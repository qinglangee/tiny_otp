import 'package:flutter_test/flutter_test.dart';
import 'package:tinyotp/totp/base32.dart';
import 'package:tinyotp/totp/totp_generator.dart';

void main() {
  // RFC 6238 Appendix B test secrets are public standard test vectors.
  const sha1Secret = '12345678901234567890';
  const sha256Secret = '12345678901234567890123456789012';
  const sha512Secret = '1234567890123456789012345678901234567890123456789012345678901234';
  final vectors = <(int, String, String, TotpAlgorithm)>[
    (59, '94287082', sha1Secret, TotpAlgorithm.sha1),
    (1111111109, '07081804', sha1Secret, TotpAlgorithm.sha1),
    (1111111111, '14050471', sha1Secret, TotpAlgorithm.sha1),
    (1234567890, '89005924', sha1Secret, TotpAlgorithm.sha1),
    (2000000000, '69279037', sha1Secret, TotpAlgorithm.sha1),
    (20000000000, '65353130', sha1Secret, TotpAlgorithm.sha1),
    (59, '46119246', sha256Secret, TotpAlgorithm.sha256),
    (1111111109, '68084774', sha256Secret, TotpAlgorithm.sha256),
    (1111111111, '67062674', sha256Secret, TotpAlgorithm.sha256),
    (1234567890, '91819424', sha256Secret, TotpAlgorithm.sha256),
    (2000000000, '90698825', sha256Secret, TotpAlgorithm.sha256),
    (20000000000, '77737706', sha256Secret, TotpAlgorithm.sha256),
    (59, '90693936', sha512Secret, TotpAlgorithm.sha512),
    (1111111109, '25091201', sha512Secret, TotpAlgorithm.sha512),
    (1111111111, '99943326', sha512Secret, TotpAlgorithm.sha512),
    (1234567890, '93441116', sha512Secret, TotpAlgorithm.sha512),
    (2000000000, '38618901', sha512Secret, TotpAlgorithm.sha512),
    (20000000000, '47863826', sha512Secret, TotpAlgorithm.sha512),
  ];

  group('RFC 6238 vectors', () {
    for (final (seconds, expected, secret, algorithm) in vectors) {
      test('${algorithm.name} at Unix time $seconds', () {
        expect(
          TotpGenerator.generate(
            secret: secret.codeUnits,
            time: DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true),
            algorithm: algorithm,
            digits: 8,
          ),
          expected,
        );
      });
    }
  });

  group('TOTP parameters', () {
    test('supports six digits and preserves leading zeroes', () {
      expect(
        TotpGenerator.generate(
          secret: sha1Secret.codeUnits,
          time: DateTime.fromMillisecondsSinceEpoch(59 * 1000, isUtc: true),
          algorithm: TotpAlgorithm.sha1,
          digits: 6,
        ),
        '287082',
      );
    });

    test('uses the configured period', () {
      final secret = sha1Secret.codeUnits;
      final time = DateTime.fromMillisecondsSinceEpoch(60 * 1000, isUtc: true);
      expect(
        TotpGenerator.generate(secret: secret, time: time, period: 60),
        TotpGenerator.generate(
          secret: secret,
          time: DateTime.fromMillisecondsSinceEpoch(30 * 1000, isUtc: true),
        ),
      );
    });

    test('rejects unsupported digits, period, and empty secrets', () {
      final time = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      expect(() => TotpGenerator.generate(secret: [1], time: time, digits: 7), throwsArgumentError);
      expect(() => TotpGenerator.generate(secret: [1], time: time, period: 0), throwsArgumentError);
      expect(() => TotpGenerator.generate(secret: [], time: time), throwsArgumentError);
    });
  });

  group('Base32', () {
    test('decodes upper/lowercase and padded/unpadded input', () {
      expect(Base32.decode('MZXW6==='), 'foo'.codeUnits);
      expect(Base32.decode('mzxw6'), 'foo'.codeUnits);
    });

    test('rejects malformed characters, padding, length, and trailing bits', () {
      for (final invalid in ['!', 'ABC', 'MZ======', 'MZXW6==']) {
        expect(() => Base32.decode(invalid), throwsFormatException, reason: invalid);
      }
    });
  });
}
