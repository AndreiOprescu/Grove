# Grove — rules for the builder

- Grove is a Flutter app in `app/` for macOS, Windows, Android and iOS. Decision: `docs/adr/0001-cross-platform-flutter-supabase.md`. Plan and milestones: `docs/cross-platform-plan.md`.
- `PLAN.md` is the spec of what Grove does. It was written for the first (Swift) app, and it still says how each feature must behave. Read §0 CHOICES first. Its build rules (§2, §3, §11 to §14) were for the Swift app, which is gone. They are history.
- Visual reference: `design/layouts.html` (open in a browser). The Day Planner demo there is the behaviour to match.
- The Day Planner (§5.1) is the most important feature.
- Tests: `./scripts/flutter_test.sh` · Build: `./scripts/flutter_build.sh macos|ios|android|appbundle|windows` · Release files: `./scripts/flutter_release.sh macos|windows|android|ios` · Install on this Mac: `./scripts/flutter_install.sh`
- `app/lib/core`, `app/lib/data` and `app/lib/sync` are pure Dart: no Flutter imports. The test script checks it.
- No new package without a yes from the owner.
- Never commit `app/config/supabase.json`. It holds the keys of the Supabase project.
- The first Grove (Swift, macOS only) was taken out of the repo on 2026-10-12. Its code is in the git history before that day. The app id is `local.grove.app` (`docs/acceptance/retire-swift.md`).
- Work on a branch `feat/<topic>`, made from `main`. Until the Flutter branch is merged into `main`, make it from `feat/cross-platform-flutter`. Never commit on main. Stage exact paths. No AI attribution.
- Log every decision you make that the plan does not cover in `docs/assumptions.md`. Questions for the owner go in `docs/questions.md`.
