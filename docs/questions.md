# Open questions for the owner

Cards for choices that only the owner can make. Newest at the end.

## Q-1 · ANSWERED A · ASK · blocks F12 (look parity) · 2026-10-10
Do we put font files in the Flutter app, so the letters look the same on every system?
A) Put free (OFL licence) fonts in the app — the same letters on all 4 systems; about 2 MB more, and you approve each font.   ← my pick: Windows and Android do not have New York, Baskerville or American Typewriter, so Grove and Vintage lose their look there.
B) Keep the fonts of each system — no new files; Windows and Android show other letter shapes than the Mac.
If no answer: B stays. The font names are in one place (`app/lib/ui/theme/grove_theme.dart`), so A is a small change later.
Answer (owner, 2026-10-10): A. The owner approves each font before it goes in.

## Q-2 · ANSWERED A · ASK · blocks Q-1 (fonts in the app) · 2026-10-10
Do you approve this list of free fonts? All are in the Google Fonts repo under the OFL licence. Total about 2.8 MB.

| Where | Mac font | Free font | File | Size |
|---|---|---|---|---|
| Grove headings | New York | Newsreader | `Newsreader[opsz,wght].ttf` | 452 KB |
| Grove text | SF Rounded | Nunito | `Nunito[wght].ttf` | 277 KB |
| Minimal headings, Minimal and Futuristic text | SF Pro | Inter | `Inter[opsz,wght].ttf` | 877 KB |
| Futuristic headings (wide letters) | SF Pro expanded | Archivo | `Archivo[wdth,wght].ttf` | 659 KB |
| Futuristic numbers | SF Mono | JetBrains Mono | `JetBrainsMono[wght].ttf` | 187 KB |
| Vintage headings | Baskerville italic | Libre Baskerville | `LibreBaskerville-Italic[wght].ttf` | 167 KB |
| Vintage text | American Typewriter | Courier Prime | `CourierPrime-Regular.ttf`, `CourierPrime-Bold.ttf` | 144 KB |

A) Yes, this list — the Flutter app uses these fonts on all 4 systems, the Mac too.   ← my pick: each one is the closest free match I found, and the size is small.
B) No, change a font — you name the theme and the font you want.
If no answer: no font files go in. System fonts stay.
Answer (owner, 2026-10-10): A. All 7 fonts are approved.

## Q-3 · ANSWERED A · DEFAULT · blocks F11-core (sync engine) · 2026-10-10
You write the daily note of the same day on two devices while both are offline. Only one daily note can be there for a day. What happens at the next sync?
A) Keep one note and put both texts in it, one below the other — no text is lost; you can get a text two times if both devices started from different words.   ← my pick: a lost note is worse than a long note.
B) Keep one note, the text of the other note is lost — the note stays short; you lose what you wrote on one device.
If no answer: A stays. It is built and tested (`app/lib/sync/sync_engine.dart`, `joinBodies`). The same rule is used for weekly notes.
Answer (owner, 2026-10-11): A. The built default stays: one note with both texts.

## Q-4 · ANSWERED A · ASK · blocks F11 (login step, not F11-core) · 2026-10-10
You log in on a device that already has data, and your account has data too. Each new device makes 3 sample lists and 3 sample tasks at first start. What happens at the first sync?
A) Grove asks you one time: "Use the data of the account" (the data of this device is replaced) or "Add the data of this device to the account".   ← my pick: nothing is lost and nothing is doubled without your word.
B) Grove always adds the data of the device to the account — no question; each new device adds its sample lists and sample tasks again, and you delete them by hand.
If no answer: the login step waits. The sync engine works for both.
Answer (owner, 2026-10-10): A. Grove asks one time at the first login.

