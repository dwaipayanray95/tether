# Hard Rules

These are the critical rules that must always be followed without exception when working on Tether.

| Rule | Detail |
|------|--------|
| **Never push to GitHub** | Do not run `git push`, `git tag`, or `gh release create` unless the user explicitly asks in that message |
| **Always bump `pubspec.yaml` version to +0.0.1 unless the user explicitly asks to update the version to a new one and then continue the logic from there** |
| **Never change `coupleId`** | It is always `'ray-aproo'` — hardcoded across Firestore paths |
| **Never change allowed emails** | `dwaipayanray95@gmail.com` = Ray, `apoo.0404@gmail.com` = Aproo |
| **Name comparison is case-sensitive** | `fromName == 'Ray'` (capital R). Partner key strings are lowercase `'ray'` / `'aproo'` |
| **Always run `flutter analyze` before committing** | Fix all errors and warnings first |
