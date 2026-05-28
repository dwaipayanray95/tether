# Key Constants & Configurations

These are the core hardcoded constants, credentials, helper guidelines, styling colors, and routing schemas used in Tether.

## Core Constants

- **Couple Identifier:** `const coupleId = 'ray-aproo';` (never change, hardcoded in Firestore paths).
- **Authorized Emails:** `const allowedEmails = ['ray@redacted.invalid', 'aproo@redacted.invalid'];`

## Auth & Name Mapping

- `AuthService().isRay` - returns `true` if current user is Ray.
- `AuthService().myName` - returns `'Ray'` or `'Aproo'` (first letter capitalized).
- `AuthService().partnerName` - returns opposite of myName.
- **Lowercase keys:** Use lowercase `'ray'` / `'aproo'` when targeting presence documents, FCM tokens.

## Notification Channels

- `tether_updates_v1` - Default notification channel for messages, pokes, and todo updates.
- Note: The high-importance call channel `tether_calls_v1` has been fully removed.

## Color Palette & Typography (`app_theme.dart`)

```dart
AppTheme.primary       // #E8715A  Warm Coral — Primary action buttons, active icons, accents
AppTheme.primaryLight  // #FFF0EE  Light Coral — Backdrops for tinted action tiles
AppTheme.secondary     // #B5838D  Muted Rose
AppTheme.background    // #FAF8F6  Warm Off-White Scaffold
AppTheme.surface       // #FFFFFF  Cards, Chat Bubbles, Sheet containers
AppTheme.textDark      // #2D2D2D  Main headings, body copy
AppTheme.textMuted     // #9E9E9E  Subtitles, minor details
AppTheme.divider       // #F0EDED  Subtle lines
```

- **Body Typography:** DM Sans
- **Headings & Hero Copy:** Playfair Display

## FCM Send Rules & Targets

- **Primary Handler:** Always send push alerts using `FcmService.send()`.
- **Ignore / Disabled Payloads:** Payloads targeting types `'call_ping'` or `'call_ended'` are ignored by client handlers.
- **Partner target resolution:** `AuthService().partnerName.toLowerCase()` targets `'ray'` or `'aproo'`.