## Q-5 · ANSWERED A · DEFAULT · blocks F10-services (reminders) · 2026-10-10
The reminder code needs one type from the package `timezone`. That package is already installed, because `flutter_local_notifications` needs it. It is not on the plan's list of packages. Can `app/pubspec.yaml` name it?
A) Yes, name it (`timezone: ^0.11.1`) — no new code comes into the app; only one line in `app/pubspec.yaml`.   ← my pick: it is the clean way to use a package that is already there.
B) No — the line goes out and the import gets a "skip this warning" comment. The app works the same.
If no answer: A stays. It is built.
Answer (owner, 2026-10-11): A. The built default stays: `timezone` is named in `app/pubspec.yaml`.

## Q-6 · ANSWERED A · DEFAULT · blocks F10-services (reminders) · 2026-10-10
On Android, how exact must a reminder be?
A) Not exact — no extra permission. Android can show a reminder some minutes late when the phone sleeps.   ← my pick: no extra question for you on the phone, and no extra review by the Play Store.
B) Exact — the reminder shows at the right minute. You must allow "Alarms & reminders" for Grove in the Android settings. The Play Store asks why an app needs this.
If no answer: A stays. It is built.
Answer (owner, 2026-10-11): A. The built default stays: reminders are not exact on Android.

## Q-7 · ANSWERED A · DEFAULT · blocks F10-services (tray) · 2026-10-10
The Mac app has a small pop-up window under its menu bar icon, with a box to add a task. What does the tray icon of the Flutter app open on the Mac and on Windows?
A) A normal system menu: the "Now" line, the "Next" line, how much of today is done, "Open Grove", "New task", "Quit Grove". "New task" opens Grove with the cursor in the add box.   ← my pick: it needs no new package and it looks right on both systems.
B) A small pop-up window with the add box, as in the Mac app — needs a window package that is not on the plan's list, or much native code for each system.
If no answer: A stays. It is built.
Answer (owner, 2026-10-11): A. The built default stays: a normal system menu.

## Q-8 · ANSWERED A · ASK · blocks nothing now · 2026-10-10
You close the window of Grove on the Mac or on Windows. What happens?
A) Grove quits, as now — simple. The tray icon goes away. Reminders that are already set still show.   ← my pick: it is what the Flutter app does today, and a quit is never a surprise.
B) Grove stays open in the tray, as the Mac app does — the tray icon stays and "Open Grove" brings the window back. Only "Quit Grove" quits.
If no answer: A. Closing the window quits Grove.
Answer (owner, 2026-10-11): A. Closing the window quits Grove. No code change.

## Q-9 · ANSWERED A · DEFAULT · blocks F11 (login) · 2026-10-11
Grove sends you one login email. How do you finish the login?
A) You type the code of the email in Grove — works the same on the 4 systems with no extra setup. You put the code (`{{ .Token }}`) in the email text in Supabase one time.   ← my pick: it needs no native link code and no new address to protect.
B) You tap the link of the email and Grove opens — Grove needs its own link name on each system (native files for Android, iOS, macOS, Windows) and a redirect address in Supabase.
If no answer: A stays. It is built and tested. The link of the email does not open Grove.
Answer (owner, 2026-10-11): A. The built default stays: you type the code of the email in Grove.

## Q-10 · ANSWERED A · DEFAULT · blocks F11 (login) · 2026-10-11
You sign out on a device. What happens to the Grove data on that device?
A) It stays on the device — nothing is deleted. A person who uses the device after you sees your data.   ← my pick: Grove never deletes your data without your word.
B) Grove deletes the data of the device at sign-out — the device is clean. Changes that were not synced yet are lost.
If no answer: A stays. It is built and tested.
Answer (owner, 2026-10-11): A. The built default stays: the data stays on the device after a sign-out.

