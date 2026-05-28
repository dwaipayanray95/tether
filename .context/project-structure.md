# Project Structure

Tether is built using Flutter (Dart) and standard Android Native configuration. Calling and proximity features have been completely removed.

```text
lib/
├── main.dart                    # App entry point: Firebase init, auth gate
├── config/
│   └── notification_config.dart # FCM service account credentials (private)
├── models/
│   ├── message_model.dart       # Message (id, text, fromUid, fromName, sentAt, readBy, reactions, replyTo*)
│   ├── todo_model.dart          # TodoItem (id, title, done, createdBy, createdAt)
│   ├── comment_model.dart       # Comment on todos
│   └── user_model.dart          # Basic user data
├── screens/
│   ├── main_shell.dart          # Root scaffold: bottom nav, update check, handles pending notification
│   ├── home_screen.dart         # Home tab: distance card, poke, presence, quick actions (Chat/Todo)
│   ├── chat_screen.dart         # Chat tab: paginated messages, search, reply, reactions
│   ├── search_screen.dart       # Full-history message search overlay
│   ├── todo_screen.dart         # Shared to-do list and comments
│   ├── login_screen.dart        # Google Sign-In gate
│   ├── settings_screen.dart     # App version (dynamic), sign out, diagnostics link
│   ├── diagnostics_screen.dart  # Log viewer (enable/disable logging, view/clear logs)
│   └── location_screen.dart     # Partner location map
├── services/
│   ├── auth_service.dart        # Firebase Auth + Google Sign-In; isRay, myName, partnerName
│   ├── firestore_service.dart   # All Firestore reads/writes (messages, todos, presence, poke, unread)
│   ├── fcm_service.dart         # Sends FCM via HTTP v1 API with service-account JWT
│   ├── notification_service.dart# FCM receive handling (foreground/background) & local notifications
│   ├── location_service.dart    # Geolocator + Firestore location upload/stream
│   ├── update_service.dart      # GitHub Releases API check + APK download & install
│   ├── log_service.dart         # File-based debug logging (toggled in Settings/Diagnostics)
│   └── nav_service.dart         # Global navigatorKey for navigation from outside widget tree
├── theme/
│   └── app_theme.dart           # Colours, typography, component themes (coral #E8715A palette)
└── widgets/
    └── update_dialog.dart       # Two-dialog update flow: release notes → download progress
```

```text
android/
└── app/src/main/kotlin/com/theawesomeray/tether/
    └── MainActivity.kt          # Clean, default FlutterActivity (no custom MethodChannels)
```
