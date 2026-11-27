/// Exact decimal string arithmetic ported from the C++ reference.
///
/// Values are decimal strings with the same normalization as the reference:
/// trailing fractional zeros are stripped, plain zero carries no sign, and
/// arithmetic is exact (no double conversion on any persisted or displayed
/// value).
///
/// Internally this is a BigInt unscaled value plus a scale, with the
/// reference's formatting rules (insert the point, strip trailing zeros,
/// collapse zero).
library;

final RegExp _decimalPattern = RegExp(r'^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$');

/// Whether [value] is a decimal string the reference accepts: optional minus,
/// no leading zeros (except a single zero), optional fractional part, and a
/// magnitude that parses to a finite floating-point value like the
/// reference's `std::stold` + `isfinite` rule.
bool isDecimal(String value) {
  if (!_decimalPattern.hasMatch(value)) return false;
  final parsed = double.tryParse(value);
  return parsed != null && parsed.isFinite;
}

class _DecimalParts {
  _DecimalParts(this.negative, this.digits, this.scale);

  final bool negative;
  final BigInt digits;
  final int scale;
}

_DecimalParts _parseParts(String value) {
  if (!isDecimal(value)) throw ArgumentError.value(value, 'value', 'invalid decimal value');
  var negative = value.startsWith('-');
  final point = value.indexOf('.');
  final scale = point == -1 ? 0 : value.length - point - 1;
  final digitsText = value.replaceAll('.', '').replaceFirst(RegExp(r'^-'), '');
  final digits = BigInt.parse(digitsText);
  if (digits == BigInt.zero) negative = false;
  return _DecimalParts(negative, digits, scale);
}

String _format(BigInt signedValue, int scale) {
  final negative = signedValue < BigInt.zero;
  var text = signedValue.abs().toString();
  if (scale > 0) {
    if (text.length <= scale) text = text.padLeft(scale + 1, '0');
    text = '${text.substring(0, text.length - scale)}.${text.substring(text.length - scale)}';
    while (text.endsWith('0')) {
      text = text.substring(0, text.length - 1);
    }
    if (text.endsWith('.')) text = text.substring(0, text.length - 1);
  }
  if (text.isEmpty) text = '0';
  return negative && text != '0' ? '-$text' : text;
}

/// Adds two decimal strings with exact reference normalization.
String addDecimals(String left, String right) {
  final lhs = _parseParts(left);
  final rhs = _parseParts(right);
  final scale = lhs.scale > rhs.scale ? lhs.scale : rhs.scale;
  final leftValue = lhs.digits * BigInt.from(10).pow(scale - lhs.scale);
  final rightValue = rhs.digits * BigInt.from(10).pow(scale - rhs.scale);
  final sum = (lhs.negative ? -leftValue : leftValue) + (rhs.negative ? -rightValue : rightValue);
  return _format(sum, scale);
}

/// Subtracts [right] from [left] with exact reference normalization.
String subtractDecimals(String left, String right) =>
    addDecimals(left, right.startsWith('-') ? right.substring(1) : '-$right');