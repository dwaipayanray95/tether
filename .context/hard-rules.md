# Hard Rules

These are the critical rules that must always be followed without exception when working on Tether.

| Rule | Detail |
|------|--------|
| **Never push to GitHub** | Do not run `git push`, `git tag`, or `gh release create` unless the user explicitly asks in that message |
| **Never bump `pubspec.yaml` version** | Do not change `version:` in pubspec unless the user explicitly asks and confirms the number |
| **Never change `coupleId`** | It is always `'ray-aproo'` — hardcoded across Firestore paths |
| **Never change allowed emails** | `dwaipayanray95@gmail.com` = Ray, `apoo.0404@gmail.com` = Aproo |
| **Name comparison is case-sensitive** | `fromName == 'Ray'` (capital R). Partner key strings are lowercase `'ray'` / `'aproo'` |
| **Always run `flutter analyze` before committing** | Fix all errors and warnings first |
