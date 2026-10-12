# Grove — rules for the builder

- Grove is a Flutter app in `app/` for macOS, Windows, Android and iOS. Decision: `docs/adr/0001-cross-platform-flutter-supabase.md`. Plan and milestones: `docs/cross-platform-plan.md`.
- `PLAN.md` is the spec of what Grove does. It was written for the first (Swift) app, and it still says how each feature must behave. Read §0 CHOICES first. Its build rules (§14) are for the Swift app only.
- Visual reference: `design/layouts.html` (open in a browser). The Day Planner demo there is the behaviour to match.
- The Day Planner (§5.1) is the most important feature.
- Tests: `./scripts/flutter_test.sh` · Build: `./scripts/flutter_build.sh macos|ios|android|appbundle|windows` · Release files: `./scripts/flutter_release.sh macos|windows|android|ios`
- `app/lib/core`, `app/lib/data` and `app/lib/sync` are pure Dart: no Flutter imports. The test script checks it.
- No new package without a yes from the owner.
- Never commit `app/config/supabase.json`. It holds the keys of the Supabase project.
- The first Grove (Swift, macOS only) is still in `Sources/` and `Tests/`: `./scripts/build_app.sh`, `./scripts/install.sh`, `./scripts/test.sh`. Change it only when the owner asks. Its rules stay: no SwiftData, no SPM resources, no third-party packages.
- Work on a branch `feat/xp-<topic>`, made from `feat/cross-platform-flutter` (from `main` after that branch is merged). Never commit on main. Stage exact paths. No AI attribution.
- Log every decision you make that the plan does not cover in `docs/assumptions.md`. Questions for the owner go in `docs/questions.md`.
