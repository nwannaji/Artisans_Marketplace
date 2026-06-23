// lib/models/bank_account.dart
import 'package:equatable/equatable.dart';

class BankAccount extends Equatable {
  final int id;
  final String bankCode;
  final String accountNumber;
  final String accountName;
  final bool isVerified;
  final String? paystackRecipientCode;
  final bool isDefault;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const BankAccount({
    required this.id,
    required this.bankCode,
    required this.accountNumber,
    required this.accountName,
    this.isVerified = false,
    this.paystackRecipientCode,
    this.isDefault = false,
    this.createdAt,
    this.updatedAt,
  });

  /// Last 4 digits of the account number for display
  String get accountNumberMasked => '****${accountNumber.substring(accountNumber.length - 4)}';

  @override
  List<Object?> get props => [
        id, bankCode, accountNumber, accountName,
        isVerified, paystackRecipientCode, isDefault,
      ];

  factory BankAccount.fromJson(Map<String, dynamic> json) {
    return BankAccount(
      id: json['id'] as int,
      bankCode: json['bank_code'] as String? ?? '',
      accountNumber: json['account_number'] as String? ?? '',
      accountName: json['account_name'] as String? ?? '',
      isVerified: json['is_verified'] as bool? ?? false,
      paystackRecipientCode: json['paystack_recipient_code'] as String?,
      isDefault: json['is_default'] as bool? ?? false,
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}