# Database Schemas

Tether uses Google Cloud Firestore for metadata and state storage. Realtime Database (RTDB) is no longer actively used since Calling has been removed.

## Firestore Schema

All couple data lives under the root collection `couples/` with the document ID `ray-aproo`.

```text
couples/ray-aproo/
  ├── messages/{msgId}
  │     text: String,
  │     fromUid: String,
  │     fromName: String,
  │     sentAt: Timestamp,
  │     readBy: Array<String>,
  │     readTimes: Map<String, Timestamp>,
  │     reactions: Map<String, Array<String>>,
  │     replyToId: String?,
  │     replyToText: String?,
  │     imageUrl: String?
  ├── todos/{todoId}
  │     title: String,
  │     done: Boolean,
  │     createdBy: String,
  │     createdAt: Timestamp,
  │     comments: Array<CommentMap>
  ├── pokes/status
  │     lastFrom: String (uid),
  │     fromName: String,
  │     sentAt: Timestamp
  ├── fcmTokens/
  │     ray    { token: String }
  │     aproo  { token: String }
  
  [DEPRECATED / REMOVED SCHEMA]
  ├── status/presence
  │     ray   { isOnline: Boolean, lastSeen: Timestamp }
  │     aproo { isOnline: Boolean, lastSeen: Timestamp }
  ├── calls/{callId} (Obsolete - Call features removed)
```

## Firebase Realtime Database Schema

```text
[DEPRECATED / REMOVED SCHEMA]
audio_relay/
  {callId}/ (Obsolete - Voice Calls & streaming RTDB packages are removed)
```
