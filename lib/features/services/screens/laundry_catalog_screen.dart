import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/features/order/data/order_repository.dart';
import 'package:app_quanly_giaiui/features/order/widgets/cart_icon_button.dart';

class LaundryCatalogScreen extends StatefulWidget {
  const LaundryCatalogScreen({super.key});

  @override
  State<LaundryCatalogScreen> createState() => _LaundryCatalogScreenState();
}

class _LaundryCatalogScreenState extends State<LaundryCatalogScreen> {
  final _repository = OrderRepository();
  final _searchController = TextEditingController();
  late Future<LaundryCatalogData> _catalogFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _catalogFuture = _repository.getActiveLaundryCatalog();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _retry() {
    setState(() => _catalogFuture = _repository.getActiveLaundryCatalog());
  }

  IconData _itemIcon(String name) {
    final normalized = name.toLowerCase();
    if (normalized.contains('giày')) return Icons.directions_walk_outlined;
    if (normalized.contains('chăn') || normalized.contains('ga')) {
      return Icons.bed_outlined;
    }
    if (normalized.contains('gấu')) return Icons.toys_outlined;
    if (normalized.contains('váy') || normalized.contains('áo')) {
      return Icons.checkroom_outlined;
    }
    return Icons.local_laundry_service_outlined;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Danh mục loại đồ giặt'),
        actions: const [CartIconButton()],
      ),
      body: FutureBuilder<LaundryCatalogData>(
        future: _catalogFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _CatalogMessage(
              icon: Icons.cloud_off_outlined,
              message: 'Không tải được danh mục loại đồ giặt.',
              action: OutlinedButton.icon(
                onPressed: _retry,
                icon: const Icon(Icons.refresh),
                label: const Text('Thử lại'),
              ),
            );
          }

          final data = snapshot.data!;
          final query = _query.trim().toLowerCase();
          final itemTypes = data.itemTypes
              .where(
                (item) =>
                    query.isEmpty ||
                    item.name.toLowerCase().contains(query) ||
                    (item.description?.toLowerCase().contains(query) ?? false),
              )
              .toList(growable: false);

          if (data.itemTypes.isEmpty) {
            return const _CatalogMessage(
              icon: Icons.inventory_2_outlined,
              message: 'Chưa có loại đồ giặt đang hoạt động.',
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              _retry();
              await _catalogFuture;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: AppColors.heroCardGradient,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.local_laundry_service_outlined,
                          color: Colors.white, size: 30),
                      SizedBox(height: 12),
                      Text(
                        'Chọn loại đồ của bạn',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Xem các dịch vụ phù hợp và đơn giá trước khi đặt.',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Tìm loại đồ giặt',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Xóa nội dung tìm kiếm',
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close),
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text('Các loại đồ', style: AppTypography.heading3),
                const SizedBox(height: 10),
                if (itemTypes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: _CatalogMessage(
                      icon: Icons.search_off_outlined,
                      message: 'Không tìm thấy loại đồ phù hợp.',
                    ),
                  )
                else
                  ...itemTypes.map((item) {
                    final serviceCount = data.prices
                        .where((price) => price.itemTypeId == item.id)
                        .map((price) => price.serviceId)
                        .toSet()
                        .length;
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        leading: CircleAvatar(
                          backgroundColor: AppColors.primaryLight,
                          foregroundColor: AppColors.primary,
                          child: Icon(_itemIcon(item.name)),
                        ),
                        title: Text(item.name, style: AppTypography.title),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${item.description?.trim().isNotEmpty == true ? item.description!.trim() : 'Thông tin chi tiết đang được cập nhật.'}\n'
                            '$serviceCount dịch vụ hỗ trợ',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.pushNamed(
                          AppRoutes.laundryItemTypeDetail,
                          pathParameters: {'id': item.id.toString()},
                        ),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _CatalogMessage extends StatelessWidget {
  const _CatalogMessage({
    required this.icon,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}
