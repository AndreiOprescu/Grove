// The font files in the app (`app/fonts/`, declared in pubspec.yaml). The
// Mac app uses fonts of macOS that the other systems do not have. These 7
// free fonts (SIL Open Font License 1.1) are the nearest in look, so the
// letters are the same on Android, iOS, macOS and Windows.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The names of the font families in the app.
abstract final class GroveFonts {
  /// Grove titles (Mac app: New York).
  static const newsreader = 'Newsreader';

  /// Grove text (Mac app: SF Pro Rounded).
  static const nunito = 'Nunito';

  /// Minimal titles and text, Futuristic text (Mac app: SF Pro).
  static const inter = 'Inter';

  /// Futuristic titles, set wide (Mac app: SF Pro Expanded).
  static const archivo = 'Archivo';

  /// Futuristic numbers (Mac app: SF Mono).
  static const jetBrainsMono = 'JetBrains Mono';

  /// Vintage titles, italic only (Mac app: Baskerville).
  static const libreBaskerville = 'Libre Baskerville';

  /// Vintage text (Mac app: American Typewriter).
  static const courierPrime = 'Courier Prime';

  /// Each family and the file with its licence.
  static const licenses = {
    newsreader: 'fonts/newsreader/OFL.txt',
    nunito: 'fonts/nunito/OFL.txt',
    inter: 'fonts/inter/OFL.txt',
    archivo: 'fonts/archivo/OFL.txt',
    jetBrainsMono: 'fonts/jetbrainsmono/OFL.txt',
    libreBaskerville: 'fonts/librebaskerville/OFL.txt',
    courierPrime: 'fonts/courierprime/OFL.txt',
  };

  static final Set<String> all = licenses.keys.toSet();
}

/// The licence of each font, for the licence page of the app.
Stream<LicenseEntry> fontLicenses() async* {
  for (final MapEntry(key: family, value: path)
      in GroveFonts.licenses.entries) {
    yield LicenseEntryWithLineBreaks([
      family,
    ], await rootBundle.loadString(path));
  }
}

bool _registered = false;

/// Adds the font licences to the licence page. Call it one time at the start
/// of the app; more calls do nothing.
void registerFontLicenses() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(fontLicenses);
}