## Q-11 · ANSWERED A · ASK · blocks nothing now · 2026-10-11
Do you want a button in Grove that deletes your account and all its data on the server?
A) No, not now — you delete the rows and the user by hand in the Supabase dashboard (the SQL is in `docs/acceptance/F11-login.md`).   ← my pick: it is your own project, and a delete that cannot be undone needs your hand.
B) Yes — Grove gets a "Delete account" button. It needs a small server function with admin rights in Supabase. That is a new part with its own security rules.
If no answer: A. Nothing is built for this.
Answer (owner, 2026-10-11): A. No "Delete account" button. No code change.

## Q-12 · ANSWERED A · DEFAULT · blocks F11 (login) · 2026-10-11
Where does a device keep your login, and for how long?
A) In the settings file of the app, until you sign out — no new package. A person or a program that can read your user files on the device can copy the login.   ← my pick: it is what the Supabase package does by itself, and the plan's package list has no safe-store package.
B) In the key store of the system (Keychain, Windows Credential Manager, Android Keystore) — needs the package `flutter_secure_storage`, which is not on the plan's list.
If no answer: A stays. It is built. How long a login lives is a setting of your Supabase project (as new: it has no end).
Answer (owner, 2026-10-11): A. The built default stays: the login is in the settings file of the app.

## Q-13 · ANSWERED A · DEFAULT · blocks F11 (image upload) · 2026-10-11
You delete a picture from a note. What happens to its file on the server?
A) The file stays in the file store — an undo, or a device that was offline, can bring the picture back with its file. The store grows a little (free plan: 1 GB).   ← my pick: Grove never deletes your data on the server without your word.
B) Grove deletes the file — less space is used. A picture that comes back from another device has no file any more.
If no answer: A stays. It is built: no rule in the SQL allows a delete.
Answer (owner, 2026-10-11): A. The built default stays: the file stays in the file store.

## Q-14 · ANSWERED A · ASK · blocks nothing now · 2026-10-11
Who can make an account in your Supabase project? The address and the public key of the project are inside the built app, as in every Supabase app.
A) Only you — after your first login you turn off "Allow new users to sign up" in Supabase. Nobody else can sign in.   ← my pick: Grove is for one user, and the free plan is yours.
B) Each person who has the app — a person sees only their own rows, but uses the space and the emails of your project.
If no answer: sign-up stays open, as Supabase makes a new project. The step for A is in `docs/acceptance/F11-login.md`. The code is the same for both.
Answer (owner, 2026-10-11): A. Only the owner signs in. The owner turns off sign-ups in Supabase after the first login. No code change.

## Q-15 · ANSWERED A · ASK · blocks F9 (add an image to a note) · 2026-10-11
May Grove use the package `file_selector` (from the Flutter team) to pick an image file? It is not on the plan's list.
A) Yes — "Add an image" works in notes and in the notes of an event, on the 4 systems. One new package.   ← my pick: the plan wants images in the editor, and Flutter has no file window of its own.
B) No — a note shows the images it has, but you cannot add one in the Flutter app.
If no answer: B stays. The button "Add an image" is hidden. The editor is ready for it: it takes the picker as one parameter.
Answer (owner, 2026-10-11): A. The package `file_selector` is allowed. "Add an image" shows in notes and in the notes of an event.

## Q-16 · ANSWERED A · ASK · blocks F9 (web links in a note) · 2026-10-11
May Grove use the package `url_launcher` (from the Flutter team) to open a web link in the browser? It is not on the plan's list.
A) Yes — a click on a web link in a note opens the browser. One new package.   ← my pick: a link that does nothing looks broken.
B) No — a web link has the look of a link, and a click does nothing.
If no answer: B stays. Links to tasks, notes and events (`[[`) work now; they need no package.
2026-10-11, F10-screens: the same package would also give two buttons of the Settings window of the Mac app: "Show data folder" and "Open System Settings" (for the notifications). With no answer, Settings shows the path of the data folder as text with a button "Copy the path", and has no button for the settings of the system.
Answer (owner, 2026-10-11): A. The package `url_launcher` is allowed. A click on a web link in a note opens the browser. Only `http` and `https` links open; other schemes do nothing.

