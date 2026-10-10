# Open questions for the owner

Cards for choices that only the owner can make. Newest at the end.

## Q-1 · OPEN · ASK · blocks F12 (look parity) · 2026-10-10
Do we put font files in the Flutter app, so the letters look the same on every system?
A) Put free (OFL licence) fonts in the app — the same letters on all 4 systems; about 2 MB more, and you approve each font.   ← my pick: Windows and Android do not have New York, Baskerville or American Typewriter, so Grove and Vintage lose their look there.
B) Keep the fonts of each system — no new files; Windows and Android show other letter shapes than the Mac.
If no answer: B stays. The font names are in one place (`app/lib/ui/theme/grove_theme.dart`), so A is a small change later.
