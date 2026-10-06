import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/features/order/data/order_repository.dart';
import 'package:app_quanly_giaiui/features/order/domain/cart_store.dart';
import 'package:app_quanly_giaiui/features/order/widgets/measurement_dialog.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  final _repository = OrderRepository();
  late Future<void> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = _restoreCart();
  }

  Future<void> _restoreCart() async {
    final prices = await _repository.getActivePrices();
    await CartStore.instance.restore(prices);
  }

  bool _isWeightBased(String symbol) {
    final normalized = symbol.toLowerCase();
    return normalized == 'kg' || normalized == 'kilogram';
  }

  String _formatVnd(num value) => '${value.toStringAsFixed(0)} đ';

  void _adjustMeasurement(int index, double delta) {
    final cart = CartStore.instance;
    final item = cart.items[index];
    final next = item.measurement + delta;
    if (next <= 0) {
      cart.removeAt(index);
    } else {
      cart.setMeasurement(index, next);
    }
  }

  Future<void> _editMeasurement(int index) async {
    final item = CartStore.instance.items[index];
    final value = await showDialog<String>(
      context: context,
      builder: (_) => MeasurementDialog(
        title: 'Chỉnh số lượng',
        initialValue: item.measurement.toString(),
        label: 'Số lượng hoặc khối lượng',
        unit: item.price.unitSymbol,
        submitLabel: 'Lưu',
      ),
    );
    if (value == null || !mounted) return;
    final measurement = num.tryParse(value.trim().replaceAll(',', '.'));
    if (measurement == null ||
        !measurement.isFinite ||
        measurement <= 0 ||
        measurement > 99999999.99 ||
        measurement * 100 != (measurement * 100).round()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nhập giá trị hợp lệ, tối đa 2 chữ số thập phân.'),
        ),
      );
      return;
    }
    CartStore.instance.setMeasurement(index, measurement);
  }

  Future<void> _confirmClearCart() async {
    final shouldClear = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa giỏ hàng?'),
        content: const Text('Tất cả dịch vụ trong giỏ sẽ bị xóa.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Giữ lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa giỏ'),
          ),
        ],
      ),
    );
    if (shouldClear == true) CartStore.instance.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Giỏ hàng'),
        actions: [
          ListenableBuilder(
            listenable: CartStore.instance,
            builder: (context, _) => CartStore.instance.items.isEmpty
                ? const SizedBox.shrink()
                : TextButton(
                    onPressed: _confirmClearCart,
                    child: const Text('Xóa tất cả'),
                  ),
          ),
        ],
      ),
      body: FutureBuilder<void>(
        future: _loadFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Không tải được giá dịch vụ trong giỏ.'),
                  TextButton(
                    onPressed: () => setState(() {
                      _loadFuture = _restoreCart();
                    }),
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            );
          }

          return ListenableBuilder(
            listenable: CartStore.instance,
            builder: (context, _) {
              final cart = CartStore.instance;
              if (cart.items.isEmpty) {
                return _EmptyCart(unavailableItems: cart.unavailableItems);
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 150),
                children: [
                  if (cart.unavailableItems > 0) ...[
                    _UnavailableItemsNotice(count: cart.unavailableItems),
                    const SizedBox(height: 12),
                  ],
                  if (cart.priceChangedItems > 0) ...[
                    _PriceChangedNotice(count: cart.priceChangedItems),
                    const SizedBox(height: 12),
                  ],
                  Text(
                    '${cart.itemCount} loại dịch vụ',
                    style: AppTypography.title,
                  ),
                  const SizedBox(height: 12),
                  ...cart.items.indexed.map((entry) {
                    final index = entry.$1;
                    final item = entry.$2;
                    final weightBased = _isWeightBased(item.price.unitSymbol);
                    final step = weightBased ? 0.5 : 1.0;
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
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.price.serviceName,
                                        style: AppTypography.title,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        item.price.itemTypeName,
                                        style: AppTypography.bodyText.copyWith(
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Xóa mục',
                                  onPressed: () => cart.removeAt(index),
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: AppColors.error,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_formatVnd(item.price.unitPriceVnd)} / ${item.price.unitSymbol}',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const Divider(height: 24),
                            Row(
                              children: [
                                IconButton.outlined(
                                  tooltip: 'Giảm',
                                  onPressed: () =>
                                      _adjustMeasurement(index, -step),
                                  icon: const Icon(Icons.remove),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  child: TextButton(
                                    onPressed: () =>
                                        _editMeasurement(index),
                                    child: Text(
                                      '${item.measurement} ${item.price.unitSymbol}',
                                      style: AppTypography.title,
                                    ),
                                  ),
                                ),
                                IconButton.outlined(
                                  tooltip: 'Tăng',
                                  onPressed: () =>
                                      _adjustMeasurement(index, step),
                                  icon: const Icon(Icons.add),
                                ),
                                const Spacer(),
                                Text(
                                  _formatVnd(
                                    item.estimatedTotalMinorUnits / 100,
                                  ),
                                  style: AppTypography.title.copyWith(
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => context.go(AppRoutes.homePath),
                      icon: const Icon(Icons.add),
                      label: const Text('Chọn thêm dịch vụ'),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
      bottomSheet: ListenableBuilder(
        listenable: CartStore.instance,
        builder: (context, _) {
          final cart = CartStore.instance;
          if (!cart.isRestored || cart.items.isEmpty) {
            return const SizedBox.shrink();
          }
          return Container(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.divider)),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Expanded(child: Text('Tạm tính')),
                      Text(
                        _formatVnd(cart.subtotalMinorUnits / 100),
                        style: AppTypography.title,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () =>
                          context.pushNamed(
                            AppRoutes.createOrder,
                            extra: 'cart',
                          ),
                      child: const Text('Tiếp tục đặt đơn'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  const _EmptyCart({required this.unavailableItems});

  final int unavailableItems;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.shopping_cart_outlined,
              size: 64,
              color: AppColors.textSecondary,
            ),
            const SizedBox(height: 16),
            Text('Giỏ hàng đang trống', style: AppTypography.heading2),
            const SizedBox(height: 8),
            const Text(
              'Chọn dịch vụ và loại đồ giặt để thêm vào giỏ.',
              textAlign: TextAlign.center,
            ),
            if (unavailableItems > 0) ...[
              const SizedBox(height: 12),
              _UnavailableItemsNotice(count: unavailableItems),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => context.go(AppRoutes.homePath),
              icon: const Icon(Icons.local_laundry_service_outlined),
              label: const Text('Khám phá dịch vụ'),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnavailableItemsNotice extends StatelessWidget {
  const _UnavailableItemsNotice({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count mục trong giỏ đã được bỏ vì bảng giá không còn khả dụng.',
        style: AppTypography.bodySmall.copyWith(color: AppColors.warning),
      ),
    );
  }
}

class _PriceChangedNotice extends StatelessWidget {
  const _PriceChangedNotice({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Giá của $count mục đã được cập nhật theo bảng giá hiện tại. Hãy kiểm tra lại tổng tiền trước khi đặt.',
        style: AppTypography.bodySmall.copyWith(color: AppColors.warning),
      ),
    );
  }
}
