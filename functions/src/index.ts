/**
 * Cloud Functions for Tether.
 *
 * Two functions, both existing to unblock headless (background, no
 * foreground Activity) Google Drive backup sync — see AGENTS.md /
 * working.md for the full investigation. Summary:
 *
 * BackupService's Drive uploads need a Google OAuth access token. Today
 * that token comes from the `google_sign_in` Flutter plugin's session,
 * which only works while the app has a foreground Activity — verified by
 * testing from a WorkManager background isolate, where Firestore/crypto
 * worked fine but every Drive call failed with "Google Sign-In user is not
 * available." That's why backups currently only run on app open/resume.
 *
 * The fix: exchange a one-time Google `serverAuthCode` (obtained on the
 * client during sign-in, with offline access requested) for a real OAuth
 * refresh_token (exchangeGoogleAuthCode, below), then use that refresh
 * token to mint fresh Drive access tokens on demand (refreshDriveAccessToken,
 * below) — both callable from anywhere, including a headless WorkManager
 * isolate, with no Google Sign-In plugin/session/Activity involved.
 *
 * IMPORTANT — both steps need the client secret, not just the first one:
 * a Google "Web application" OAuth client (a confidential client type,
 * which this must be, since only Web/server clients can request offline
 * access this way) requires client_secret on the *original* code exchange
 * AND on every subsequent refresh_token grant — confirmed against Google's
 * "Using OAuth 2.0 for Web Server Applications" docs. There is no
 * secret-free refresh path for this client type. That means minting a
 * Drive access token can never happen purely on-device — it always needs
 * this function, on every single backup run, not just once at sign-in.
 * The stored refresh_token itself is what's cheap to keep on-device;
 * turning it into a usable access token always makes one lightweight
 * Cloud Functions round trip.
 *
 * ── Required one-time setup before this can be deployed/used ──────────────
 *
 * 1. In Google Cloud Console (the same project as this Firebase project,
 *    tether-8d3fa): APIs & Services > Credentials > Create Credentials >
 *    OAuth client ID > Application type "Web application". This is
 *    SEPARATE from the existing Android OAuth client Tether already uses
 *    for sign-in. No redirect URI is needed for this flow.
 * 2. Set the two secrets this function needs (never commit these):
 *      firebase functions:secrets:set GOOGLE_WEB_CLIENT_ID
 *      firebase functions:secrets:set GOOGLE_WEB_CLIENT_SECRET
 *      firebase functions:secrets:set ALLOWED_EMAILS
 *    (ALLOWED_EMAILS: comma-separated, e.g. "a@x.com,b@y.com" — mirrors
 *    firestore.rules'/storage.rules' allowlist; kept as a secret here
 *    rather than hardcoded so this file never contains real emails.)
 * 3. On the client (google_sign_in v7), request offline access with that
 *    Web client ID as `serverClientId` when signing in, to get a
 *    serverAuthCode back.
 * 4. `cd functions && npm install && npm run deploy`
 * 5. Your Google OAuth consent screen must be in "Production" status, not
 *    "Testing" — in Testing mode, refresh tokens auto-expire after 7 days,
 *    which would silently break background sync a week after every
 *    sign-in.
 */

import {onCall, HttpsError} from "firebase-functions/v2/https";
import {defineSecret} from "firebase-functions/params";
import * as logger from "firebase-functions/logger";

const googleWebClientId = defineSecret("GOOGLE_WEB_CLIENT_ID");
const googleWebClientSecret = defineSecret("GOOGLE_WEB_CLIENT_SECRET");
const allowedEmails = defineSecret("ALLOWED_EMAILS");

interface ExchangeRequest {
  serverAuthCode: string;
}

interface RefreshRequest {
  refreshToken: string;
}

interface GoogleTokenResponse {
  access_token?: string;
  refresh_token?: string;
  expires_in?: number;
  error?: string;
  error_description?: string;
}

/// Same allowlist model as firestore.rules/storage.rules — both functions
/// below must never be callable by an arbitrary signed-in Firebase user,
/// since a valid Firebase project API key is not itself a secret (it's
/// compiled into the app). Auth is required AND the caller's email must
/// be on the allowlist. Throws HttpsError directly, so callers just
/// invoke this first and let it throw.
function requireAllowedCaller(
  authEmail: string | undefined,
  allowedEmailsCsv: string
): string {
  const callerEmail = authEmail?.toLowerCase();
  if (!callerEmail) {
    throw new HttpsError("unauthenticated", "Sign-in required.");
  }
  const allowed = allowedEmailsCsv.split(",").map((e) => e.trim().toLowerCase());
  if (!allowed.includes(callerEmail)) {
    logger.warn("rejected caller", {callerEmail});
    throw new HttpsError("permission-denied", "This account is not allowed.");
  }
  return callerEmail;
}

