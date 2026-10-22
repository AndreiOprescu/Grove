# Bedtime reminder — proof

The owner asked: "use some sort of detection system to figure out when I am awake, and when I go to sleep. Maybe by using screen time detections. maybe try to do some sort of statistical approach, because maybe on certain days I go to sleep earlier or later than others. with that, I want you to send me a friendly notification, on my phone and on my laptop that I should plan my next day. Tell me like 1 hour and 30 minutes before I would normally go to sleep. The sleep and wakeup lines arent always accurate so dont just rely on those"

The owner's answers of 2026-10-22 are decisions 1–9 below. Decision record: `docs/adr/0005-bedtime-from-device-activity.md`. Words: `CONTEXT.md` › Sleep. Rules decided on the way: `docs/assumptions.md` (lines "2026-10-22 · Bedtime reminder").

Branch `feat/next-version` (draft PR #48, version 1.2.0).

Check: `./scripts/flutter_test.sh` (2026-10-22, on this Mac): format clean, analyze clean, pure-Dart check clean, all tests passed. `flutter build apk --debug` and `flutter build macos --debug` build.

## What the user sees

- Settings › Notifications has a "Bedtime" section: "Remind me to plan tomorrow before bed" (on), the lead (1 hour, 1½ hours, 2 hours; 1½ by default), and a line "Tonight: usually asleep around 23:40, reminder at 22:10."
- On Android a card asks to turn on Usage access, with a button that opens that system page.
- On the Mac a section "On this Mac" has "Open Grove at login" (on after the first start). Closing the window keeps Grove in the menu bar.
- Each evening, the lead before the usual bedtime, a warm notification asks to plan tomorrow, or to check tomorrow's plan when it has things. A tap opens the Planner on tomorrow.

## Each decision

| # | Decision | Proof |
|---|---|---|
| 1 | Learn from the phone (Usage access) and the Mac (lock, sleep, wake); iOS and Windows only get the reminder | `MainActivity.kt` (`grove/activity`), `ActivityRecorder.swift`, `MainFlutterWindow.swift`; `AppServices.activitySource`; `test/services/device_activity_source_test.dart`; `sleep_store_test.dart` "one per night before the usual bedtime" (no source) |
| 2 | An early phone alarm makes the bedtime earlier | `sleep_stats_test.dart` (alarm group); `bedtime_planner_test.dart`; `sleep_store_test.dart` "an early alarm makes the reminder earlier, also with no Usage access" |
| 3 | Only one row per night syncs; no events, no app names, no alarm | `sleep_night_rules_test.dart` (the exact JSON); `sleep_store_test.dart` "only the night row syncs: no events, no alarm, no planner line" and "the part of another device is kept" |
| 4 | Usual bedtime: 4 same weekdays → 14 nights → sleep line → 23:00 | `sleep_stats_test.dart` |
| 5 | Detection never moves the wake-up or sleep line | `sleep_store_test.dart` "only the night row syncs: …" (no `planner.` key written) |
| 6 | Always sent, two kinds of text, a tap opens the Planner on tomorrow | `bedtime_planner_test.dart` (both texts, "today" after midnight); `system_notifier_test.dart` "a bedtime reminder opens the planner on its day"; `sleep_store_test.dart` "on a bedtime reminder opens the planner on its day" |
| 7 | On/off and lead 60/90/120 (90), synced | `sleep_store_test.dart` "the switch and the lead are synced settings rows, no undo step"; `settings_view_test.dart` "the bedtime switch and its lead" |
| 8 | Mac: close hides to the menu bar; open at login, on by default, starts hidden | `AppDelegate.swift`, `MainFlutterWindow.swift`; `sleep_store_test.dart` "open at login (Mac)" group; `settings_view_test.dart` "Open Grove at login" |
| 9 | Warm and short, a few texts | `bedtime_planner_test.dart` (stable per night, more than one text over nights) |

## Not verified yet

- On the phone (`RZCY80AVTDT`): the phone was not connected on 2026-10-22. To check: install, turn on Usage access from the card, use the phone one evening, and see the night row and the reminder the next day.
- On the Mac: the new build was not installed, so hiding on close, the login start and the lock events were built but not tried. To check: `./scripts/flutter_install.sh`, close the window, lock and unlock, then `defaults read local.grove.app grove.activity`.
- Two devices on the same night (both parts in one row).
