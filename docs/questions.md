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

## Q-3 · OPEN · DEFAULT · blocks F11-core (sync engine) · 2026-10-10
You write the daily note of the same day on two devices while both are offline. Only one daily note can be there for a day. What happens at the next sync?
A) Keep one note and put both texts in it, one below the other — no text is lost; you can get a text two times if both devices started from different words.   ← my pick: a lost note is worse than a long note.
B) Keep one note, the text of the other note is lost — the note stays short; you lose what you wrote on one device.
If no answer: A stays. It is built and tested (`app/lib/sync/sync_engine.dart`, `joinBodies`). The same rule is used for weekly notes.

## Q-4 · ANSWERED A · ASK · blocks F11 (login step, not F11-core) · 2026-10-10
You log in on a device that already has data, and your account has data too. Each new device makes 3 sample lists and 3 sample tasks at first start. What happens at the first sync?
A) Grove asks you one time: "Use the data of the account" (the data of this device is replaced) or "Add the data of this device to the account".   ← my pick: nothing is lost and nothing is doubled without your word.
B) Grove always adds the data of the device to the account — no question; each new device adds its sample lists and sample tasks again, and you delete them by hand.
If no answer: the login step waits. The sync engine works for both.
Answer (owner, 2026-10-10): A. Grove asks one time at the first login.

## Q-5 · OPEN · DEFAULT · blocks F10-services (reminders) · 2026-10-10
The reminder code needs one type from the package `timezone`. That package is already installed, because `flutter_local_notifications` needs it. It is not on the plan's list of packages. Can `app/pubspec.yaml` name it?
A) Yes, name it (`timezone: ^0.11.1`) — no new code comes into the app; only one line in `app/pubspec.yaml`.   ← my pick: it is the clean way to use a package that is already there.
B) No — the line goes out and the import gets a "skip this warning" comment. The app works the same.
If no answer: A stays. It is built.

## Q-6 · OPEN · DEFAULT · blocks F10-services (reminders) · 2026-10-10
On Android, how exact must a reminder be?
A) Not exact — no extra permission. Android can show a reminder some minutes late when the phone sleeps.   ← my pick: no extra question for you on the phone, and no extra review by the Play Store.
B) Exact — the reminder shows at the right minute. You must allow "Alarms & reminders" for Grove in the Android settings. The Play Store asks why an app needs this.
If no answer: A stays. It is built.

## Q-7 · OPEN · DEFAULT · blocks F10-services (tray) · 2026-10-10
The Mac app has a small pop-up window under its menu bar icon, with a box to add a task. What does the tray icon of the Flutter app open on the Mac and on Windows?
A) A normal system menu: the "Now" line, the "Next" line, how much of today is done, "Open Grove", "New task", "Quit Grove". "New task" opens Grove with the cursor in the add box.   ← my pick: it needs no new package and it looks right on both systems.
B) A small pop-up window with the add box, as in the Mac app — needs a window package that is not on the plan's list, or much native code for each system.
If no answer: A stays. It is built.

## Q-8 · OPEN · ASK · blocks nothing now · 2026-10-10
You close the window of Grove on the Mac or on Windows. What happens?
A) Grove quits, as now — simple. The tray icon goes away. Reminders that are already set still show.   ← my pick: it is what the Flutter app does today, and a quit is never a surprise.
B) Grove stays open in the tray, as the Mac app does — the tray icon stays and "Open Grove" brings the window back. Only "Quit Grove" quits.
If no answer: A. Closing the window quits Grove.

## Q-9 · OPEN · DEFAULT · blocks F11 (login) · 2026-10-11
Grove sends you one login email. How do you finish the login?
A) You type the code of the email in Grove — works the same on the 4 systems with no extra setup. You put the code (`{{ .Token }}`) in the email text in Supabase one time.   ← my pick: it needs no native link code and no new address to protect.
B) You tap the link of the email and Grove opens — Grove needs its own link name on each system (native files for Android, iOS, macOS, Windows) and a redirect address in Supabase.
If no answer: A stays. It is built and tested. The link of the email does not open Grove.

## Q-10 · OPEN · DEFAULT · blocks F11 (login) · 2026-10-11
You sign out on a device. What happens to the Grove data on that device?
A) It stays on the device — nothing is deleted. A person who uses the device after you sees your data.   ← my pick: Grove never deletes your data without your word.
B) Grove deletes the data of the device at sign-out — the device is clean. Changes that were not synced yet are lost.
If no answer: A stays. It is built and tested.

