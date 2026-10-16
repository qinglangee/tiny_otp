import 'package:flutter_test/flutter_test.dart';
import 'package:tinyotp/totp/otpauth_uri_parser.dart';
import 'package:tinyotp/totp/totp_generator.dart';

void main() {
  test('parses an encoded label and supported query parameters', () {
    final parsed = OtpAuthUriParser.parse(
      'otpauth://totp/Example%20Service%3Aalice%40example.com'
      '?secret=JBSWY3DPEHPK3PXP&issuer=Example%20Service&algorithm=SHA256&digits=8&period=60',
    );

    expect(parsed.issuer, 'Example Service');
    expect(parsed.accountName, 'alice@example.com');
    expect(parsed.algorithm, TotpAlgorithm.sha256);
    expect(parsed.digits, 8);
    expect(parsed.period, 60);
    expect(parsed.toString(), isNot(contains('JBSWY3DPEHPK3PXP')));
  });

  test('uses defaults and issuer label when query issuer is absent', () {
    final parsed = OtpAuthUriParser.parse(
      'otpauth://totp/GitHub%3Aalice?secret=JBSWY3DPEHPK3PXP',
    );

    expect(parsed.issuer, 'GitHub');
    expect(parsed.accountName, 'alice');
    expect(parsed.algorithm, TotpAlgorithm.sha1);
    expect(parsed.digits, 6);
    expect(parsed.period, 30);
  });

  test('rejects missing secret, malformed URI, and HOTP', () {
    for (final input in [
      'otpauth://totp/GitHub%3Aalice?issuer=GitHub',
      'otpauth://totp/GitHub%3Aalice?secret=abc',
      'otpauth://hotp/GitHub%3Aalice?secret=JBSWY3DPEHPK3PXP&counter=1',
      'not an authenticator uri',
    ]) {
      expect(() => OtpAuthUriParser.parse(input), throwsA(isA<OtpAuthFormatException>()));
    }
  });

  test('rejects duplicate or conflicting parameters', () {
    for (final input in [
      'otpauth://totp/GitHub%3Aalice?secret=JBSWY3DPEHPK3PXP&secret=JBSWY3DPEHPK3PXP',
      'otpauth://totp/GitHub%3Aalice?secret=JBSWY3DPEHPK3PXP&issuer=GitLab',
    ]) {
      expect(() => OtpAuthUriParser.parse(input), throwsA(isA<OtpAuthFormatException>()));
    }
  });

  test('rejects unsupported algorithms and invalid digits or period', () {
    for (final query in [
      'algorithm=MD5',
      'digits=7',
      'digits=0',
      'period=0',
      'period=86401',
    ]) {
      expect(
        () => OtpAuthUriParser.parse(
          'otpauth://totp/GitHub%3Aalice?secret=JBSWY3DPEHPK3PXP&$query',
        ),
        throwsA(isA<OtpAuthFormatException>()),
      );
    }
  });
}
