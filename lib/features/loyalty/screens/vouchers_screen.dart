import 'package:flutter/material.dart';
import 'package:app_quanly_giaiui/core/constants/app_strings.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/utils/formatter_utils.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/features/loyalty/data/loyalty_repository.dart';

class VouchersScreen extends StatefulWidget {
  const VouchersScreen({this.highlightCode, super.key});

  final String? highlightCode;

  @override
  State<VouchersScreen> createState() => _VouchersScreenState();
}

class _VouchersScreenState extends State<VouchersScreen> {
  final _repository = LoyaltyRepository();
  late Future<List<LoyaltyVoucher>> _vouchersFuture;
  final GlobalKey _highlightedVoucherKey = GlobalKey();
  bool _hasScrolledToHighlightedVoucher = false;

  @override
  void initState() {
    super.initState();
    _vouchersFuture = _loadVouchers();
  }

  Future<List<LoyaltyVoucher>> _loadVouchers() async {
    final summary = await _repository.getSummary();
    return summary.vouchers;
  }

  void _retry() {
    setState(() {
      _vouchersFuture = _loadVouchers();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.vouchers)),
      body: FutureBuilder<List<LoyaltyVoucher>>(
        future: _vouchersFuture,
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
                  const Text('Không tải được danh sách mã giảm giá.'),
                  TextButton(onPressed: _retry, child: const Text('Thử lại')),
                ],
              ),
            );
          }

          final vouchers = snapshot.data!;
          final highlightCode = widget.highlightCode?.trim();
          final highlightedVoucher =
              highlightCode == null || highlightCode.isEmpty
              ? null
              : vouchers
                    .where(
                      (voucher) =>
                          voucher.code.toLowerCase() ==
                          highlightCode.toLowerCase(),
                    )
                    .firstOrNull;

          if (highlightedVoucher != null && !_hasScrolledToHighlightedVoucher) {
            _hasScrolledToHighlightedVoucher = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              final targetContext = _highlightedVoucherKey.currentContext;
              if (targetContext != null) {
                Scrollable.ensureVisible(
                  targetContext,
                  duration: const Duration(milliseconds: 450),
                  curve: Curves.easeInOut,
                  alignment: 0.35,
                );
              }
            });
          }

          return RefreshIndicator(
            onRefresh: () async {
              final future = _loadVouchers();
              setState(() {
                _vouchersFuture = future;
              });
              await future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                _buildHeader(),
                const SizedBox(height: 24),
                if (highlightCode != null &&
                    highlightCode.isNotEmpty &&
                    highlightedVoucher == null)
                  _buildUnavailablePromotionNotice(),
                if (vouchers.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.card_giftcard_outlined,
                            size: 64,
                            color: AppColors.textSecondary,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Hiện chưa có mã giảm giá khả dụng',
                            style: AppTypography.bodyText.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...vouchers.map((voucher) {
                    final isHighlighted =
                        voucher.code.toLowerCase() ==
                        highlightCode?.toLowerCase();
                    return _buildVoucher(
                      voucher,
                      key: isHighlighted ? _highlightedVoucherKey : null,
                      highlighted: isHighlighted,
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.confirmation_number_outlined,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mã giảm giá',
                  style: AppTypography.heading3.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  'Áp dụng mã khi thanh toán để nhận ưu đãi',
                  style: AppTypography.bodySmall.copyWith(
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnavailablePromotionNotice() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: const Text('Mã giảm giá này không còn hiệu lực.'),
    );
  }

  Widget _buildVoucher(
    LoyaltyVoucher voucher, {
    Key? key,
    bool highlighted = false,
  }) {
    final isPercent = voucher.discountType == 'Phần trăm';
    final discount = isPercent
        ? '${voucher.discountValue.toStringAsFixed(0)}%'
        : FormatterUtils.formatVnd(voucher.discountValue);
    final condition = voucher.minimumOrder == null
        ? voucher.condition ?? ''
        : '${voucher.condition ?? ''} Từ ${FormatterUtils.formatVnd(voucher.minimumOrder!)}';

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlighted ? AppColors.primary : AppColors.divider,
          width: highlighted ? 2.5 : 1,
        ),
        boxShadow: highlighted
            ? [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 14,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.confirmation_number_outlined,
              color: AppColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(voucher.title, style: AppTypography.title),
                const SizedBox(height: 4),
                Text(
                  'Giảm $discount',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'HSD: ${FormatterUtils.formatDate(voucher.expiresAt)}',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (condition.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(condition, style: AppTypography.caption),
                ],
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    voucher.code,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
