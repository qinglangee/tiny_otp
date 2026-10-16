import '../../totp/base32.dart';
import '../../totp/totp_generator.dart';

/// In-memory Phase 1 account. Persistence is intentionally not implemented yet.
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
