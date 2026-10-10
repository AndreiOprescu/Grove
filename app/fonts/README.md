# Fonts in the app

The owner approved these 7 font families on 2026-10-10 (`docs/questions.md`, Q-1 and Q-2).
All have the SIL Open Font License 1.1. Each folder has the licence text (`OFL.txt`).

Source: `https://github.com/google/fonts`, branch `main`, downloaded on 2026-10-10.
The files are not changed. Only the file name is shorter (no `[` `]` `,` in asset paths).

| Family | Theme use | File here | File in `google/fonts` | SHA-256 |
|---|---|---|---|---|
| Newsreader | Grove titles | `newsreader/Newsreader-Variable.ttf` | `ofl/newsreader/Newsreader[opsz,wght].ttf` | `8a08d13f8a6c0d51be379a60af84f945f65369a67e509ee3c3bdcc421254d7c1` |
| Nunito | Grove text | `nunito/Nunito-Variable.ttf` | `ofl/nunito/Nunito[wght].ttf` | `bb55a5ca5c2042335b3991af27c4d0705d0ef41cac6164ac737fd8f2a1e85207` |
| Inter | Minimal titles and text, Futuristic text | `inter/Inter-Variable.ttf` | `ofl/inter/Inter[opsz,wght].ttf` | `29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031` |
| Archivo | Futuristic titles (wide) | `archivo/Archivo-Variable.ttf` | `ofl/archivo/Archivo[wdth,wght].ttf` | `0e094a7d3c7c4c25cf1310c4b30014f1dae9332220b1c2c88f4fa996f0b05053` |
| JetBrains Mono | Futuristic numbers | `jetbrainsmono/JetBrainsMono-Variable.ttf` | `ofl/jetbrainsmono/JetBrainsMono[wght].ttf` | `48715a42ec242c21e9f02692891e147d022299a52e48d5e413e1a942193ffeda` |
| Libre Baskerville | Vintage titles (italic) | `librebaskerville/LibreBaskerville-Italic-Variable.ttf` | `ofl/librebaskerville/LibreBaskerville-Italic[wght].ttf` | `223959683dc73ec4437bd61fabaa4b3f22209e22855ffd3aee36ba61a5116e97` |
| Courier Prime | Vintage text | `courierprime/CourierPrime-Regular.ttf` | `ofl/courierprime/CourierPrime-Regular.ttf` | `72f793376f8e2841656bf21d77a5de010f2929bd6956a22ee848ad0c7eb978af` |
| Courier Prime | Vintage text, bold | `courierprime/CourierPrime-Bold.ttf` | `ofl/courierprime/CourierPrime-Bold.ttf` | `ff1f38786c849d1c41fa8e447960abdb2bd75fdfb0cfcdeb524fad65a5af3638` |

To add or change a font: ask the owner first. Then change `app/pubspec.yaml`, `app/lib/ui/theme/fonts.dart` and this table. `app/test/ui/theme/fonts_test.dart` checks them.
