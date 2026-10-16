import 'package:crypto/crypto.dart';

import 'base32.dart';

enum TotpAlgorithm { sha1, sha256, sha512 }

/// Generates standards-based TOTP values as defined by RFC 6238 / RFC 4226.
abstract final class TotpGenerator {
  static String generate({
    required List<int> secret,
    required DateTime time,
    TotpAlgorithm algorithm = TotpAlgorithm.sha1,
    int digits = 6,
    int period = 30,
  }) {
    if (secret.isEmpty) throw ArgumentError.value(secret, 'secret', 'Must not be empty.');
    if (digits != 6 && digits != 8) {
      throw ArgumentError.value(digits, 'digits', 'Must be 6 or 8.');
    }
    if (period <= 0) throw ArgumentError.value(period, 'period', 'Must be positive.');

    final unixSeconds = time.toUtc().millisecondsSinceEpoch ~/ 1000;
    if (unixSeconds < 0) throw ArgumentError.value(time, 'time', 'Must be after the Unix epoch.');
    final counter = unixSeconds ~/ period;
    final message = List<int>.generate(
      8,
      (index) => (counter >> ((7 - index) * 8)) & 0xff,
      growable: false,
    );
    final digest = Hmac(_hashFor(algorithm), secret).convert(message).bytes;
    final offset = digest.last & 0x0f;
    final binary = ((digest[offset] & 0x7f) << 24) |
        ((digest[offset + 1] & 0xff) << 16) |
        ((digest[offset + 2] & 0xff) << 8) |
        (digest[offset + 3] & 0xff);
    final modulus = digits == 6 ? 1000000 : 100000000;
    return (binary % modulus).toString().padLeft(digits, '0');
  }

  static String generateFromBase32({
    required String secret,
    required DateTime time,
    TotpAlgorithm algorithm = TotpAlgorithm.sha1,
    int digits = 6,
    int period = 30,
  }) =>
      generate(
        secret: Base32.decode(secret),
        time: time,
        algorithm: algorithm,
        digits: digits,
        period: period,
      );

  static Hash _hashFor(TotpAlgorithm algorithm) => switch (algorithm) {
        TotpAlgorithm.sha1 => sha1,
        TotpAlgorithm.sha256 => sha256,
        TotpAlgorithm.sha512 => sha512,
      };
}