## Q-17 · ANSWERED B · ASK · blocks F9 (one golden picture on Linux and Windows) · 2026-10-11
The futuristic Day Spread picture is 0.203 % (Windows) and 0.210 % (Linux) off the macOS picture, and the limit is 0.2 %. Nothing moved. May the compare let a thin gap between two letters or two lines pass?
A) Yes — the compare also takes a gap of 1 to 2 pixels between two letters or two lines as a soft edge. The limit stays 0.2 %. The picture runs on all 4 jobs again, and the pictures at 0.196 % and 0.197 % get room.   ← my pick: the cause is the box font of the tests, not the app.
B) No — the compare stays. The picture gets less on it until it passes. A new heading can push a picture over again.
If no answer: the compare and the limit stay. `spread_desktop_futuristic_light.png` is checked on the macOS and iOS jobs only; the test is skipped on Linux and Windows (`_parked` in `app/test/ui/goldens/f9_golden_test.dart`).
Checked again 2026-10-11, F10-screens, before any change (the two times before, F7 and F8, the cause was text on a part of a pixel; not this time):
- I listed each text of this screen with its place, from left to right and from top to bottom. No layout slip is in the red pixels. Off whole pixels are only: the letters of the headings (the theme asks for 1.5 points between them), the two tilted sticky notes (in all 4 themes, and the other 3 pictures pass), and texts half a pixel up or down (in all 4 themes; none of them is red in the picture of the difference).
- In the pictures of the CI the date (28 pt, bold) sits on whole pixels, y 40 to 68, and still rows 39 and 68 are half inked: the engine makes the bold of the test font by growing each box about half a pixel on each side. So a gap of 1.5 leaves half a pixel column between two letters, and the 2 points between the date and the line under it leave one half row. macOS gives that pixel 124 of 255 and Linux 112; the compare allows 12. The same text with no gap has no seam, and a 12 pt text that is not bold has clean edges on both systems.
- No number for the gap puts these edges on whole pixels (by the same sum a gap of 2 would leave two half columns; I did not try it on the CI), so I see no layout fix. 779 of the 1937 red pixels are the date (532 seams, 247 the row under it); the rest are the same seams in the smaller headings and the rows over the titles of the blocks. The test stays parked. The compare and the limit did not change.
Answer (owner, 2026-10-11): B. The compare and the limit stay as they are. The picture stays skipped on Linux and Windows and is checked on macOS and iOS. Nothing changes.

## Q-18 · ANSWERED A · ASK · blocks F10-screens (Export and Import in Settings) · 2026-10-11
May Grove use the package `file_selector` (the same one as in Q-15) for the file windows of "Export JSON…" and "Import JSON…" in Settings? It is not on the plan's list.
A) Yes — Export and Import work as in the Mac app, with a save window and an open window, on the 4 systems. One new package, the same as in Q-15.   ← my pick: the plan wants export and import, and Flutter has no file window of its own.
B) No — no package. Export writes `grove-export-<day>.json` into the data folder, and Import reads a file with a fixed name from that folder. On a phone that folder is hard to reach.
If no answer: the two buttons are hidden, and Settings says so. The code and its tests are ready (`SettingsFiles` in `app/lib/ui/settings/settings_view.dart`). The daily backups still run.
Before the buttons show, one more thing needs a decision (the owner's, with Track A): what Import does when sync is signed in. Import replaces all data of the device; with sync on, that could replace the data of the account too.
Answer (owner, 2026-10-11): A. The package `file_selector` is allowed. "Export JSON…" and "Import JSON…" show in Settings.
Answer to the follow-up (owner, 2026-10-11): Import is blocked while you are signed in to sync. Grove says so in plain words (sign out first). Import works only when signed out.
Built 2026-10-11: Export shows on macOS and Windows. `file_selector` has no save window on Android and iOS, so the card was wrong about "on the 4 systems" for Export: on a phone only Import shows. See Q-27.

## Q-27 · ANSWERED B · ASK · blocks F10-screens (Export on a phone) · 2026-10-11
`file_selector` has no save window on Android and iOS. How do you get your data out of Grove on a phone?
A) With the share sheet of the phone, by the package `share_plus` (from the Flutter Community group) — "Export JSON…" gives the file to Files, Drive or mail. One new package.   ← my pick: it is the normal way a phone app gives a file out.
B) No Export on a phone — you export on a computer. With sync the same data is on the computer.
If no answer: B. On Android and iOS "Export JSON…" is hidden and Settings says "Export is not on this device yet." Import works there, and the daily backups run.
Answer (owner, 2026-10-11): B. No Export on a phone. No new package. It is what is built.

