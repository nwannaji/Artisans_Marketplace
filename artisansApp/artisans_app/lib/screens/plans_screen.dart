import 'package:artisans_app/models/subscription.dart';
import 'package:artisans_app/services/subscription_api_service.dart';
import 'package:artisans_app/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// Plans/Pricing screen showing subscription tiers.
/// All pricing, features, and payment details come from the backend —
/// no hardcoded bank details or prices in the app.
class PlansScreen extends StatefulWidget {
  const PlansScreen({super.key});

  @override
  State<PlansScreen> createState() => _PlansScreenState();
}

class _PlansScreenState extends State<PlansScreen> {
  final _subscriptionService = SubscriptionApiService();
  Subscription? _currentSubscription;
  List<TierInfo> _tiers = [];
  PaymentInfo? _paymentInfo;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final subscriptionResult = _subscriptionService.getMySubscription();
      final tierResult = _subscriptionService.getTierInfo();

      final results = await Future.wait([
        subscriptionResult,
        tierResult,
      ]);
      if (mounted) {
        setState(() {
          _currentSubscription = results[0] as Subscription;
          final tierResponse = results[1] as TierListResponse;
          _tiers = tierResponse.tiers;
          _paymentInfo = tierResponse.paymentInfo;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  SubscriptionTier get _currentTier => _currentSubscription?.effectiveTier ?? SubscriptionTier.free;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription Plans'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // Header
                  Text(
                    'Choose Your Plan',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Upgrade to get more bookings and visibility',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  if (_currentSubscription != null && !_currentSubscription!.isFree) ...[
                    const SizedBox(height: 12),
                    _buildCurrentPlanBanner(),
                  ],
                  const SizedBox(height: 20),
                  // Tier cards
                  ..._tiers.map((tier) => _buildTierCard(tier)),
                  const SizedBox(height: 24),
                  // Payment info section — all from backend
                  if (_paymentInfo != null) _buildPaymentInfo(_paymentInfo!),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }

  Widget _buildCurrentPlanBanner() {
    final sub = _currentSubscription!;
    final color = sub.isPremium
        ? Colors.purple
        : sub.isPro
            ? Colors.amber[700]!
            : Colors.grey;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.verified, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Plan: ${sub.tierLabel}',
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
                if (sub.expiresAt != null)
                  Text(
                    'Expires: ${_formatDate(sub.expiresAt!)}',
                    style: TextStyle(fontSize: 12, color: color),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierCard(TierInfo tier) {
    final isCurrentTier = _tierMatchesCurrent(tier);
    final isProOrPremium = tier.tier == 'PRO' || tier.tier == 'PREMIUM';
    final isPremium = tier.tier == 'PREMIUM';

    final Color accentColor = isPremium
        ? Colors.purple
        : tier.tier == 'PRO'
            ? Colors.amber[700]!
            : Colors.grey;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrentTier ? accentColor : Colors.grey.shade300,
          width: isCurrentTier ? 2 : 1,
        ),
        boxShadow: isPremium
            ? [
                BoxShadow(
                  color: Colors.purple.withValues(alpha: 0.15),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: name + badge
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (tier.badge != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            tier.badge!,
                            style: TextStyle(
                              color: accentColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        tier.name,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isCurrentTier)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: accentColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Current Plan',
                      style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Price
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  tier.monthlyPrice,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: accentColor,
                  ),
                ),
                if (isProOrPremium)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 4),
                    child: Text(
                      '/month',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            // Features
            ...tier.features.map((feature) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, size: 18, color: accentColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          feature,
                          style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                        ),
                      ),
                    ],
                  ),
                )),
            if (isProOrPremium && !isCurrentTier) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _showUpgradeInfo(tier),
                  child: Text(
                    tier.tier == 'PRO' ? 'Upgrade to Pro' : 'Upgrade to Premium',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentInfo(PaymentInfo info) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'How to Upgrade',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'To upgrade your plan, make a bank transfer and contact us:',
            style: TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 12),
          _buildPaymentRow(Icons.account_balance, 'Bank:', info.bankName),
          _buildPaymentRow(Icons.numbers, 'Account:', info.accountNumber),
          _buildPaymentRow(Icons.business, 'Account Name:', info.accountName),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          const Text(
            'After payment, send proof of transfer via:',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _launchWhatsApp(info.whatsappNumber, info.whatsappMessage),
                  icon: const Icon(Icons.chat, size: 18),
                  label: const Text('WhatsApp'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.green[700],
                    side: BorderSide(color: Colors.green[300]!),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _launchPhone(info.phoneNumber),
                  icon: const Icon(Icons.phone, size: 18),
                  label: const Text('Call Us'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue[700],
                    side: BorderSide(color: Colors.blue[300]!),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.blue[700]),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
          const SizedBox(width: 4),
          Expanded(child: Text(value, style: TextStyle(fontSize: 13, color: Colors.grey[700]))),
        ],
      ),
    );
  }

  bool _tierMatchesCurrent(TierInfo tier) {
    switch (tier.tier) {
      case 'FREE':
        return _currentTier == SubscriptionTier.free;
      case 'PRO':
        return _currentTier == SubscriptionTier.pro;
      case 'PREMIUM':
        return _currentTier == SubscriptionTier.premium;
      default:
        return false;
    }
  }

  void _showUpgradeInfo(TierInfo tier) {
    final info = _paymentInfo;
    if (info == null) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Upgrade to ${tier.name}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              '${tier.monthlyPrice}/month',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppColors.accent),
            ),
            const SizedBox(height: 16),
            const Text('To upgrade, please:', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(height: 8),
            _buildStep('1', 'Make a bank transfer of ${tier.monthlyPrice} to:'),
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 4, bottom: 8),
              child: Text(
                '${info.accountName}\n${info.accountNumber}\n${info.bankName}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            _buildStep('2', 'Send proof of payment via WhatsApp or call:'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _launchWhatsApp(info.whatsappNumber, info.whatsappMessage);
                    },
                    icon: const Icon(Icons.chat),
                    label: const Text('WhatsApp'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _launchPhone(info.phoneNumber);
                    },
                    icon: const Icon(Icons.phone),
                    label: const Text('Call Us'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep(String number, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: AppColors.accent,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(number, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _launchWhatsApp(String number, String message) async {
    final uri = Uri.parse('https://wa.me/$number?text=${Uri.encodeComponent(message)}');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        // Fallback: try launching anyway (canLaunchUrl can be unreliable on some Android 11+ devices)
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open WhatsApp. Please install WhatsApp or contact support.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error opening WhatsApp: $e')),
        );
      }
    }
  }

  Future<void> _launchPhone(String number) async {
    final uri = Uri.parse('tel:$number');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        final launched = await launchUrl(uri);
        if (!launched && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not open the phone dialer.')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error making call: $e')),
        );
      }
    }
  }
}