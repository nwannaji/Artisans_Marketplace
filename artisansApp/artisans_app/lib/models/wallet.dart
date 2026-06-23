// lib/models/wallet.dart
import 'package:equatable/equatable.dart';

class Wallet extends Equatable {
  final int userId;
  final double balance;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Wallet({
    required this.userId,
    this.balance = 0.0,
    this.createdAt,
    this.updatedAt,
  });

  @override
  List<Object?> get props => [userId, balance, createdAt, updatedAt];

  factory Wallet.fromJson(Map<String, dynamic> json) {
    return Wallet(
      userId: json['user'] as int,
      balance: _parseDouble(json['balance']) ?? 0.0,
      createdAt: _parseDateTime(json['created_at']),
      updatedAt: _parseDateTime(json['updated_at']),
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}

enum TransactionType {
  deposit,
  withdrawal,
  transferOut,
  commission,
  refund,
  escrowHold,
  escrowRelease;

  static TransactionType fromString(String? type) {
    switch (type?.toUpperCase()) {
      case 'DEPOSIT': return TransactionType.deposit;
      case 'WITHDRAWAL': return TransactionType.withdrawal;
      case 'TRANSFER_OUT': return TransactionType.transferOut;
      case 'PAYMENT': return TransactionType.transferOut; // Legacy alias
      case 'COMMISSION': return TransactionType.commission;
      case 'REFUND': return TransactionType.refund;
      case 'ESCROW_HOLD': return TransactionType.escrowHold;
      case 'ESCROW_RELEASE': return TransactionType.escrowRelease;
      default: return TransactionType.deposit;
    }
  }

  String get label {
    switch (this) {
      case TransactionType.deposit: return 'Deposit';
      case TransactionType.withdrawal: return 'Withdrawal';
      case TransactionType.transferOut: return 'Bank Transfer';
      case TransactionType.commission: return 'Commission';
      case TransactionType.refund: return 'Refund';
      case TransactionType.escrowHold: return 'Escrow Hold';
      case TransactionType.escrowRelease: return 'Escrow Release';
    }
  }
}

class Transaction extends Equatable {
  final int? id;
  final double amount;
  final TransactionType transactionType;
  final String status;
  final String? reference;
  final int? jobId;
  final String? description;
  final DateTime? createdAt;

  const Transaction({
    this.id,
    required this.amount,
    required this.transactionType,
    this.status = 'PENDING',
    this.reference,
    this.jobId,
    this.description,
    this.createdAt,
  });

  @override
  List<Object?> get props => [
    id, amount, transactionType, status, reference, jobId, description, createdAt,
  ];

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'] as int?,
      amount: _parseDouble(json['amount']) ?? 0.0,
      transactionType: TransactionType.fromString(json['transaction_type'] as String?),
      status: json['status'] as String? ?? 'PENDING',
      reference: json['reference'] as String?,
      jobId: json['job_id'] as int?,
      description: json['description'] as String?,
      createdAt: _parseDateTime(json['created_at']),
    );
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}