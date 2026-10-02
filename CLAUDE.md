# Grove — rules for the builder

- The full spec is `PLAN.md`. Read it fully before coding. Read §0 CHOICES first.
- Visual reference: `design/layouts.html` (open in a browser). The Day Planner demo there is the behaviour to match.
- The Day Planner (§5.1) is the most important feature. Build and test it early (milestone M2).
- Build: `./scripts/build_app.sh` · Install + Desktop icon: `./scripts/install.sh` · Tests: `./scripts/test.sh`
- No Xcode on this Mac. No SwiftData. No SPM resources. No third-party packages. See PLAN.md §14.
- Work on branch `feat/grove-v1`. Never commit on main. Stage exact paths. No AI attribution.
- Log every decision you make that the plan does not cover in `docs/assumptions.md`.
