import '../../core/parsing/at_date.dart' show isSpaceOrTab;

/// Cuts spaces and tabs off both ends (Swift's `.whitespaces`). Line breaks stay.
String trimSpaces(String s) {
  var a = 0, b = s.length;
  while (a < b && isSpaceOrTab(s.codeUnitAt(a))) {
    a++;
  }
  while (b > a && isSpaceOrTab(s.codeUnitAt(b - 1))) {
    b--;
  }
  return s.substring(a, b);
}

/// The first [n] characters. It counts code points, so it never cuts a pair in half.
String prefixRunes(String s, int n) {
  if (s.length <= n) return s;
  final runes = s.runes;
  return runes.length <= n ? s : String.fromCharCodes(runes.take(n));
}

/// Orders two texts without looking at upper and lower case.
int compareIgnoringCase(String a, String b) =>
    a.toLowerCase().compareTo(b.toLowerCase());

final _lineBreaks = RegExp('[\\n\\r\\u000B\\u000C\\u0085\\u2028\\u2029]');

/// Splits at every kind of line break (Swift's `.newlines`).
List<String> splitLines(String s) => s.split(_lineBreaks);
