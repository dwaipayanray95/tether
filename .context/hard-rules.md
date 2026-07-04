# Hard Rules

These are the critical rules that must always be followed without exception when working on Tether.

| Rule | Detail |
|------|--------|
| **Never push to GitHub** | Do not run `git push`, `git tag`, or `gh release create` unless the user explicitly asks in that message |
| **Never bump `pubspec.yaml`** | The user will manually bump version codes henceforth. Do not auto-increment version code. |
| **Never change `coupleId`** | It is always `'ray-aproo'` — loaded from the gitignored `lib/config/env_config.dart` file. |
| **Never change allowed emails** | `ray@redacted.invalid` = Ray, `aproo@redacted.invalid` = Aproo — loaded from `lib/config/env_config.dart`. |
| **Name comparison is case-sensitive** | `fromName == 'Ray'` (capital R). Partner key strings are lowercase `'ray'` / `'aproo'` |
| **Always run `flutter analyze` before committing** | Fix all errors and warnings first |
