// lib/models/wallet.dart
import 'package:equatable/equatable.dart';
import 'package:flutter/material.dart';

class Wallet extends Equatable {
  final int? userId;
  final double balance;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const Wallet({
    this.userId,
    this.balance = 0.0,
    this.createdAt,
    this.updatedAt,
  });

  @override
  List<Object?> get props => [userId, balance, createdAt, updatedAt];

  factory Wallet.fromJson(Map<String, dynamic> json) {
    return Wallet(
      userId: json['user_id'] != null
          ? (json['user_id'] as num).toInt()
          : json['user'] != null
              ? (json['user'] as num).toInt()
              : null,
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
  escrowRelease,
  pandascrowFund, pandascrowRelease, pandascrowRefund, pandascrowFee;

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
      case 'PANDASCROW_FUND': return TransactionType.pandascrowFund;
      case 'PANDASCROW_RELEASE': return TransactionType.pandascrowRelease;
      case 'PANDASCROW_REFUND': return TransactionType.pandascrowRefund;
      case 'PANDASCROW_FEE': return TransactionType.pandascrowFee;
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
      case TransactionType.pandascrowFund: return 'Escrow Funding';
      case TransactionType.pandascrowRelease: return 'Escrow Release';
      case TransactionType.pandascrowRefund: return 'Escrow Refund';
      case TransactionType.pandascrowFee: return 'Escrow Fee';
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

enum PandascrowEscrowStatus {
  initialized,
  funded,
  completed,
  disputed,
  cancelled,
  refunded;

  static PandascrowEscrowStatus fromString(String? status) {
    switch (status?.toUpperCase()) {
      case 'INITIALIZED': return PandascrowEscrowStatus.initialized;
      case 'FUNDED': return PandascrowEscrowStatus.funded;
      case 'COMPLETED': return PandascrowEscrowStatus.completed;
      case 'DISPUTED': return PandascrowEscrowStatus.disputed;
      case 'CANCELLED': return PandascrowEscrowStatus.cancelled;
      case 'REFUNDED': return PandascrowEscrowStatus.refunded;
      default: return PandascrowEscrowStatus.initialized;
    }
  }

  String get label {
    switch (this) {
      case PandascrowEscrowStatus.initialized: return 'Awaiting Payment';
      case PandascrowEscrowStatus.funded: return 'Funded';
      case PandascrowEscrowStatus.completed: return 'Completed';
      case PandascrowEscrowStatus.disputed: return 'Disputed';
      case PandascrowEscrowStatus.cancelled: return 'Cancelled';
      case PandascrowEscrowStatus.refunded: return 'Refunded';
    }
  }

  Color get color {
    switch (this) {
      case PandascrowEscrowStatus.initialized: return Colors.orange;
      case PandascrowEscrowStatus.funded: return Colors.green;
      case PandascrowEscrowStatus.completed: return Colors.blue;
      case PandascrowEscrowStatus.disputed: return Colors.red;
      case PandascrowEscrowStatus.cancelled: return Colors.grey;
      case PandascrowEscrowStatus.refunded: return Colors.purple;
    }
  }
}

class PandascrowEscrow {
  final int? id;
  final String escrowId;
  final int jobId;
  final PandascrowEscrowStatus status;
  final double amount;
  final String? paymentUrl;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PandascrowEscrow({
    this.id,
    required this.escrowId,
    required this.jobId,
    required this.status,
    required this.amount,
    this.paymentUrl,
    this.createdAt,
    this.updatedAt,
  });

  factory PandascrowEscrow.fromJson(Map<String, dynamic> json) {
    return PandascrowEscrow(
      id: json['id'] as int?,
      escrowId: json['escrow_id'] as String? ?? '',
      jobId: json['job'] as int? ?? json['job_id'] as int? ?? 0,
      status: PandascrowEscrowStatus.fromString(json['status'] as String?),
      amount: (json['amount'] as num?)?.toDouble() ?? 0.0,
      paymentUrl: json['payment_url'] as String?,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'].toString()) : null,
      updatedAt: json['updated_at'] != null ? DateTime.tryParse(json['updated_at'].toString()) : null,
    );
  }
}