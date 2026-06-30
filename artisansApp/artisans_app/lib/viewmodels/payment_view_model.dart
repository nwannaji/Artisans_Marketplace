// lib/viewmodels/payment_view_model.dart
import '../models/wallet.dart';
import '../services/payment_api_service.dart';
import 'base_view_model.dart';

class PaymentViewModel extends BaseViewModel {
  final PaymentApiService _paymentService = PaymentApiService();

  Wallet? _wallet;
  Wallet? get wallet => _wallet;

  List<Transaction> _transactions = [];
  List<Transaction> get transactions => _transactions;

  Future<void> loadWallet() async {
    setState(ViewState.loading);
    try {
      _wallet = await _paymentService.getWallet();
      setState(ViewState.idle);
    } catch (e) {
      setError(e.toString());
    }
  }

  Future<void> loadTransactions() async {
    try {
      _transactions = await _paymentService.listTransactions();
      notifyListeners();
    } catch (e) {
      setError(e.toString());
    }
  }

  Future<Map<String, dynamic>?> fundEscrow(int jobId, {double? amount}) async {
    try {
      final result = await _paymentService.fundEscrow(jobId, amount: amount);
      // Refresh wallet after funding (for internal escrow, wallet is debited)
      await loadWallet();
      return result;
    } catch (e) {
      setError(e.toString());
      return null;
    }
  }

  Future<Map<String, dynamic>?> releaseEscrow(int jobId) async {
    try {
      final result = await _paymentService.releaseEscrow(jobId);
      // Refresh wallet after release
      await loadWallet();
      return result;
    } catch (e) {
      setError(e.toString());
      return null;
    }
  }

  Future<bool> releaseEscrowWithOtp(int jobId, String otp) async {
    try {
      await _paymentService.submitEscrowReleaseOtp(jobId, otp);
      await loadWallet();
      return true;
    } catch (e) {
      setError(e.toString());
      return false;
    }
  }

  Future<Map<String, dynamic>?> getEscrowStatus(int jobId) async {
    try {
      return await _paymentService.getEscrowStatus(jobId);
    } catch (e) {
      return null;
    }
  }

  Future<bool> initiatePayment({required double amount, required int jobId}) async {
    try {
      await _paymentService.initiatePaystackPayment(
        amount: amount,
        jobId: jobId,
      );
      // The result contains an authorization_url for Paystack
      // The calling screen should handle the redirect
      return true;
    } catch (e) {
      setError(e.toString());
      return false;
    }
  }
}