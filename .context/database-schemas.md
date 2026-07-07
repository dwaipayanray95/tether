# Database Schemas

Tether uses Google Cloud Firestore for the bulk of app data, plus Firebase Realtime
Database (RTDB) for the high-frequency proximity radar feature only. RTDB is **not**
unused — `widgets/home/compass_card.dart` writes/reads it directly via
`FirebaseDatabase.instance`.

## Firestore Schema

Per-user data lives at the top level under `users/{uid}`. Everything shared by the
couple lives under `couples/ray-aproo/`.

```text
users/{uid}
  uid: String, name: String, email: String, photoUrl: String?, coupleId: String,
  profile: { birthday?, clothingSizes: Map<String,String>, shoeSize?, ringSize?,
             allergies: [String], foodDislikes: [String], favoriteFoods: [String],
             favoriteColor?, favoriteMovies: [String] (max 5) }
  -- `profile` shape mirrors partner_profile_model.dart (PartnerProfile). Self-reported:
  -- each user edits only their own via partner_info_screen.dart's "Me" tab.
  -- The E2EE public key is NOT stored here — see couples/ray-aproo/status/presence below.
```

```text
couples/ray-aproo/
  anniversary: Timestamp?   -- shared field, either partner can edit
  ├── messages/{msgId}
  │     senderId: String, text: String (E2EE ciphertext JSON),
  │     type: 'text'|'image'|'poke'|'voice',
  │     imageUrl: String?, audioUrl: String? (E2EE ciphertext JSON), duration: Int?,
  │     sentAt: Timestamp, updatedAt: Timestamp,
  │     readBy: Array<String>, readTimes: Map<String, Timestamp>,
  │     reactions: Map<emoji, Array<uid>>, replyToId: String?, replyToText: String?
  ├── todos/{todoId}
  │     title: String (E2EE), details: String? (E2EE), isDone: Boolean,
  │     createdBy: String, createdAt: Timestamp, updatedAt: Timestamp,
  │     dueDate: Timestamp?, assignedTo: 'ray'|'aproo'|null,
  │     priority: 'low'|'medium'|'high'|null, completedAt: Timestamp?,
  │     checklist: [{id, title (E2EE), isDone}]
  │     └── comments/{commentId}   -- SUBCOLLECTION, NOT an inline array field
  │           text: String (E2EE), authorName: String, createdAt: Timestamp
  │           -- comments are immutable after creation (only deletable), so
  │           -- createdAt alone is a valid backup delta cursor for them.
  ├── sticky_notes/{noteId}
  │     text: String (E2EE), createdBy: String, createdByName: String,
  │     colorIndex: Int, createdAt: Timestamp, updatedAt: Timestamp,
  │     isArchived: Boolean, archivedAt: Timestamp?
  ├── pokes/status
  │     lastFrom: String (uid), fromName: String, sentAt: Timestamp
  ├── fcmTokens/
  │     ray    { token: String }
  │     aproo  { token: String }
  ├── deletions/{deletionId}
  │     collection: String,   // 'todos' | 'sticky_notes' | 'todos/{todoId}/comments'
  │     docId: String, deletedAt: Timestamp
  │     -- Tombstone log for the backup pipeline (backup_service.dart). A
  │     -- cursor-based "what changed since X" query never sees deletions (a
  │     -- removed doc just stops appearing) — these tombstones are the only
  │     -- way the backup applies removals without re-reading whole
  │     -- collections. Pruned once a backup run has safely captured them
  │     -- (firestore_service.dart → pruneDeletionsBefore()).
  └── status/presence  (single document — actively used, not deprecated)
        ray   { isOnline: Boolean, lastSeen: Timestamp, publicKey: String? (E2EE, X25519 base64),
                music: {track, artist, isPlaying}?, battery: {level, isCharging}? }
        aproo { isOnline: Boolean, lastSeen: Timestamp, publicKey: String?, music: {...}?, battery: {...}? }
```

```text
couples/ray-aproo/locations/{ray|aproo}
  lat: Double, lng: Double, locality: String?, updatedAt: Timestamp, name: String
```

**Why `updatedAt` on todos/messages/sticky_notes:** the backup pipeline's incremental
delta queries (`where updatedAt > cursor`) need a field that changes on every edit,
not just creation — `createdAt`/`sentAt` alone never change after the doc is created.
Every mutating write to these three collections sets `updatedAt: FieldValue.serverTimestamp()`.

## Firebase Realtime Database Schema

Used for the proximity radar (AirTag-style high-frequency location sync when
partners are close together) — see `widgets/home/compass_card.dart`.

```text
proximity_sync/
  ray-aproo/
    ray/
      lat: Double, lng: Double, active: Boolean, updatedAt: ServerValue.timestamp
    aproo/
      lat: Double, lng: Double, active: Boolean, updatedAt: ServerValue.timestamp
```

Auto-activates when distance ≤ 150m OR partner has radar active; writes at ~3 Hz
while active. `active` is set to `false` (not deleted) when radar turns off.

## Removed / Never-Existed Schema (do not reference)

- `calls/{callId}` — call signaling, removed with the voice calling feature.
- `audio_relay/{callId}` — RTDB voice-call audio streaming, removed with calling.
- Inline `comments[]` array field on todos — comments are a subcollection (see above); this was a documentation error, not a real prior schema.
