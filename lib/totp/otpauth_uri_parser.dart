import 'base32.dart';
import 'totp_generator.dart';

class OtpAuthFormatException implements Exception {
  const OtpAuthFormatException(this.message);

  final String message;

  @override
  String toString() => 'OtpAuthFormatException: $message';
}

/// A validated otpauth configuration. Its string representation never includes
/// the credential bytes.
class OtpAuthAccountConfig {
  OtpAuthAccountConfig({
    required this.issuer,
    required this.accountName,
    required List<int> secret,
    required this.algorithm,
    required this.digits,
    required this.period,
  }) : secret = List<int>.unmodifiable(secret);

  final String issuer;
  final String accountName;
  final List<int> secret;
  final TotpAlgorithm algorithm;
  final int digits;
  final int period;

  @override
  String toString() =>
      'OtpAuthAccountConfig(issuer: $issuer, accountName: $accountName, algorithm: $algorithm, digits: $digits, period: $period)';
}

abstract final class OtpAuthUriParser {
  static OtpAuthAccountConfig parse(String input) {
    try {
      return _parse(input);
    } on OtpAuthFormatException {
      rethrow;
    } on Object {
      throw const OtpAuthFormatException('The QR code contains malformed or unsupported data.');
    }
  }

  static OtpAuthAccountConfig _parse(String input) {
    late final Uri uri;
    try {
      uri = Uri.parse(input);
    } on FormatException {
      throw const OtpAuthFormatException('The QR code does not contain a valid authenticator URI.');
    }
    if (uri.scheme.toLowerCase() != 'otpauth' || uri.host.toLowerCase() != 'totp') {
      throw const OtpAuthFormatException('Only otpauth TOTP accounts are supported.');
    }
    if (uri.userInfo.isNotEmpty || uri.hasPort || uri.hasFragment) {
      throw const OtpAuthFormatException('The authenticator URI contains unsupported parts.');
    }
    final segments = uri.pathSegments;
    if (segments.length != 1 || segments.single.trim().isEmpty) {
      throw const OtpAuthFormatException('The account label is missing or malformed.');
    }

    final parameters = uri.queryParametersAll;
    for (final values in parameters.values) {
      if (values.length != 1) {
        throw const OtpAuthFormatException('The authenticator URI contains a repeated parameter.');
      }
    }
    String? parameter(String name) => parameters[name]?.single;

    final secretValue = parameter('secret');
    if (secretValue == null || secretValue.isEmpty) {
      throw const OtpAuthFormatException('The QR code does not contain a secret.');
    }
    late final List<int> secret;
    try {
      secret = Base32.decode(secretValue);
    } on FormatException {
      throw const OtpAuthFormatException('The QR code contains an invalid Base32 secret.');
    }

    final rawLabel = segments.single;
    final separator = rawLabel.indexOf(':');
    final labelIssuer = separator < 0 ? null : rawLabel.substring(0, separator).trim();
    final accountName = (separator < 0 ? rawLabel : rawLabel.substring(separator + 1)).trim();
    final queryIssuer = parameter('issuer')?.trim();
    if (queryIssuer != null && queryIssuer.isEmpty) {
      throw const OtpAuthFormatException('The issuer must not be empty.');
    }
    if (labelIssuer != null && labelIssuer.isEmpty) {
      throw const OtpAuthFormatException('The issuer in the account label must not be empty.');
    }
    if (queryIssuer != null &&
        labelIssuer != null &&
        queryIssuer.toLowerCase() != labelIssuer.toLowerCase()) {
      throw const OtpAuthFormatException('The issuer in the label and query do not match.');
    }
    final issuer = queryIssuer ?? labelIssuer;
    if (issuer == null || issuer.isEmpty || accountName.isEmpty) {
      throw const OtpAuthFormatException('The issuer and account name are required.');
    }

    final algorithmName = (parameter('algorithm') ?? 'SHA1').toUpperCase();
    final algorithm = switch (algorithmName) {
      'SHA1' => TotpAlgorithm.sha1,
      'SHA256' => TotpAlgorithm.sha256,
      'SHA512' => TotpAlgorithm.sha512,
      _ => throw const OtpAuthFormatException('The QR code uses an unsupported HMAC algorithm.'),
    };
    final digits = _positiveInt(parameter('digits'), defaultValue: 6, name: 'digits');
    if (digits != 6 && digits != 8) {
      throw const OtpAuthFormatException('The QR code must use 6 or 8 digits.');
    }
    final period = _positiveInt(parameter('period'), defaultValue: 30, name: 'period');
    if (period > 86400) {
      throw const OtpAuthFormatException('The QR code period is too large.');
    }

    return OtpAuthAccountConfig(
      issuer: issuer,
      accountName: accountName,
      secret: secret,
      algorithm: algorithm,
      digits: digits,
      period: period,
    );
  }

  static int _positiveInt(String? value, {required int defaultValue, required String name}) {
    if (value == null) return defaultValue;
    final parsed = int.tryParse(value);
    if (parsed == null || parsed <= 0) {
      throw OtpAuthFormatException('The QR code has an invalid $name value.');
    }
    return parsed;
  }
}