## Q-28 · ANSWERED A · DEFAULT · blocks nothing now · 2026-10-11
A large picture that you add in the Flutter app is stored as a PNG file, because Flutter cannot write JPEG. A photo is then about 5 to 10 times larger than in the Mac app. May Grove use the package `image` (from the Dart community) to write JPEG?
A) No, PNG stays — no new package. A large photo takes about 2 to 4 MB of the device and of the file store of the account (free plan: 1 GB).   ← my pick: it works now, and a note has few photos.
B) Yes — a large photo with no see-through parts is stored as JPEG, about 0.3 MB, as in the Mac app. One new package.
If no answer: A stays. It is built. A PNG or JPEG of at most 1600 pixels on its long side is kept as it is, so only large pictures and other kinds (GIF, WebP, BMP) grow.
Answer (owner, 2026-10-11): A. PNG stays. No new package. It is what is built.

## Q-35 · ANSWERED A · ASK · blocks the pencil on a block and the menu line "Open / create linked note" · 2026-10-11
What is the "linked note" of a block in the planner? The plan wants a pencil on a block that has one (§5.1.2) and a menu line "Open / create linked note" (§5.1.4). The Mac app has neither.
A) The meeting note of the block — the menu line opens or makes the same note as "Create meeting note" in the card of an event, and the pencil shows when that note is there.   ← my pick: the store call is there already (`createMeetingNote`), so a block has one kind of note.
B) Leave both out, as in the Mac app — nothing to build; the plan keeps two lines that no app does.
If no answer: nothing changes. The menu has no such line. A block can draw the pencil (`block_view.dart`), but the store gives the flag to no block.
For A, not tried yet: `createMeetingNote` with a task block and with a goal block. They are events in the store, so it should work; the title of the note would be the title of the block.
Answer (owner, 2026-10-12): A. The linked note is the meeting note of the block.
Built on 2026-10-12 for the three kinds of block (event, task block, goal block). The proof is in `docs/acceptance/F12-planner-notes.md`.

## Q-36 · OPEN · DEFAULT · blocks nothing (the pencil and the menu line work today) · 2026-10-12
When you rename a block or move it to another day, should it keep its linked note? Today Grove finds the meeting note by its title, "name — day", in the planner and in the card of an event.
A) Keep the rule of today — after a rename or a move to another day the block has no pencil, and the menu line makes a new note. The old note stays in Notes with its old title. Nothing to build.   ← my pick: it is the rule the card of an event has now, and each day of a repeating event needs the day in the title to have its own note.
B) Find the note by its link only — a block keeps its pencil and its note after a rename or a move. This needs a new rule for a repeating event (all its days share one link), and the card of an event changes too.
If no answer: A stays. A test holds the rule (`app/test/state/block_note_store_test.dart`, "a new name or a new day").

