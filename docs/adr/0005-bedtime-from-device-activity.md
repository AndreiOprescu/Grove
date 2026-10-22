# ADR 0005 · Grove learns the usual bedtime from device use, and only night times sync

Status: Proposed (2026-10-22; the owner said yes to it in the plan of 2026-10-22, the owner marks it Accepted)

## Context
The owner wants a friendly reminder to plan tomorrow, 1½ hours before they usually fall asleep, on the phone and on the Mac.
The wake-up and sleep lines on the planner are often wrong, so they cannot be the source.
The phone is an Android phone. iOS gives an app no screen or lock history at all; Screen Time needs an Apple-approved entitlement and gives no times.

## Decision
- **Sources.** Android: the system's usage events (screen on, screen off, unlock). The user must turn on "Usage access" for Grove once. Android keeps about a week of history, so Grove can learn a night later. Mac: lock, screen sleep, system sleep and wake, heard only while Grove runs. iOS and Windows learn nothing, but get the reminder from the synced nights.
- **Next alarm.** Android tells any app when its next alarm rings, with no permission. If the alarm minus the usual sleep length is earlier than the usual bedtime, the earlier time counts. The alarm stays on the phone.
- **Privacy boundary.** Only one line per night syncs: when the user fell asleep and woke, and which device saw it. Raw events and app names never leave the device. The Mac keeps 14 days of its own events in its preferences; Android raw events are never stored by Grove.
- **Storage.** A night is a row of the synced `settings` table, key `sleep.night.<evening date>`, value JSON with one part per device. Each device replaces only its own part. No new table, so the owner runs no SQL. Precedent: the planner's wake-up and sleep lines (`DayMarkerRules`).
- **The Mac stays alive.** Closing the window hides Grove in the menu bar (no Dock icon) instead of quitting, and Grove opens hidden at login (a switch, on by default). Without this the Mac hears nothing most of the time. ⌘Q and "Quit Grove" still quit.
- **The planner lines stay the user's.** Detection never moves the wake-up or sleep line. A line is only the last fallback for the usual bedtime.

## Consequences
- The reminders are scheduled with the system for 7 nights ahead, so they come with Grove closed. A night learned after that changes them at the next start, resume, sync or hourly refresh.
- Two devices at the same time can write the same night row; the last write wins, and the device whose part was lost writes it again at its next refresh.
- A Play Store release must explain the Usage access permission (it is a protected permission). Grove is not on the Play Store now.
- If the owner later wants the Mac to quit on close, the Mac part of the learning stops working; the phone still works.
