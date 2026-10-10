# F10-services · Reminders, tray, backup schedule — proof

Plan: `docs/cross-platform-plan.md` (milestone F10). Track A, branch `feat/xp-engine` (`docs/tracks.md`).
Check: `./scripts/flutter_test.sh` (2026-10-10: 1291 tests passed, analyze clean, format clean). 72 of them are new: 66 in `app/test/services/`, 6 in `app/test/state/daily_backup_test.dart`.
CI run 38065249067 (commit 90067d7): green on Android, Windows, macOS, iOS. The run before it (38064435235, commit 95e500f) was green on Windows, macOS and iOS and red on the Linux machine of the Android job: the tests could not build the tray's native library there. Commit 90067d7 adds three Linux packages to that CI job; no app code changed.

Scope (`docs/tracks.md`): "reminders on all 4 OS (`flutter_local_notifications`), system tray on Mac and Windows (`tray_manager`), backup schedule. No screens."
Acceptance of F10 in the plan: "Notifications fire on each OS. Goldens green." The goldens (pictures of screens) belong to F10-screens (Track B).

Not in this step: the Garden, the Settings screen, and the call from `app/lib/main.dart`. The real app does not open a database yet (Track B does this at the start of F7). Until then, the services run in the check app `app/tool/services_check.dart`.

## What was built

| Part | File |
|---|---|
| The contract of a notification centre | `app/lib/services/notification_gateway.dart` (`NotificationGateway`, `NoteRequest`, `PendingNote`, `NoteResponse`) |
| The rules: permission, ids, what to cancel, what to ask for, what a click does | `app/lib/services/system_notifier.dart` (`SystemNotifier`, the `Notifier` of the store) |
| The real notification centre on Android, iOS, macOS, Windows | `app/lib/services/local_notifications_gateway.dart` (`LocalNotificationsGateway`) |
| The contract of a tray | `app/lib/services/tray_gateway.dart` (`TrayGateway`, `TrayEntry`) |
| The rules of the tray: the lines, the commands, when to build the menu again | `app/lib/services/tray_service.dart` (`TrayService`) |
| The real tray on macOS and Windows | `app/lib/services/tray_manager_gateway.dart` (`TrayManagerGateway`) |
| "Show the window" and "Quit" | `app/lib/services/app_window.dart` (`AppWindow`), `app/macos/Runner/MainFlutterWindow.swift`, `app/windows/runner/flutter_window.cpp` and `.h` |
| The daily backup while the app stays open | `app/lib/services/backup_schedule.dart` (`BackupSchedule`), `AppStore.runDailyBackup` in `app/lib/state/store_data.dart` |
| One start for all of it | `app/lib/services/app_services.dart` (`AppServices`) |
| One import | `package:grove/services/services.dart` |
| Android set-up | `app/android/app/build.gradle.kts`, `AndroidManifest.xml`, `res/drawable/ic_notification.xml`, `res/raw/keep.xml` |
| iOS set-up | `app/ios/Runner/AppDelegate.swift` (one line) |
| Tray icons | `app/assets/tray/leaf_template.png`, `app/assets/tray/leaf.png`, made by `scripts/make_tray_icons.py` |
| The check app | `app/tool/services_check.dart` |

Packages: `flutter_local_notifications` 22.3.1 and `tray_manager` 0.8.0 are on the plan's list. `timezone` 0.11.1 is not on the list; it was already installed by `flutter_local_notifications`, and `app/pubspec.yaml` now names it (Q-5 in `docs/questions.md`).

## Proof for each scope word