## Q-37 · OPEN · DEFAULT · blocks nothing (the now line works today) · 2026-10-12
Should the now line of the planner keep its slow pulse? The plan asks for it (§6.3: the line fades from 1 to 0.45 and back in 3.2 seconds). With "Motion on" the pulse is the only thing that makes an idle planner draw.
A) Keep the pulse, at 20 steps a second — with "Motion on" an idle planner draws 20 small frames a second at most (before: one for each refresh of the screen, 60 or 120). With "Motion off" it draws none. The processor use is not measured yet.   ← my pick: it is what the plan says, and a step changes only the line, not the planner.
B) No pulse — the line stands still, and an idle planner draws nothing, with motion on too. The plan loses the line of §6.3.
If no answer: A stays. It is built. The measure of the processor use is a request in `docs/tracks.md` ("Requests, with the planner notes").

## Q-26 · ANSWERED B · DEFAULT · blocks F12 (release builds) · 2026-10-11
Which id does the Flutter app have? `PLAN.md` §0 says `local.grove.app`. The Flutter app has `local.grove.grove`.
A) Keep `local.grove.grove` — the Mac app and the Flutter app are two apps, each with its own data folder. Both can be on one Mac.   ← my pick: nothing of the Mac app is touched before you retire it.
B) Use `local.grove.app` — one id, as the plan says. On a Mac the Flutter app then takes the place of the Swift app.
If no answer: A stays. It is what is built.
Answer (owner, 2026-10-11): B. The id will be `local.grove.app`, but not now. See Q-30: the id stays `local.grove.grove` while the owner uses the Swift Mac app.

## Q-30 · ANSWERED B · ASK · blocks the change of the app id to `local.grove.app` (your answer to Q-26) · 2026-10-11
With the id `local.grove.app` the Flutter app cannot reach the database of the Mac app, but on your Mac the two apps then share the settings file of macOS and the reminders. May the id change?
A) Yes, after you copy one file — you run `cp ~/Library/Preferences/local.grove.app.plist ~/Desktop/` first. Then the id changes on the 4 systems. The Flutter app starts with an empty store; your Mac data stays in `~/Library/Application Support/Grove/`. Reminders of both apps show under one name while you use both.   ← my pick: the code shows two reasons why the database is safe, and the copy protects the one small file that is not sure.
B) Not now — the id stays `local.grove.grove` until you stop using the Mac app. The two apps share nothing.
If no answer: the id stays `local.grove.grove`. Nothing was changed. What was checked is in `docs/acceptance/F12-release.md`, part "The app id".
Answer (owner, 2026-10-11): B. Not now. The id stays `local.grove.grove` while the owner uses the Swift Mac app. It changes to `local.grove.app` on the day the owner retires the Swift app. No code was changed.

## Q-22 · OPEN · ASK · blocks nothing now (Import works, signed out) · 2026-10-11
A device that synced with an account: sign out, import, sign in again with the same account. Today the rows of the file then take the place of the rows of the account, on each device, and Grove asks nothing. Must Grove ask first?
A) Yes — after an import the next login asks the question of a first login again ("add the data of this device" or "use the data of the account"), and what the import took away on the device is not taken away on the account. One change in the sync rules on the device; nothing changes on the server.   ← my pick: the block of Q-18 is there so that an import cannot replace the account by accident, and these three steps go around it.
B) No — it stays as it is. Who signs out, imports and signs in again gets the file on each device. The copy `before-import.sqlite` is on that one device; the account has no copy.
If no answer: B stays, I change no sync rule. The tests in `app/test/state/import_sync_test.dart` say what Grove does today, so a change is seen.
What I checked (Track A, 2026-10-11, with the fake account of the tests, no real project):
- Signed in: the store refuses the import and no row changes (`ImportRefused`; the owner's answer under Q-18).
- A device that never synced, and an account with no data: the rows of the file go to the account, no question. Nothing is lost.
- A device that never synced, and an account with data: Grove asks. "Use the data of the account" drops the rows of the file (a copy is saved first) and sends nothing. "Add the data of this device" keeps each task, note and event of the account and adds the rows of the file.
- One thing is lost in that last case: a setting that the device had before the import and the file has not (for example the own text for a new daily note) is taken away on the account too. The rule is older than the import: a row taken away before the first login is taken away on the account with "add the data of this device". An import takes many rows away at one time. A covers this too.
- A device that synced before, same account again: no question, and the account gets the file (the question of this card). A row another device made after the sign-out stays.
- Sign in with another account after the import: Grove asks, and nothing moves before the answer.

## Q-31 · ANSWERED A · ASK · blocks F12 (signed builds) · 2026-10-11
Signing costs money and needs accounts in your name. Which one do you want now?
A) None now — cost 0. The Mac app, the Windows folder and the Android APK work on your own devices, with a warning of the system on a device that is not this Mac. The iPhone build cannot be put on a phone.   ← my pick: Grove is for one user, and only the iPhone waits for it.
B) The Apple Developer Program first, 99 USD a year — a Mac app that opens with no warning on any Mac, and the iPhone app on your phone. Windows (a code signing certificate, paid; I do not know a sure price) and the Play Store (25 USD, one time) stay for later.
If no answer: A stays. No key, certificate or account was made. What each system needs is in `docs/acceptance/F12-release.md`, part "Signing".
Answer (owner, 2026-10-11): A. No signing now. No key, certificate or account is made.

