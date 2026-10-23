import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/features/order/data/order_repository.dart';
import 'package:app_quanly_giaiui/features/order/widgets/cart_icon_button.dart';
import 'package:app_quanly_giaiui/features/services/service_visual_style.dart';

class ServiceCatalogScreen extends StatefulWidget {
  const ServiceCatalogScreen({super.key});

  @override
  State<ServiceCatalogScreen> createState() => _ServiceCatalogScreenState();
}

class _ServiceCatalogScreenState extends State<ServiceCatalogScreen> {
  static const _catalogLoadTimeout = Duration(seconds: 15);

  final _repository = OrderRepository();
  final _searchController = TextEditingController();
  late Future<LaundryCatalogData> _catalogFuture;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _catalogFuture = _loadCatalog();
  }

  Future<LaundryCatalogData> _loadCatalog() =>
      _repository.getActiveLaundryCatalog().timeout(_catalogLoadTimeout);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dịch vụ'),
        actions: const [CartIconButton()],
      ),
      body: FutureBuilder<LaundryCatalogData>(
        future: _catalogFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Không tải được danh sách dịch vụ.'),
                  TextButton(
                    onPressed: () {
                      final future = _loadCatalog();
                      setState(() {
                        _catalogFuture = future;
                      });
                    },
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            );
          }

          final groups = <String, Map<int, LaundryPriceOption>>{};
          for (final price in snapshot.data!.prices) {
            final category = price.serviceTypeName?.trim();
            groups
                .putIfAbsent(
                  category == null || category.isEmpty
                      ? 'Dịch vụ khác'
                      : category,
                  () => <int, LaundryPriceOption>{},
                )
                .putIfAbsent(price.serviceId, () => price);
          }
          final query = _query.trim().toLowerCase();
          final visibleGroups = groups.entries
              .map((entry) {
                final services = entry.value.values
                    .where(
                      (service) =>
                          query.isEmpty ||
                          entry.key.toLowerCase().contains(query) ||
                          service.serviceName.toLowerCase().contains(query),
                    )
                    .toList(growable: false);
                return MapEntry(entry.key, services);
              })
              .where((entry) => entry.value.isNotEmpty)
              .toList(growable: false);

          return RefreshIndicator(
            onRefresh: () async {
              final future = _loadCatalog();
              setState(() {
                _catalogFuture = future;
              });
              try {
                await future;
              } catch (_) {
                // The FutureBuilder shows the error and retry action.
              }
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: 'Tìm dịch vụ',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
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
                const SizedBox(height: 16),
                if (visibleGroups.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Text(
                      'Chưa có dịch vụ phù hợp.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  ...visibleGroups.map((group) => Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          border: Border.all(color: AppColors.divider),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                group.key,
                                style: AppTypography.heading3,
                              ),
                            ),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 4,
                                mainAxisSpacing: 8,
                                crossAxisSpacing: 8,
                                childAspectRatio: 0.9,
                              ),
                              itemCount: group.value.length,
                              itemBuilder: (context, index) {
                                final service = group.value[index];
                                final visual =
                                    ServiceVisualStyle.forService(service);
                                return InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () => context.pushNamed(
                                    AppRoutes.serviceDetail,
                                    pathParameters: {
                                      'id': service.serviceId.toString(),
                                    },
                                  ),
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          color: visual.backgroundColor,
                                          borderRadius:
                                              BorderRadius.circular(14),
                                        ),
                                        child: Icon(
                                          visual.icon,
                                          color: visual.color,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        service.serviceName,
                                        style: AppTypography.caption.copyWith(
                                          color: AppColors.textPrimary,
                                          fontSize: 11,
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      )),
              ],
            ),
          );
        },
      ),
    );
  }
}