export const exchangeGoogleAuthCode = onCall<ExchangeRequest>(
  {secrets: [googleWebClientId, googleWebClientSecret, allowedEmails]},
  async (request) => {
    const callerEmail = requireAllowedCaller(request.auth?.token.email, allowedEmails.value());

    const serverAuthCode = request.data?.serverAuthCode;
    if (!serverAuthCode || typeof serverAuthCode !== "string") {
      throw new HttpsError("invalid-argument", "serverAuthCode is required.");
    }

    const params = new URLSearchParams({
      code: serverAuthCode,
      client_id: googleWebClientId.value(),
      client_secret: googleWebClientSecret.value(),
      grant_type: "authorization_code",
      // Empty redirect_uri is correct for the Android offline-access
      // (serverAuthCode) flow — this is not a browser redirect flow.
      redirect_uri: "",
    });

    const response = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: {"Content-Type": "application/x-www-form-urlencoded"},
      body: params.toString(),
    });

    const data = (await response.json()) as GoogleTokenResponse;

    if (!response.ok) {
      // Never log the request body (contains the auth code) or response
      // body (would contain the refresh token if present) — only the
      // error fields, which don't carry secrets.
      logger.error("exchangeGoogleAuthCode: token exchange failed", {
        status: response.status,
        error: data.error,
        errorDescription: data.error_description,
      });
      throw new HttpsError(
        "internal",
        `Google token exchange failed: ${data.error ?? "unknown error"}`
      );
    }

    if (!data.refresh_token) {
      // Google omits refresh_token on a code exchange when this Google
      // account has already granted this Web client offline access before
      // (e.g. re-signing in after an uninstall wiped the client's stored
      // token, but the server-side grant is still on file) — the exchange
      // itself succeeded, there's just nothing new to hand back. This is
      // NOT the same failure as the block above, so it gets its own code
      // ("failed-precondition", distinct from "internal") — the client
      // uses that to trigger a one-time disconnect+re-authorize instead of
      // silently giving up on background sync forever.
      logger.warn("exchangeGoogleAuthCode: exchange succeeded but no refresh_token " +
        "returned (likely already-granted offline access)", {callerEmail});
      throw new HttpsError(
        "failed-precondition",
        "no_refresh_token: Google did not return a refresh token for this grant."
      );
    }

    logger.info("exchangeGoogleAuthCode: refresh token issued", {callerEmail});

    // Only the refresh_token is useful to the client long-term (it mints
    // its own access tokens from here on) — the access_token this
    // exchange also returns is short-lived and not worth passing back.
    return {refreshToken: data.refresh_token};
  }
);

/// Mints a fresh Drive-scoped access token from a stored refresh_token.
/// Called on every headless background backup run (see
/// HeadlessDriveTokenService on the client) — unlike exchangeGoogleAuthCode,
/// this is NOT a one-time call, since a Web-application-type OAuth client
/// requires client_secret on every refresh grant, not just the original
/// code exchange (see this file's top doc comment). Callable from a
/// background isolate the same way Firestore already is — both go through
/// Firebase's own auth/App Check layer, not Google Sign-In's session.
export const refreshDriveAccessToken = onCall<RefreshRequest>(
  {secrets: [googleWebClientId, googleWebClientSecret, allowedEmails]},
  async (request) => {
    requireAllowedCaller(request.auth?.token.email, allowedEmails.value());

    const refreshToken = request.data?.refreshToken;
    if (!refreshToken || typeof refreshToken !== "string") {
      throw new HttpsError("invalid-argument", "refreshToken is required.");
    }

    const params = new URLSearchParams({
      refresh_token: refreshToken,
      client_id: googleWebClientId.value(),
      client_secret: googleWebClientSecret.value(),
      grant_type: "refresh_token",
    });

    const response = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: {"Content-Type": "application/x-www-form-urlencoded"},
      body: params.toString(),
    });

    const data = (await response.json()) as GoogleTokenResponse;

    if (!response.ok || !data.access_token) {
      // "invalid_grant" here specifically means the refresh token itself
      // was revoked/expired (user revoked access, or unused >6 months) —
      // the client should treat that as "re-run setupAfterSignIn() next
      // time the app is foregrounded," not retry immediately.
      logger.error("refreshDriveAccessToken: refresh failed", {
        status: response.status,
        error: data.error,
        errorDescription: data.error_description,
      });
      throw new HttpsError(
        data.error === "invalid_grant" ? "failed-precondition" : "internal",
        `Google token refresh failed: ${data.error ?? "unknown error"}`
      );
    }

    return {accessToken: data.access_token, expiresIn: data.expires_in};
  }
);
