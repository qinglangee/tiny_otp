import 'dart:convert';

import '../../totp/base32.dart';
import '../../totp/totp_generator.dart';

/// TOTP account. The secret is held as bytes and excluded from its string form.
class TotpAccount {
  TotpAccount({
    required this.id,
    required this.issuer,
    required this.accountName,
    required List<int> secret,
    this.algorithm = TotpAlgorithm.sha1,
    this.digits = 6,
    this.period = 30,
  }) : secret = List<int>.unmodifiable(secret);

  final String id;
  final String issuer;
  final String accountName;
  final List<int> secret;
  final TotpAlgorithm algorithm;
  final int digits;
  final int period;

  factory TotpAccount.fromJson(Map<String, Object?> json) {
    final id = json['id'];
    final issuer = json['issuer'];
    final accountName = json['accountName'];
    final encodedSecret = json['secret'];
    final algorithmName = json['algorithm'];
    final digits = json['digits'];
    final period = json['period'];
    if (id is! String || id.isEmpty ||
        issuer is! String || issuer.trim().isEmpty ||
        accountName is! String || accountName.trim().isEmpty ||
        encodedSecret is! String ||
        algorithmName is! String ||
        digits is! int || (digits != 6 && digits != 8) ||
        period is! int || period <= 0) {
      throw const FormatException('Stored account has invalid fields.');
    }
    final algorithm = TotpAlgorithm.values.where((value) => value.name == algorithmName);
    if (algorithm.isEmpty) throw const FormatException('Stored account uses an unsupported algorithm.');
    late final List<int> secret;
    try {
      secret = base64Url.decode(base64Url.normalize(encodedSecret));
    } on FormatException {
      throw const FormatException('Stored account secret is malformed.');
    }
    if (secret.isEmpty) throw const FormatException('Stored account secret is empty.');
    return TotpAccount(
      id: id,
      issuer: issuer,
      accountName: accountName,
      secret: secret,
      algorithm: algorithm.first,
      digits: digits,
      period: period,
    );
  }

  factory TotpAccount.fromBase32({
    required String id,
    required String issuer,
    required String accountName,
    required String secret,
    TotpAlgorithm algorithm = TotpAlgorithm.sha1,
    int digits = 6,
    int period = 30,
  }) {
    return TotpAccount(
      id: id,
      issuer: issuer.trim(),
      accountName: accountName.trim(),
      secret: Base32.decode(secret),
      algorithm: algorithm,
      digits: digits,
      period: period,
    );
  }

  @override
  String toString() => 'TotpAccount(id: $id, issuer: $issuer, accountName: $accountName)';
}