| Scope | Tests (all green) |
|---|---|
| Reminders, the rules | `system_notifier_test.dart` (36): the three permission states; the question is asked one time; reminders are sent with stable ids; a second send changes only what is new; old ones are cancelled; a time in the past is not sent; two ids with the same number; the focus notification with and without "Mark done"; a failed system call stops nothing; a click opens the item on its day; "Mark done" marks the task done in a real store; a click that started the app is given one time |
| Reminders, the real plugin | `local_notifications_gateway_test.dart` (8): the calls that reach the Android side of `flutter_local_notifications` (icon, time as a UTC instant, channel, inexact mode, the action button), cancel, the pending list, the permission, the launch click, and a full round trip with `SystemNotifier` |
| Tray | `tray_service_test.dart` (10): the menu lines for a full and an empty day; a system with no tray; "Open Grove", a click on the icon, "New task", "Quit Grove"; many store changes make one new menu; the clock moves the lines; the same lines make no new menu; a long title is cut in the tooltip |
| Backup schedule | `daily_backup_test.dart` (6): no second copy on the same day; a new day gets a copy with the data of now; only 14 copies stay; old unused images go after a new copy; a store in memory; a folder that cannot be written. `backup_schedule_test.dart` (4): same day, new day, a deleted copy, the 30-minute timer over midnight |
| Start and stop | `app_services_test.dart` (8): the window channel; the right notifier for each system; start sends the reminders, shows the tray and gives the launch click; a phone has no tray; a return to the app runs the backup check and makes new reminders; nothing runs after `dispose` |

## "Notifications fire on each OS": what I saw, and what I did not see

| System | What ran | What I saw |
|---|---|---|
| Android | The check app on the emulator `RealTraveller_Pixel7` (Android 16, API 36), started read-only so the emulator keeps no change. Permission given with `adb shell pm grant local.grove.grove android.permission.POST_NOTIFICATIONS`. | **Seen.** 10 seconds after the request, `adb shell dumpsys notification` showed the notification: channel `reminders`, title "Focus time is up", text "Check the focus notification. Mark it done?", the leaf icon, one action "Mark done". I tapped "Mark done" with `adb shell input tap`. The app log then said `focus task: done` and the notification was gone. |
| macOS | `flutter build macos --debug -t tool/services_check.dart`, then the app ran for 12 seconds. | **Half seen.** The app started, made its backup, and the log said `tray icon: shown` (the system made the icon and the menu with no error). I did not look at the menu bar with eyes. I did not ask for the notification permission, because the system shows a question that only you can answer. So no notification was seen on the Mac. |
| iOS | CI builds the app with the plugin and the new line in `AppDelegate.swift`. | **Not seen.** This Mac has no CocoaPods, so there is no local iOS build and no simulator run. |
| Windows | CI builds the app with the plugin, the tray library and the new C++ code. | **Not seen.** There is no Windows machine here. The Windows code paths are covered by the Dart tests only as far as the payload rules go. |

What you do to see the rest (each takes about 2 minutes):

- Mac: `cd app && flutter run -d macos -t tool/services_check.dart`. Click "1. Allow notifications" and answer the system question. Click "2. Focus end in 10 seconds". A notification comes; "Mark done" changes "Focus task" to `done`. Look for the leaf in the menu bar and click it.
- Windows: the same command with `-d windows`. The leaf is in the tray (maybe behind the small arrow). Right click opens the menu.
- iPhone or simulator: the same command with the device id from `flutter devices`.
- Button "3. Reminder in 2 minutes" checks a normal reminder.

The check app keeps its data in a folder `grove-services-check` in the temporary folder of the system. It does not touch the data of Grove.

## Honest notes

- The real app does not start the services yet. `app/lib/main.dart` is a shared file and has no store. The request to Track B is in `docs/tracks.md`: three lines at the place where the store is opened.
- Nobody asks for the notification permission yet in the real app. The store has `askForNotifications()`; the Swift app calls it after the welcome card and from Settings. Those screens are Track B's.
- Android reminders are not exact (Q-6). A reminder can come some minutes late when the phone sleeps. Android removes the reminders of an app that the user force-stops; they come back at the next start of Grove.
- A reminder set before a change of time zone keeps its instant until Grove runs again.
- The tray is a system menu, not the pop-up window of the Mac app (Q-7). It has no box to type a task; "New task" opens Grove with the cursor in the add box.
- Closing the window still quits Grove on the Mac and on Windows (Q-8). The tray icon lives only while Grove runs.
- `TrayManagerGateway` talks to native code and has no unit test. It ran one time on this Mac (see the table).
- The Windows C++ code and the iOS Swift line are compiled only by CI.
- "Mark done" on a closed app: the click starts Grove, and Grove marks the task done after its start. This path is tested with the fake and with the mocked Android channel, not on a device (Android cancels alarms on a force-stop, so the emulator could not show it).
