const _banglaDigits = ['০', '১', '২', '৩', '৪', '৫', '৬', '৭', '৮', '৯'];

/// Converts the ASCII digits 0-9 within [input] to Bangla numerals,
/// leaving everything else (decimal points, %, letters) untouched.
String toBanglaDigits(String input) {
  final buffer = StringBuffer();
  for (final rune in input.runes) {
    final char = String.fromCharCode(rune);
    final digit = int.tryParse(char);
    buffer.write(digit != null ? _banglaDigits[digit] : char);
  }
  return buffer.toString();
}

/// Formats a percentage value like the summary popup expects: two decimal
/// places, Bangla digits, trailing "%".
String formatBanglaPercent(double value) {
  return '${toBanglaDigits(value.toStringAsFixed(2))}%';
}

/// Formats a gram weight for the summary popup: no unnecessary trailing
/// zeros (e.g. 180 not 180.00, but 12.5 stays 12.5), Bangla digits.
String formatBanglaGrams(double value) {
  final text = value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toString();
  return toBanglaDigits(text);
}