## Q-11 · OPEN · ASK · blocks nothing now · 2026-10-11
Do you want a button in Grove that deletes your account and all its data on the server?
A) No, not now — you delete the rows and the user by hand in the Supabase dashboard (the SQL is in `docs/acceptance/F11-login.md`).   ← my pick: it is your own project, and a delete that cannot be undone needs your hand.
B) Yes — Grove gets a "Delete account" button. It needs a small server function with admin rights in Supabase. That is a new part with its own security rules.
If no answer: A. Nothing is built for this.

## Q-12 · OPEN · DEFAULT · blocks F11 (login) · 2026-10-11
Where does a device keep your login, and for how long?
A) In the settings file of the app, until you sign out — no new package. A person or a program that can read your user files on the device can copy the login.   ← my pick: it is what the Supabase package does by itself, and the plan's package list has no safe-store package.
B) In the key store of the system (Keychain, Windows Credential Manager, Android Keystore) — needs the package `flutter_secure_storage`, which is not on the plan's list.
If no answer: A stays. It is built. How long a login lives is a setting of your Supabase project (as new: it has no end).

## Q-13 · OPEN · DEFAULT · blocks F11 (image upload) · 2026-10-11
You delete a picture from a note. What happens to its file on the server?
A) The file stays in the file store — an undo, or a device that was offline, can bring the picture back with its file. The store grows a little (free plan: 1 GB).   ← my pick: Grove never deletes your data on the server without your word.
B) Grove deletes the file — less space is used. A picture that comes back from another device has no file any more.
If no answer: A stays. It is built: no rule in the SQL allows a delete.

## Q-14 · OPEN · ASK · blocks nothing now · 2026-10-11
Who can make an account in your Supabase project? The address and the public key of the project are inside the built app, as in every Supabase app.
A) Only you — after your first login you turn off "Allow new users to sign up" in Supabase. Nobody else can sign in.   ← my pick: Grove is for one user, and the free plan is yours.
B) Each person who has the app — a person sees only their own rows, but uses the space and the emails of your project.
If no answer: sign-up stays open, as Supabase makes a new project. The step for A is in `docs/acceptance/F11-login.md`. The code is the same for both.

## Q-15 · OPEN · ASK · blocks F9 (add an image to a note) · 2026-10-11
May Grove use the package `file_selector` (from the Flutter team) to pick an image file? It is not on the plan's list.
A) Yes — "Add an image" works in notes and in the notes of an event, on the 4 systems. One new package.   ← my pick: the plan wants images in the editor, and Flutter has no file window of its own.
B) No — a note shows the images it has, but you cannot add one in the Flutter app.
If no answer: B stays. The button "Add an image" is hidden. The editor is ready for it: it takes the picker as one parameter.

## Q-16 · OPEN · ASK · blocks F9 (web links in a note) · 2026-10-11
May Grove use the package `url_launcher` (from the Flutter team) to open a web link in the browser? It is not on the plan's list.
A) Yes — a click on a web link in a note opens the browser. One new package.   ← my pick: a link that does nothing looks broken.
B) No — a web link has the look of a link, and a click does nothing.
If no answer: B stays. Links to tasks, notes and events (`[[`) work now; they need no package.

## Q-17 · OPEN · ASK · blocks F9 (one golden picture on Linux and Windows) · 2026-10-11
The futuristic Day Spread picture is 0.203 % (Windows) and 0.210 % (Linux) off the macOS picture, and the limit is 0.2 %. Nothing moved. May the compare let a thin gap between two letters or two lines pass?
A) Yes — the compare also takes a gap of 1 to 2 pixels between two letters or two lines as a soft edge. The limit stays 0.2 %. The picture runs on all 4 jobs again, and the pictures at 0.196 % and 0.197 % get room.   ← my pick: the cause is the box font of the tests, not the app.
B) No — the compare stays. The picture gets less on it until it passes. A new heading can push a picture over again.
If no answer: the compare and the limit stay. `spread_desktop_futuristic_light.png` is checked on the macOS and iOS jobs only; the test is skipped on Linux and Windows (`_parked` in `app/test/ui/goldens/f9_golden_test.dart`).

## Q-26 · OPEN · DEFAULT · blocks F12 (release builds) · 2026-10-11
Which id does the Flutter app have? `PLAN.md` §0 says `local.grove.app`. The Flutter app has `local.grove.grove`.
A) Keep `local.grove.grove` — the Mac app and the Flutter app are two apps, each with its own data folder. Both can be on one Mac.   ← my pick: nothing of the Mac app is touched before you retire it.
B) Use `local.grove.app` — one id, as the plan says. On a Mac the Flutter app then takes the place of the Swift app.
If no answer: A stays. It is what is built.
