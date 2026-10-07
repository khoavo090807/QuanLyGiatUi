import 'package:flutter/material.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/core/utils/formatter_utils.dart';
import 'package:app_quanly_giaiui/features/order/data/order_repository.dart';
import 'package:app_quanly_giaiui/features/order/domain/cart_item.dart';
import 'package:app_quanly_giaiui/features/order/domain/cart_store.dart';
import 'package:app_quanly_giaiui/features/order/widgets/cart_icon_button.dart';
import 'package:app_quanly_giaiui/features/order/widgets/measurement_dialog.dart';

class LaundryItemTypeDetailScreen extends StatefulWidget {
  const LaundryItemTypeDetailScreen({required this.itemTypeId, super.key});

  final String itemTypeId;

  @override
  State<LaundryItemTypeDetailScreen> createState() =>
      _LaundryItemTypeDetailScreenState();
}

class _LaundryItemTypeDetailScreenState
    extends State<LaundryItemTypeDetailScreen> {
  final _repository = OrderRepository();
  late Future<LaundryCatalogData> _catalogFuture;

  @override
  void initState() {
    super.initState();
    _catalogFuture = _repository.getActiveLaundryCatalog();
  }

  void _retry() {
    setState(() => _catalogFuture = _repository.getActiveLaundryCatalog());
  }

  Future<void> _addPriceToCart(
    LaundryPriceOption price,
    List<LaundryPriceOption> allPrices,
  ) async {
    await CartStore.instance.restore(allPrices);
    if (!mounted) return;

    final value = await showDialog<String>(
      context: context,
      builder: (_) => MeasurementDialog(
        title: 'Thêm ${price.itemTypeName}',
        initialValue: '1',
        label: price.unitSymbol.toLowerCase() == 'kg'
            ? 'Khối lượng (kg)'
            : 'Số lượng',
        unit: price.unitSymbol,
        submitLabel: 'Thêm vào giỏ',
      ),
    );
    if (value == null || !mounted) return;

    final measurement = num.tryParse(value.replaceAll(',', '.'));
    if (measurement == null ||
        !measurement.isFinite ||
        measurement <= 0 ||
        measurement > 99999999.99 ||
        measurement * 100 != (measurement * 100).round()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nhập số lượng hợp lệ, tối đa 2 chữ số thập phân.'),
        ),
      );
      return;
    }

    CartStore.instance.add(
      CartItem(price: price, measurement: measurement),
    );
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Đã thêm ${price.serviceName} · ${price.itemTypeName} vào giỏ.',
          ),
        ),
      );
  }

  IconData _serviceIcon(String name) {
    final normalized = name.toLowerCase();
    if (normalized.contains('khô')) return Icons.dry_cleaning_outlined;
    if (normalized.contains('sấy')) return Icons.air_outlined;
    if (normalized.contains('ủi')) return Icons.iron_outlined;
    if (normalized.contains('tẩy')) return Icons.cleaning_services_outlined;
    return Icons.water_drop_outlined;
  }

  Color _serviceColor(String name) {
    final normalized = name.toLowerCase();
    if (normalized.contains('khô')) return AppColors.secondary;
    if (normalized.contains('sấy')) return AppColors.warning;
    if (normalized.contains('ủi')) return AppColors.success;
    if (normalized.contains('tẩy')) return AppColors.info;
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    final id = int.tryParse(widget.itemTypeId);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chi tiết loại đồ'),
        actions: const [CartIconButton()],
      ),
      body: FutureBuilder<LaundryCatalogData>(
        future: _catalogFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _DetailMessage(
              icon: Icons.cloud_off_outlined,
              message: 'Không tải được thông tin loại đồ.',
              action: OutlinedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            );
          }

          final data = snapshot.data!;
          final itemType = data.itemTypes
              .where((item) => item.id == id)
              .firstOrNull;
          if (itemType == null) {
            return const _DetailMessage(
              icon: Icons.inventory_2_outlined,
              message: 'Không tìm thấy loại đồ này hoặc loại đồ đã ngừng hoạt động.',
            );
          }
          final prices = data.prices
              .where((price) => price.itemTypeId == itemType.id)
              .toList(growable: false);

          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 28,
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.primary,
                      child: Icon(
                        Icons.local_laundry_service_outlined,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(itemType.name, style: AppTypography.heading2),
                          const SizedBox(height: 4),
                          Text(
                            itemType.description?.trim().isNotEmpty == true
                                ? itemType.description!.trim()
                                : 'Thông tin chi tiết đang được cập nhật.',
                            style: AppTypography.bodyText.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Text('Dịch vụ hỗ trợ', style: AppTypography.heading2),
              const SizedBox(height: 6),
              Text(
                'Các dịch vụ và đơn giá hiện áp dụng cho ${itemType.name.toLowerCase()}.',
                style: AppTypography.bodyText.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              if (prices.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: _DetailMessage(
                      icon: Icons.info_outline,
                      message:
                          'Hiện chưa có dịch vụ hoặc đơn giá cho loại đồ này. Vui lòng liên hệ cửa hàng để được tư vấn.',
                    ),
                  ),
                )
              else
                ...prices.map((price) {
                  final color = _serviceColor(price.serviceName);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  _serviceIcon(price.serviceName),
                                  color: color,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (price.serviceTypeName != null &&
                                        price.serviceTypeName!.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: color.withValues(alpha: 0.1),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          price.serviceTypeName!,
                                          style: AppTypography.caption.copyWith(
                                            color: color,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    const SizedBox(height: 5),
                                    Text(
                                      price.serviceName,
                                      style: AppTypography.title,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                '${FormatterUtils.formatVnd(price.unitPriceVnd)}/${price.unitSymbol}',
                                style: AppTypography.title.copyWith(
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                          if (price.serviceDescription?.trim().isNotEmpty ==
                              true) ...[
                            const SizedBox(height: 10),
                            Text(
                              price.serviceDescription!.trim(),
                              style: AppTypography.bodySmall,
                            ),
                          ],
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.straighten_outlined,
                                size: 16,
                                color: AppColors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Đơn vị: ${price.unitName}',
                                style: AppTypography.bodySmall.copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (price.processingTimeMinutes != null &&
                                  price.processingTimeMinutes! > 0) ...[
                                const SizedBox(width: 14),
                                const Icon(
                                  Icons.schedule_outlined,
                                  size: 16,
                                  color: AppColors.textSecondary,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  '${price.processingTimeMinutes} phút',
                                  style: AppTypography.bodySmall,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => _addPriceToCart(
                                price,
                                data.prices,
                              ),
                              icon: const Icon(Icons.add_shopping_cart_outlined),
                              label: const Text('Thêm vào giỏ hàng'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 8),
              Text(
                'Đơn giá cuối cùng có thể được cửa hàng xác nhận sau khi kiểm nhận đồ.',
                style: AppTypography.caption,
                textAlign: TextAlign.center,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DetailMessage extends StatelessWidget {
  const _DetailMessage({required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}
