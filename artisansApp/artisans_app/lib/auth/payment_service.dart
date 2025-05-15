import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<double> getWalletBalance(String userId) async {
    try {
      final doc = await _firestore.collection('wallets').doc(userId).get();
      return doc.data()?['balance']?.toDouble() ?? 0.0;
    } catch (e) {
      if (kDebugMode) {
        print('Error getting wallet balance: $e');
      }
      return 0.0;
    }
  }

  Future<void> topUpWallet(String userId, double amount) async {
    try {
      await _firestore.collection('wallets').doc(userId).set({
        'balance': FieldValue.increment(amount),
      }, SetOptions(merge: true));
    } catch (e) {
      if (kDebugMode) {
        print('Error topping up wallet: $e');
      }
      rethrow;
    }
  }

  Future<void> transferToArtisan(
    String customerId,
    String artisanId,
    double amount,
    String jobId,
  ) async {
    try {
      // Start a batch write for atomic operations
      final batch = _firestore.batch();

      // Deduct from customer's wallet
      final customerWalletRef = _firestore
          .collection('wallets')
          .doc(customerId);
      batch.update(customerWalletRef, {
        'balance': FieldValue.increment(-amount),
      });

      // Add to artisan's wallet (minus commission)
      final commission = amount * 0.1; // 10% commission
      final artisanAmount = amount - commission;
      final artisanWalletRef = _firestore.collection('wallets').doc(artisanId);
      batch.update(artisanWalletRef, {
        'balance': FieldValue.increment(artisanAmount),
      });

      // Add to admin's wallet (commission)
      final adminWalletRef = _firestore.collection('wallets').doc('admin');
      batch.update(adminWalletRef, {
        'balance': FieldValue.increment(commission),
      });

      // Record the transaction
      final transactionRef = _firestore.collection('transactions').doc();
      batch.set(transactionRef, {
        'id': transactionRef.id,
        'from': customerId,
        'to': artisanId,
        'amount': amount,
        'jobId': jobId,
        'commission': commission,
        'timestamp': FieldValue.serverTimestamp(),
      });

      await batch.commit();
    } catch (e) {
      if (kDebugMode) {
        print('Error transferring to artisan: $e');
      }
      rethrow;
    }
  }

  Future<void> initiateWithdrawal(
    String userId,
    double amount,
    String bankAccount,
  ) async {
    try {
      // In a real app, this would call Paystack/Flutterwave API
      await _firestore.collection('withdrawals').doc().set({
        'userId': userId,
        'amount': amount,
        'bankAccount': bankAccount,
        'status': 'pending',
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Deduct from wallet immediately
      await _firestore.collection('wallets').doc(userId).update({
        'balance': FieldValue.increment(-amount),
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error initiating withdrawal: $e');
      }
      rethrow;
    }
  }
}
