import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/core/utils/formatter_utils.dart';
import 'package:app_quanly_giaiui/features/order/data/order_repository.dart';
import 'package:app_quanly_giaiui/features/order/domain/cart_item.dart';
import 'package:app_quanly_giaiui/features/order/domain/cart_store.dart';
import 'package:app_quanly_giaiui/features/order/widgets/cart_icon_button.dart';
import 'package:app_quanly_giaiui/features/order/widgets/measurement_dialog.dart';

class ServiceDetailScreen extends StatefulWidget {
  const ServiceDetailScreen({required this.serviceId, super.key});

  final String serviceId;

  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen> {
  final _repository = OrderRepository();
  late final Future<List<LaundryPriceOption>> _pricesFuture;

  @override
  void initState() {
    super.initState();
    _pricesFuture = _repository.getActivePrices();
  }

  void _startOrder(int priceId) {
    context.pushNamed(AppRoutes.createOrder, extra: priceId);
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
      SnackBar(content: Text('Đã thêm ${price.itemTypeName} vào giỏ.')),
    );
  }

  IconData _serviceIcon(String name) {
    final normalized = name.toLowerCase();
    if (normalized.contains('khô')) return Icons.dry_cleaning_outlined;
    if (normalized.contains('sấy')) return Icons.air_outlined;
    if (normalized.contains('ủi')) return Icons.iron_outlined;
    return Icons.water_drop_outlined;
  }

  Color _serviceColor(String name) {
    final normalized = name.toLowerCase();
    if (normalized.contains('khô')) return AppColors.secondary;
    if (normalized.contains('sấy')) return AppColors.warning;
    if (normalized.contains('ủi')) return AppColors.success;
    return AppColors.info;
  }

  String _processingTimeLabel(int? minutes) {
    if (minutes == null || minutes <= 0) return 'Đang cập nhật';
    return '$minutes phút';
  }

  @override
  Widget build(BuildContext context) {
    final serviceId = int.tryParse(widget.serviceId);
    return Scaffold(
      body: FutureBuilder<List<LaundryPriceOption>>(
        future: _pricesFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(title: const Text('Chi tiết dịch vụ')),
              body: const Center(child: Text('Không tải được bảng giá.')),
            );
          }

          final prices = (snapshot.data ?? const <LaundryPriceOption>[])
              .where((price) => price.serviceId == serviceId)
              .toList(growable: false);
          if (prices.isEmpty) {
            return Scaffold(
              appBar: AppBar(title: const Text('Chi tiết dịch vụ')),
              body: const Center(
                child: Text('Dịch vụ hiện không có bảng giá.'),
              ),
            );
          }

          final service = prices.first;
          final serviceName = service.serviceName;
          final svcColor = _serviceColor(serviceName);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 210,
                pinned: true,
                title: Text(serviceName),
                actions: const [CartIconButton()],
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    color: svcColor.withValues(alpha: 0.1),
                    child: Center(
                      child: Icon(
                        _serviceIcon(serviceName),
                        size: 88,
                        color: svcColor,
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 120),
                sliver: SliverList.list(
                  children: [
                    Text(serviceName, style: AppTypography.heading1),
                    const SizedBox(height: 8),
                    Text(
                      service.serviceDescription?.trim().isNotEmpty == true
                          ? service.serviceDescription!.trim()
                          : 'Mô tả dịch vụ đang được cập nhật.',
                      style: AppTypography.bodyText.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(
                          Icons.schedule_outlined,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Thời gian xử lý dự kiến: '
                          '${_processingTimeLabel(service.processingTimeMinutes)}',
                          style: AppTypography.bodyText,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text('Bảng giá', style: AppTypography.heading3),
                    const SizedBox(height: 10),
                    Table(
                      border: TableBorder.all(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      columnWidths: const {
                        0: FlexColumnWidth(2),
                        1: FlexColumnWidth(2.5),
                        2: FlexColumnWidth(1),
                      },
                      children: [
                        TableRow(
                          decoration: const BoxDecoration(
                            color: AppColors.background,
                            borderRadius: BorderRadius.vertical(
                              top: Radius.circular(8),
                            ),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'Loại đồ',
                                style: AppTypography.bodyText.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(12),
                              child: Text(
                                'Đơn giá',
                                style: AppTypography.bodyText.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(8),
                              child: Text(
                                'Thêm',
                                textAlign: TextAlign.center,
                                style: AppTypography.bodySmall.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        ...prices.map(
                          (price) => TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  price.itemTypeName,
                                  style: AppTypography.bodyText,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Text(
                                  '${FormatterUtils.formatVnd(price.unitPriceVnd)} / ${price.unitSymbol}',
                                  style: AppTypography.bodyText,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Thêm vào giỏ',
                                onPressed: () => _addPriceToCart(
                                  price,
                                  snapshot.data!,
                                ),
                                icon: const Icon(
                                  Icons.add_shopping_cart_outlined,
                                  color: AppColors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text('Quy trình xử lý', style: AppTypography.heading3),
                    const SizedBox(height: 10),
                    const _ProcessStep(
                      number: '1',
                      title: 'Tiếp nhận và kiểm nhận',
                      description:
                          'Cửa hàng xác nhận loại đồ, số lượng hoặc khối lượng thực tế.',
                    ),
                    const _ProcessStep(
                      number: '2',
                      title: 'Xử lý theo dịch vụ',
                      description:
                          'Nhân viên cập nhật trạng thái khi đơn chuyển công đoạn.',
                    ),
                    const _ProcessStep(
                      number: '3',
                      title: 'Hoàn tất và bàn giao',
                      description:
                          'Bạn có thể theo dõi cập nhật trong lịch sử đơn hàng.',
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      bottomSheet: FutureBuilder<List<LaundryPriceOption>>(
        future: _pricesFuture,
        builder: (context, snapshot) {
          final firstPrice = snapshot.data
              ?.where((price) => price.serviceId == serviceId)
              .firstOrNull;
          if (firstPrice == null) return const SizedBox.shrink();
          return Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.surface,
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _startOrder(firstPrice.priceId),
                  child: const Text('Đặt dịch vụ'),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProcessStep extends StatelessWidget {
  const _ProcessStep({
    required this.number,
    required this.title,
    required this.description,
  });

  final String number;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        child: Text(number),
      ),
      title: Text(title, style: AppTypography.title),
      subtitle: Text(description, style: AppTypography.bodySmall),
    );
  }
}