## Q-40 · ANSWERED B · DEFAULT · blocks nothing (one text in the details of `grove.exe`) · 2026-10-11
On Windows, may the "Product name" of the program change from "grove" to "Grove"? The data folder gets its name from this text: `%APPDATA%\local.grove\grove`.
A) Keep "grove" — the data folder stays the same for sure; the window, the taskbar and Task Manager already say "Grove", only the "Details" tab of the file says "grove".   ← my pick: the brief says not to change a name that makes the data folder.
B) Change it to "Grove" — the "Details" tab says "Grove" too; on a normal Windows disk the folder is the same one (big and small letters are equal there), on a disk set to tell them apart the app would start with an empty folder.
If no answer: A stays. The file name `grove.exe` stays too.
Answer (owner, 2026-10-12): B. The Windows "Product name" becomes "Grove".

## Q-48 · ANSWERED A · ASK · blocks the subtasks of a goal (what a click on a goal does) · 2026-10-12
What does a click on a goal in the Goals panel do, now that a goal has subtasks? Before, the click opened the editor of the goal.
A) The click opens the subtasks — all of them and a line to add one. The editor is one click more: the line "Edit goal…" in the open goal, or "Edit…" in the right-click menu.   ← my pick: your words were "added by clicking on the goal" and "expanded by clicking on the goal".
B) The click opens the subtasks and the editor together — one click for both; an open goal is then very tall, and on a phone the editor pushes the other goals off the screen.
If no answer: A stays. It is built.
Answer (owner, 2026-10-12): A.
The builder got this answer from the coordinator of the session, with the plan ("A, yes to all"). The proof is in `docs/acceptance/goal-subtasks.md`.

## Q-49 · ANSWERED A · ASK · blocks the subtasks of a goal (the new table) · 2026-10-12
May the new table `goal_subtasks` be migration 8 of the shared database schema? The Swift Mac app has 7 on its branch and 6 on `main`.
A) Yes, migration 8 — one number for the database, the export file and the sync, as for each table before. The Swift Mac app then refuses an export file of this app ("from a newer Grove"). This app still imports the files of the Mac app (schema 6 and 7).   ← my pick: the export, the import and the sync read one list of tables and one number; a second number is a new rule in each of them.
B) Keep the number 7 and put the table on a track of this app only — the export file still says schema 7; the app then has two kinds of tables, and it was not tried if the Mac app reads a file with a table it does not know.
If no answer: A stays. It is built.
Answer (owner, 2026-10-12): A.
The builder got this answer from the coordinator of the session, with the plan ("A, yes to all"). To go back the other way, from this app to the Mac app, the Mac app needs migration 8 too. Nothing in `Sources/` was changed.
