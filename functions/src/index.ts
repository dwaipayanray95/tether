import * as admin from "firebase-admin";
import * as functions from "firebase-functions";

admin.initializeApp();

const db = admin.firestore();
const COUPLE_ID = "ray-aproo";

// ── Helpers ───────────────────────────────────────────────────────────────────

async function getPartnerToken(senderUid: string): Promise<string | null> {
  const snap = await db.collection("users").get();
  for (const doc of snap.docs) {
    if (doc.id !== senderUid) {
      return (doc.data().fcmToken as string) ?? null;
    }
  }
  return null;
}

async function getSenderName(senderUid: string): Promise<string> {
  const doc = await db.collection("users").doc(senderUid).get();
  return (doc.data()?.name as string) ?? "Someone";
}

async function notify(token: string, title: string, body: string): Promise<void> {
  try {
    await admin.messaging().send({
      token,
      notification: {title, body},
      android: {
        priority: "high",
        notification: {
          channelId: "tether_default",
          color: "#E8715A",
          sound: "default",
        },
      },
    });
  } catch (err) {
    functions.logger.error("FCM send failed", err);
  }
}

// ── New chat message ───────────────────────────────────────────────────────────

export const onNewMessage = functions.firestore
  .document(`couples/${COUPLE_ID}/messages/{messageId}`)
  .onCreate(async (snap) => {
    const data = snap.data();
    const token = await getPartnerToken(data.senderId);
    if (!token) return;
    const name = await getSenderName(data.senderId);
    const body = data.type === "image" ? "📷 Sent a photo" : (data.text as string);
    await notify(token, name, body);
  });

// ── New poke ──────────────────────────────────────────────────────────────────

export const onNewPoke = functions.firestore
  .document("pokes/{pokeId}")
  .onCreate(async (snap) => {
    const data = snap.data();
    const token = await getPartnerToken(data.from);
    if (!token) return;
    const name = data.fromName as string ?? "Someone";
    await notify(token, "Tether 💕", `${name} is thinking of you`);
  });

// ── New to-do item ────────────────────────────────────────────────────────────

export const onNewTodo = functions.firestore
  .document(`couples/${COUPLE_ID}/todos/{todoId}`)
  .onCreate(async (snap) => {
    const data = snap.data();
    const token = await getPartnerToken(data.createdBy);
    if (!token) return;
    const name = await getSenderName(data.createdBy);
    await notify(token, "New item on Our List", `${name} added: ${data.title}`);
  });

// ── New comment on to-do ──────────────────────────────────────────────────────

export const onNewComment = functions.firestore
  .document(`couples/${COUPLE_ID}/todos/{todoId}/comments/{commentId}`)
  .onCreate(async (snap, context) => {
    const data = snap.data();
    const todoId = context.params.todoId;

    // Get the todo title
    const todoDoc = await db
      .collection("couples")
      .doc(COUPLE_ID)
      .collection("todos")
      .doc(todoId)
      .get();
    const todoTitle = (todoDoc.data()?.title as string) ?? "a task";

    // Find the partner token by name (comment has authorName, not UID)
    const usersSnap = await db.collection("users").get();
    let partnerToken: string | null = null;
    for (const doc of usersSnap.docs) {
      if (doc.data().name !== data.authorName) {
        partnerToken = (doc.data().fcmToken as string) ?? null;
        break;
      }
    }
    if (!partnerToken) return;

    await notify(
      partnerToken,
      `Note on "${todoTitle}"`,
      `${data.authorName}: ${data.text}`
    );
  });
