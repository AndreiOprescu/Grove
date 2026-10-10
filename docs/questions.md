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
