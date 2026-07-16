# Changelog

All notable changes to this project will be documented in this file.

## v3.3.5 (2026-07-16)

### Other Changes
- chore: update build scripts
- chore: sync build and check scripts
- chore: update CHANGELOG.md [skip ci]

## v3.3.4 (2026-07-16)

### Added
- feat: replace SAF with MediaStore channel for silent local backup folder creation

### Other Changes
- docs: update readme

## v3.3.3 (2026-07-15)

### Added
- feat: local first backups now

### Fixed
- fixes here and there
- fix: harden crypto, backup and local-DB layer from full-codebase review

### Other Changes
- firestore changes and backed google OAuth changes

## v3.1.2 (2026-07-08)

### Added
- feat(localDB): add local first on device db, backed by firestore sync + drive backup

## v2.5.25 (2026-07-08)

### Other Changes
- add snaps to backup function and fix chat scrolling smoothness

## v2.5.22 (2026-07-07)

### Added
- feat(settings): add in partner info and variables
- feat: added voice note feature over firestore
- feat(E2EE): encrpytion tests at device
- feat: added E2EE for the app
- feat: user can now save snaps and add Google Drive backup
- feat: added polaroid frame to pictures and captions
- feat: Add post-creation editable metadata for to-dos, and implement sticky notes archiving memory vault
- feat: Add close proximity breathing heart UI transition inside compass card for distances under 6 meters
- feat: Resolve proximity deadlocks, speed up compass ticks, and expand native music intent receiver for YT Music/Apple Music/Spotify playback states
- feat: Add RTDB AirTag Proximity Radar at 3Hz with glowing emerald card theme
- feat: Remove close button from search fields to leverage native swipe-to-back exit logic
- feat: Close button immediately exits/closes search bar directly
- feat: Always show search bar close button to clear queries or exit search view easily
- feat: Scale down header and margins to fit Poke card on screen, and create unified modern search bars
- feat: Move compass card to top, show clean direction arrow, add battery/music telemetry, and fix sticky note flickering
- feat: Implement Real-Time Love Compass with native sensor EventChannel and premium Glassmorphic UI
- feat: make sticky notes tapable to open an elegant love letter dialog reader
- feat: simplify sticky notes UI, remove section header, and integrate elegant Add Sticky note card at index 0
- feat: add real-time partner phone battery percentage tracking and beautiful status indicators on Home screen
- feat: sleeker shared to-do tiles, sub-task checklists with progress indicators, and FCM notification sender-name fixes, bump to v1.5.1
- feat: implement cost-free Action-Based LastSeen Presence with 1-minute Active threshold, eliminating stale force-close indicators
- feat: relocate presence indicator to premium home header and chat appbar subtitles, decluttering home dashboard
- feat: implement real-time Sticky Notes bulletin board and native Apple Music Playback Syncing
- feat: elevate chat UI/UX with premium scroll-to-bottom FAB, floating reply banners, and capsule docks
- feat: add tactile haptics to comments and poke, markdown update release notes rendering, and version bump v1.4.4
- feat(todo): add completed tasks collapsible toggle and sort chronologically, bump to v1.4.3
- feat(todo): upgrade to-do capabilities, interactions, serverless diagnostics, and bump to v1.4.0
- feat: implement WebRTC voice calling with Oracle signaling and CallKit UI v1.1.7
- feat: fix audio relay + notifications for v1.1.6
- feat: implement Firebase RTDB audio relay with Opus compression (v1.1.5)
- feat(chat): move timestamp inside bubble; show actual time for messages >59m old
- feat(home): green Call button in quick actions
- feat(calls): proximity sensor — screen dims when held to ear
- feat(updates): check on every resume; separate download progress dialog
- feat(calls): incoming call ringing UI, ringtone, and full-screen notification
- feat: WebRTC P2P voice calls via Firestore signalling
- feat: paginated chat, scroll-to-message, full-history search
- feat: back button goes to home, add all permissions, fix APK install flow
- feat: push notifications for poke, chat, todo and comments
- feat: add live location sharing with Google Maps, fix keystore workflow
- feat: auto-update via GitHub Releases
- feat: push notifications (chat, poke, todo, comments) + security rules
- feat: todo details + comment delete, chat read receipts
- feat: Google-only login, wire quick actions, todo item comments
- feat: wire up Firebase — auth, Firestore, Google Sign-In with email allowlist

