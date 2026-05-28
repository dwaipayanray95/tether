# Feature Map

Use this map to identify which files to read or modify when editing specific app features:

### 💬 Chat & Messages
- **Message Bubble Appearance:** `chat_screen.dart` → `_MessageBubble` widget (bottom of file).
- **Timestamp Formatting:** `chat_screen.dart` → `_formatTimestamp()`.
- **Pagination Configuration:** `chat_screen.dart` → `_loadInitialMessages()`, `_loadMore()`.
- **Reply to Message Behaviour:** `chat_screen.dart` → `_replyTo` state + `_buildInput()`.
- **Message Scroll & Highlight:** `chat_screen.dart` → `scrollToMessageById()`.
- **Emoji Reactions:** `chat_screen.dart` → `_ReactionPicker`, `_MessageBubble.onReaction`.
- **Unread Badge Counts:** `firestore_service.dart` → `unreadCountStream()`, `markMessagesRead()`.
- **Message Search Overlays:** `search_screen.dart` + `firestore_service.dart` → `getAllMessages()`.
- **Image Sending Flows:** `chat_screen.dart` → `_pickAndSendImage()`.
- **Firestore Messaging Reads/Writes:** `firestore_service.dart` → `messageStream()`, `sendMessage()`, `fetchMessagePage()`.

### 🏠 Home Screen & Presence
- **Distance Card Calculation:** `home_screen.dart` → `_buildDistanceCard()`.
- **Online presence / last seen:** `home_screen.dart` → `_buildLastSeen()` + `firestore_service.dart` → `presenceStream()`.
- **Poke Interactions:** `home_screen.dart` → `_sendPoke()` + `firestore_service.dart` → `sendPoke()`.
- **Quick Action Layouts:** `home_screen.dart` → `_buildQuickActions()`.

### 🔔 Notifications & FCM
- **Outbound FCM Calls:** `fcm_service.dart` → `send()` (HTTP v1 payload styling with service account key).
- **FCM Service Credentials:** `config/notification_config.dart`.
- **Foreground Handlers:** `notification_service.dart` → `FirebaseMessaging.onMessage`.
- **Background Handlers:** `notification_service.dart` → `firebaseMessagingBackgroundHandler`.

### 🔄 Auto-Update & Diagnostics
- **Release check:** `update_service.dart` → `checkForUpdate()`.
- **Release dialogues:** `widgets/update_dialog.dart` (re-route UI alerts for updating APKs).
- **Logging logic:** `settings_screen.dart` + `log_service.dart` + `diagnostics_screen.dart`.
