/// Strict RFC 4648 Base32 decoder used for TOTP secrets.
///
/// Padding may be omitted. If present, it must be canonical and at the end.
class Base32FormatException extends FormatException {
  Base32FormatException(super.message, [super.source, super.offset]);
}

abstract final class Base32 {
  static const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static List<int> decode(String input) {
    final value = input.trim().toUpperCase();
    if (value.isEmpty) {
      throw Base32FormatException('Secret must not be empty.', input, 0);
    }

    final firstPadding = value.indexOf('=');
    final data = firstPadding == -1 ? value : value.substring(0, firstPadding);
    final padding = firstPadding == -1 ? '' : value.substring(firstPadding);
    if (padding.contains(RegExp(r'[^=]'))) {
      throw Base32FormatException('Padding must appear only at the end.', input);
    }

    final remainder = data.length % 8;
    const validRemainders = {0, 2, 4, 5, 7};
    if (!validRemainders.contains(remainder)) {
      throw Base32FormatException('Invalid Base32 length.', input);
    }
    final expectedPadding = switch (remainder) {
      0 => 0,
      2 => 6,
      4 => 4,
      5 => 3,
      7 => 1,
      _ => throw StateError('Unreachable Base32 length.'),
    };
    if (padding.isNotEmpty &&
        (value.length % 8 != 0 || padding.length != expectedPadding)) {
      throw Base32FormatException('Invalid Base32 padding.', input);
    }

    final bytes = <int>[];
    var buffer = 0;
    var bitsInBuffer = 0;
    for (var index = 0; index < data.length; index++) {
      final digit = _alphabet.indexOf(data[index]);
      if (digit < 0) {
        throw Base32FormatException('Secret contains an invalid Base32 character.', input, index);
      }
      buffer = (buffer << 5) | digit;
      bitsInBuffer += 5;
      if (bitsInBuffer >= 8) {
        bitsInBuffer -= 8;
        bytes.add((buffer >> bitsInBuffer) & 0xff);
      }
    }

    // RFC 4648 requires unused low bits in the final symbol to be zero.
    if (bitsInBuffer > 0 && (buffer & ((1 << bitsInBuffer) - 1)) != 0) {
      throw Base32FormatException('Secret has non-zero trailing Base32 bits.', input);
    }
    if (bytes.isEmpty) {
      throw Base32FormatException('Secret must contain at least one byte.', input);
    }
    return List<int>.unmodifiable(bytes);
  }
}
