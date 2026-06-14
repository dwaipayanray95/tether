# Release Notes — Tether v1.6.2

Welcome to Tether version 1.6.2! This update focuses on performance refactoring, feature enhancements, and critical bug fixes to make the app incredibly stable and responsive.

## 🚀 Key Highlights & New Features

### 1. HomeScreen Architecture Refactoring (Performance Booster)
- Completely modularized the giant `home_screen.dart` into isolated, focused widgets inside `lib/widgets/home/`.
- Isolated high-frequency updates (like the 60 FPS compass pointer needle and geolocator streams) to only rebuild their respective components. This eliminates full-screen rebuild lag and ensures a buttery-smooth user experience.

### 2. Flexible Todo Assignee Support
- Added a new **"Unassigned"** chip option during task creation (active by default).
- Added the ability to remove/clear the assignee from a task entirely (setting it to Unassigned) from the task details panel.
- Tasks assigned to both partners are clearly labeled as **"👤 Both"**.
- Unassigned tasks clean up card space by automatically hiding the assignee badge.

### 3. Visual & Interaction Improvements
- Changed the sticky note peel off dialog button to **"Peel off"** instead of "Archive" to match the board metaphor.
- Refined the Sticky Board header button into a sleek, clean, **icon-only archive folder button**.
- Integrated APNs high-priority push flags (`apns-priority: 10`) and Android maximum priority (`PRIORITY_MAX` + default sound & vibration) to ensure all notifications land on top of the system stack.

---

## 🐛 Bug Fixes & Diagnostics

- **Resolved Database Expiry Crash**: Updated and redeployed permanent security rules to Firebase Firestore, fixing the expired 30-day template rules that triggered `permission-denied` errors.
- **Fixed ProGuard/R8 TypeToken Obfuscation**: Added rules to preserve generic signatures during release compilation, resolving the Android crash that occurred during todo synchronization.
- **Diagnostics and Error Checking**: Added error boundaries to active Firestore streams to show debug info rather than infinite loading spinners.
