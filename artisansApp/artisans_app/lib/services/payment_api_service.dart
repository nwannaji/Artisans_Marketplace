// lib/services/payment_api_service.dart

import '../models/job.dart';
import '../models/wallet.dart';
import '../models/bank_account.dart';
import 'api_client.dart';

class PaymentApiService {
  final ApiClient _apiClient = ApiClient();

  /// Get the current user's wallet
  Future<Wallet> getWallet() async {
    final result = await _apiClient.get('/api/payments/wallet/');
    return Wallet.fromJson(result);
  }

  /// List transactions for the current user's wallet
  Future<List<Transaction>> listTransactions() async {
    final result = await _apiClient.getList('/api/payments/transactions/');
    return result.map((json) => Transaction.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// Create a transaction (deposit, withdrawal, etc.)
  Future<Transaction> createTransaction(Map<String, dynamic> data) async {
    final result = await _apiClient.post('/api/payments/transactions/', body: data);
    return Transaction.fromJson(result);
  }

  /// Initiate a wallet deposit via Paystack
  Future<Map<String, dynamic>> depositToWallet({required double amount}) async {
    return await _apiClient.post('/api/payments/deposit/', body: {
      'amount': amount.toString(),
    });
  }

  /// Fund escrow for a job (customer only)
  Future<Map<String, dynamic>> fundEscrow(int jobId, {double? amount}) async {
    final body = <String, dynamic>{};
    if (amount != null) body['amount'] = amount.toString();
    return await _apiClient.post('/api/payments/escrow/$jobId/fund/', body: body);
  }

  /// Release escrow for a job (customer confirms completion)
  Future<Map<String, dynamic>> releaseEscrow(int jobId) async {
    return await _apiClient.post('/api/payments/escrow/$jobId/release/');
  }

  /// Get escrow status (for polling after Pandascrow payment)
  Future<Map<String, dynamic>> getEscrowStatus(int jobId) async {
    return await _apiClient.get('/api/payments/escrow/$jobId/status/');
  }

  /// Submit OTP for Pandascrow escrow release
  Future<Map<String, dynamic>> submitEscrowReleaseOtp(int jobId, String otp) async {
    return await _apiClient.post('/api/payments/escrow/$jobId/release/otp/', body: {'otp': otp});
  }

  /// Initiate a Paystack payment
  Future<Map<String, dynamic>> initiatePaystackPayment({
    required double amount,
    required int jobId,
  }) async {
    return await _apiClient.post('/api/payments/paystack/payment/', body: {
      'amount': amount.toString(),
      'job_id': jobId,
    });
  }

  /// Verify a Paystack payment callback
  Future<Map<String, dynamic>> verifyPaystackPayment(String reference) async {
    return await _apiClient.post('/api/payments/paystack/callback/', body: {
      'reference': reference,
    });
  }

  // ---- Bank Account Management ----

  /// List the current user's bank accounts
  Future<List<BankAccount>> listBankAccounts() async {
    final result = await _apiClient.getList('/api/payments/bank-accounts/');
    return result.map((json) => BankAccount.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// Add a new bank account
  Future<BankAccount> addBankAccount({
    required String bankCode,
    required String accountNumber,
    required String accountName,
  }) async {
    final result = await _apiClient.post('/api/payments/bank-accounts/', body: {
      'bank_code': bankCode,
      'account_number': accountNumber,
      'account_name': accountName,
    });
    return BankAccount.fromJson(result);
  }

  /// Verify a bank account via Paystack
  Future<Map<String, dynamic>> verifyBankAccount(int bankAccountId) async {
    return await _apiClient.post('/api/payments/bank-accounts/$bankAccountId/verify/');
  }

  /// Delete a bank account
  Future<void> deleteBankAccount(int bankAccountId) async {
    await _apiClient.delete('/api/payments/bank-accounts/$bankAccountId/');
  }

  // ---- Withdrawals ----

  /// Initiate a withdrawal from wallet to bank account
  Future<Map<String, dynamic>> withdraw({
    required double amount,
    int? bankAccountId,
  }) async {
    final body = <String, dynamic>{
      'amount': amount.toString(),
    };
    if (bankAccountId != null) body['bank_account_id'] = bankAccountId;
    return await _apiClient.post('/api/payments/withdraw/', body: body);
  }

  // ---- Admin Escrow Management ----

  /// Admin: list all jobs with held escrow
  Future<List<Job>> adminListEscrowJobs() async {
    final result = await _apiClient.getList('/api/payments/admin/escrow/');
    return result.map((json) => Job.fromJson(json as Map<String, dynamic>)).toList();
  }

  /// Admin: release escrow for a job (pays artisan minus commission)
  Future<Map<String, dynamic>> adminReleaseEscrow(int jobId) async {
    return await _apiClient.post('/api/payments/admin/escrow/$jobId/release/');
  }

  /// Admin: refund escrow for a job (full or partial refund to customer)
  Future<Map<String, dynamic>> adminRefundEscrow(int jobId, {double? amount}) async {
    final body = <String, dynamic>{};
    if (amount != null) body['refund_amount'] = amount.toString();
    return await _apiClient.post('/api/payments/admin/escrow/$jobId/refund/', body: body);
  }
}