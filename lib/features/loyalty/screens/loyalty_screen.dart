import 'package:flutter/material.dart';
import 'package:app_quanly_giaiui/core/constants/app_strings.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/features/loyalty/data/loyalty_repository.dart';

class LoyaltyScreen extends StatefulWidget {
  const LoyaltyScreen({super.key});

  @override
  State<LoyaltyScreen> createState() => _LoyaltyScreenState();
}

class _LoyaltyScreenState extends State<LoyaltyScreen> {
  final _repository = LoyaltyRepository();
  late Future<LoyaltySummary> _summaryFuture;

  @override
  void initState() {
    super.initState();
    _summaryFuture = _repository.getSummary();
  }

  void _retry() {
    setState(() {
      _summaryFuture = _repository.getSummary();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.loyalty)),
      body: FutureBuilder<LoyaltySummary>(
        future: _summaryFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 48),
                  const SizedBox(height: 12),
                  const Text('Không tải được điểm và khuyến mãi.'),
                  TextButton(onPressed: _retry, child: const Text('Thử lại')),
                ],
              ),
            );
          }

          final summary = snapshot.data!;
          return RefreshIndicator(
            onRefresh: () async {
              final future = _repository.getSummary();
              setState(() {
                _summaryFuture = future;
              });
              await future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                _buildPointsCard(summary.points),
                const SizedBox(height: 28),
                Text('Quyền lợi thành viên', style: AppTypography.heading3),
                const SizedBox(height: 16),
                _buildBenefit(Icons.percent, 'Tích điểm theo đơn hàng', 'Điểm được cập nhật sau khi đơn hoàn tất.'),
                _buildBenefit(Icons.local_shipping_outlined, 'Ưu đãi giao nhận', 'Mã giảm giá được cửa hàng phát hành theo từng chương trình.'),
                const SizedBox(height: 20),
                Text(AppStrings.vouchers, style: AppTypography.heading3),
                const SizedBox(height: 12),
                if (summary.vouchers.isEmpty)
                  const Text('Hiện chưa có mã giảm giá khả dụng.')
                else
                  ...summary.vouchers.map(_buildVoucher),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildPointsCard(int points) {
    final progress = (points / 2000).clamp(0.0, 1.0);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: AppColors.heroCardGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Điểm tích lũy', style: AppTypography.title.copyWith(color: Colors.white)),
              const Icon(Icons.stars_rounded, color: Colors.white, size: 32),
            ],
          ),
          const SizedBox(height: 16),
          Text('$points', style: AppTypography.heading1.copyWith(color: Colors.white, fontSize: 40)),
          Text('điểm', style: AppTypography.bodySmall.copyWith(color: Colors.white.withValues(alpha: 0.8))),
          const SizedBox(height: 24),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '${2000 - points.clamp(0, 2000)} điểm để lên hạng tiếp theo',
            style: AppTypography.caption.copyWith(color: Colors.white.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildBenefit(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: AppTypography.title),
            const SizedBox(height: 4),
            Text(subtitle, style: AppTypography.bodySmall),
          ])),
        ],
      ),
    );
  }

  Widget _buildVoucher(LoyaltyVoucher voucher) {
    final isPercent = voucher.discountType == 'Phần trăm';
    final discount = isPercent
        ? '${voucher.discountValue.toStringAsFixed(0)}%'
        : '${voucher.discountValue.toStringAsFixed(0)} đ';
    final condition = voucher.minimumOrder == null
        ? voucher.condition ?? ''
        : '${voucher.condition ?? ''} Từ ${voucher.minimumOrder!.toStringAsFixed(0)} đ';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.divider)),
      child: Row(
        children: [
          const Icon(Icons.confirmation_number_outlined, color: AppColors.primary, size: 34),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(voucher.title, style: AppTypography.title),
            const SizedBox(height: 4),
            Text('Giảm $discount', style: AppTypography.bodySmall),
            Text(condition, style: AppTypography.caption),
            Text('Mã: ${voucher.code}', style: AppTypography.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold)),
          ])),
        ],
      ),
    );
  }
}