### Fixed
- fix(backup): add app wide google backup architecture
- fix(voice-notes): fix new voice notes not being played back correct
- fix: google sign in issue
- fix(google-sign-in): stop background authorizeScopes call causing repeat login prompts
- fix(OAuth): google drive scope requests fixed
- fix(OAuth): fix google login
- fix: snap cipher text not decoded at homescreen
- fix: gdrive backup not being deleted
- fix: issue with google login and log out
- fix(snaps): caption saved in the wrong font
- fix: snaps not showing up correctly in the gallery
- fix downlaoding and saving snaps
- fix: timestamp on the snaps
- fix keys for app building
- fix github build failing
- fix sticky notes not showing under archive
- fix: Lock all Firebase dependencies to compatible exact versions, preventing build failure in Gradle release builds
- fix: add receiver exported flag to dynamic music receiver to resolve Android startup crash
- fix: increase offer wait time and force signaling init on accept
- fix: restore full call_screen class structure and clean build parameters
- fix: resolve syntax errors and invalid callkit parameters
- fix: resolve syntax errors and invalid callkit parameters
- fix: mount RTCVideoRenderer to play remote audio stream
- fix: adjust Android CallKit params for full-screen wake-up
- fix: foreground call routing and migrate notifications to self-hosted server
- fix: implement hybrid signaling with FCM wake-up and CallKit bugfixes
- fix: resolve WebRTC build errors and name collisions
- Fix opus_flutter_android NDK minSdk by setting flutter.minSdkVersion=21 in gradle.properties
- fix(android): use maxOf(flutter.minSdkVersion, 21) for opus_flutter_android
- fix(android): bump minSdk to 21 for opus_flutter_android NDK requirement
- fix: resolve compilation errors in audio_relay_service.dart
- fix(chat): rename Ray to Raayyy in header; remove meaningless green dot
- fix(settings): read version dynamically from package_info_plus
- fix(calls): pre-gather TURN candidates to prevent ICE timing failure
- fix(calls): fix no-audio, add TURN servers, wire speaker toggle, fix ICE race
- fix(calls): queue ICE candidates until remote desc is set; prevent double-dispose
- fix: remove focus border and add padding on SearchScreen AppBar TextField
- fix: decode secrets before analyze step
- fix: use echo for key.properties, add keystore verification step
- fix: use release keystore for signing, bump version to 1.0.2
- fix: grant workflow contents:write permission for GitHub Releases
- fix: add assets/images directory for GitHub Actions build

### Other Changes
- chore(notifications): remove test and dead code
- security: remove hardcoded emails/API key, inject secrets via CI
- chore(logs): added more logs for google drive for bug fixing
- make backup system more robust and update docs
- update build dependencies
- bump workflow
- updated github actions
- removed dead code
- added foreground vibration and updated the unread counter logic for inactive tabs
- improvements to chat and chat counter
- automatic scope verification and self-healing logout system
- Backup encryption key if it doesnt exist online
- extend encryption to all aspects of the app
- update github build process
- changes to snap
- streamline github builds and releases
- treat tether notifs as conversation so they land higher up
- change stamp on snap, unread chat counter, grammar fixes
- remove debug fallback & enforce release signing
- optimised code for firestore and removed location pings
- added github actions build script
- docs: add release notes for v1.6.2
- refactor: modularize HomeScreen, add Unassigned to Todo, fix R8 TypeToken crash and deploy firestore rules
- refactor: Remove partner battery status from header; keeping only on Love Compass card
- chore: Bump version to v1.6.0
- bump: upgrade version to 1.5.2+31
- style: convert sticky notes timestamps explicitly to Indian Standard Time (IST)
- style: shrink Add Sticky card to compact size and place at the far right of the scroll view
- style: remove presence status from chat screen, reposition sticky notes to top of home screen, and make sticky notes header sleeker
- bump version to v1.5.0
- perf(size): remove unused heavy native dependencies and bump to v1.4.2
- perf(android): enable parallel and cached gradle builds for faster compilation
- style(todo): implement high-premium stacked card presentation for tasks and bump to v1.4.1
- Import flutter/services.dart to resolve HapticFeedback compiler error in main_shell.dart (v1.3.0)
- Safely isolate each sequential permission phase in separate try-catch blocks to prevent aborts (v1.3.0)
- Refactor permissions to sequential flows to prevent Android platform crashes and blocks (v1.3.0)
- Purge voice calling, remove image attachment triggers, and implement comprehensive startup permission gate for Android (v1.3.0)
- 1.2.1 added some anims and stuff in chat
- Bump version to 1.2.0: Re-designed voice calling screen, fixed WebRTC signaling serverlessness using direct FCM HTTP v1 REST client, resolved connection socket leaks/crashes, and implemented optimized cached image sharing in chat
- chore: bump version to v1.1.9
- chore: bump version to v1.1.8 and add release notes
- refactor: move call notification logic to signaling server
- Remove all call features for ground-up rewrite
- Suppress NDK CXX1110 error from opus_flutter_android hardcoded minSdk=19
- chore: bump version to 1.1.4 and consolidate logging/call fixes
- chore: bump version to 1.1.3+13
- chore: bump version to 1.1.2+12
- chore: bump version to 1.1.1+11
- chore: bump version to 1.1.0+10
- v1.0.9 — fix Firestore path regression (restore chats & to-dos)
- refactor: consolidate presence logic and revert 'Raayyy' identifiers
- v1.0.8 — scrollable update dialog + install permission prompt
- v1.0.7 — refactor, settings screen, location ping, poke improvements
- v1.0.6 — search, distance card, online presence, notifications
- chore: bump version to 1.0.3
- chore: ignore functions build output and node_modules
- chore: set together-since date to Apr 9, 2026
- chore: update google-services.json with SHA-1 for Google Sign-In
- chore: update Aproo's email in allowlist
- chore: add Google services Gradle plugin for Firebase
- chore: update package name to com.theawesomeray.tether
- chore: update package name to com.raynaproo.tether
- Initial Tether app — Ray & Aproo couples app

