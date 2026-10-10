import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app_quanly_giaiui/core/constants/app_strings.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/core/widgets/section_header.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/features/auth/data/auth_repository.dart';
import 'package:app_quanly_giaiui/features/notification/data/notification_repository.dart';
import 'package:app_quanly_giaiui/features/notification/services/notification_service.dart';
import 'package:app_quanly_giaiui/features/order/data/order_repository.dart';
import 'package:app_quanly_giaiui/features/order/domain/cart_store.dart';
import 'package:app_quanly_giaiui/features/order/widgets/cart_icon_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    required this.unreadNotificationCount,
    required this.unreadMessageCount,
    required this.onOpenNotifications,
    super.key,
  });

  final ValueNotifier<int> unreadNotificationCount;
  final ValueNotifier<int> unreadMessageCount;
  final VoidCallback onOpenNotifications;
  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final _repository = OrderRepository();
  final _authRepository = AuthRepository();
  final _notificationRepository = NotificationRepository();
  late Future<_HomeData> _homeData;
  StreamSubscription<LaundryNotification>? _notificationSubscription;
  Timer? _messageCountTimer;
  bool _refreshingMessageCount = false;

  @override
  void initState() {
    super.initState();
    _homeData = _loadHomeData();
    _notificationSubscription = NotificationService.instance.onNewNotification
        .listen((notification) {
          if (notification.type == 'new_message') {
            _refreshUnreadMessageCount();
          }
        });
    _messageCountTimer = Timer.periodic(
      const Duration(seconds: 12),
      (_) => _refreshUnreadMessageCount(),
    );
  }

  Future<_HomeData> _loadHomeData() async {
    final prices = await _repository.getActivePrices();
    await CartStore.instance.restore(prices);
    List<LaundryOrderRecord> orders = const [];
    List<String> roles = const [];
    AuthenticatedProfile? profile;

    try {
      orders = await _repository.getCustomerHistory();
    } catch (_) {
      // A new account may not have an order profile yet.
    }
    try {
      roles = await _authRepository.getCurrentRoles();
    } catch (_) {
      // Missing account/role data should not block the customer UI.
    }
    try {
      profile = await _authRepository.getCurrentProfile();
    } catch (_) {
      // Profile data should not block the home screen.
    }
    try {
      final unreadCount = await _notificationRepository.getUnreadCount();
      if (mounted) widget.unreadNotificationCount.value = unreadCount;
    } catch (_) {
      if (mounted) widget.unreadNotificationCount.value = 0;
    }
    try {
      final unreadMessages = await _notificationRepository
          .getUnreadMessageCount();
      if (mounted) widget.unreadMessageCount.value = unreadMessages;
    } catch (_) {
      if (mounted) widget.unreadMessageCount.value = 0;
    }

    return _HomeData(
      prices: prices,
      orders: orders,
      roles: roles,
      profile: profile,
    );
  }

  void refresh() {
    final future = _loadHomeData();
    setState(() {
      _homeData = future;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: FutureBuilder<_HomeData>(
          future: _homeData,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Không tải được dữ liệu trang chủ.'),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _homeData = _loadHomeData();
                        });
                      },
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              );
            }

            final data = snapshot.data!;
            return RefreshIndicator(
              onRefresh: () async {
                refresh();
                await _homeData;
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, data.profile),
                    const SizedBox(height: 16),
                    if (data.roles.any(
                      {'Nhân viên', 'Quản lý', 'Chủ cửa hàng'}.contains,
                    )) ...[
                      _buildStaffShortcut(context),
                      const SizedBox(height: 16),
                    ],
                    _buildActiveOrderCard(context, data.orders),
                    const SizedBox(height: 16),
                    _buildLaundryCatalogShortcut(context),
                    const SizedBox(height: 16),
                    SectionHeader(
                      title: AppStrings.services,
                      actionText: AppStrings.seeAll,
                      onActionTap: () =>
                          context.pushNamed(AppRoutes.createOrder),
                    ),
                    _buildServicesGrid(context, data.prices),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.pushNamed(AppRoutes.createOrder),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text(AppStrings.newOrder),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, AuthenticatedProfile? profile) {
    final avatarUrl = profile?.avatarUrl;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 25,
            backgroundColor: AppColors.primaryLight,
            backgroundImage: avatarUrl == null ? null : NetworkImage(avatarUrl),
            child: avatarUrl == null
                ? const Icon(Icons.person, color: AppColors.primary, size: 28)
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${AppStrings.hello}${profile?.displayName ?? 'Khách hàng'}',
                  style: AppTypography.title,
                ),
                const SizedBox(height: 2),
                Text(AppStrings.whatService, style: AppTypography.bodySmall),
              ],
            ),
          ),
          const CartIconButton(),
          IconButton(
            tooltip: 'Tin nhắn với cửa hàng',
            onPressed: () async {
              await context.push(AppRoutes.messagesPath);
              await _refreshUnreadMessageCount();
            },
            icon: ValueListenableBuilder<int>(
              valueListenable: widget.unreadMessageCount,
              builder: (context, count, child) => Badge(
                isLabelVisible: count > 0,
                label: Text(count > 99 ? '99+' : '$count'),
                child: child,
              ),
              child: const Icon(Icons.chat_bubble_outline),
            ),
          ),
          ValueListenableBuilder<int>(
            valueListenable: widget.unreadNotificationCount,
            builder: (context, unreadCount, child) => IconButton(
              tooltip: AppStrings.notifications,
              onPressed: widget.onOpenNotifications,
              icon: Badge(
                isLabelVisible: unreadCount > 0,
                smallSize: 8,
                child: child,
              ),
            ),
            child: const Icon(Icons.notifications_outlined),
          ),
        ],
      ),
    );
  }

  // ---- Active Order Card ----
  Widget _buildActiveOrderCard(
    BuildContext context,
    List<LaundryOrderRecord> orders,
  ) {
    final activeOrders = orders.where(
      (order) => !{
        'Đã giao',
        'Đã thanh toán',
        'Đã hủy',
        'Hoàn thành',
      }.contains(order.status),
    );
    final order = activeOrders.firstOrNull;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        constraints: const BoxConstraints(minHeight: 216),
        decoration: BoxDecoration(
          gradient: AppColors.heroCardGradient,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: order == null
              ? MainAxisAlignment.center
              : MainAxisAlignment.start,
          children: order == null
              ? [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.local_laundry_service_outlined,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Chưa có đơn đang xử lý',
                              style: AppTypography.title.copyWith(
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Các cập nhật mới nhất về đơn hàng sẽ hiện ở đây.',
                              style: AppTypography.bodySmall.copyWith(
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ]
              : [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        AppStrings.currentOrders,
                        style: AppTypography.title.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          order.status,
                          style: AppTypography.caption.copyWith(
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Đơn #${order.orderNumber} · ${order.lineDescription}',
                    style: AppTypography.bodyText.copyWith(
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  if (order.logisticsSummary case final logistics?) ...[
                    const SizedBox(height: 4),
                    Text(
                      logistics,
                      style: AppTypography.bodySmall.copyWith(
                        color: Colors.white.withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: 0.35,
                      minHeight: 6,
                      backgroundColor: Colors.white.withValues(alpha: 0.2),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Tạo lúc ${_formatDate(order.createdAt)}',
                        style: AppTypography.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                      ),
                      if (order.orderId != null)
                        TextButton(
                          onPressed: () {
                            context.pushNamed(
                              AppRoutes.trackingDetail,
                              pathParameters: {'id': order.orderId.toString()},
                            );
                          },
                          child: Text(
                            'Chi tiết →',
                            style: AppTypography.bodySmall.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
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

  Widget _buildStaffShortcut(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: OutlinedButton.icon(
        onPressed: () => context.pushNamed(AppRoutes.staffQueue),
        icon: const Icon(Icons.fact_check_outlined),
        label: const Text('Mở hàng đợi nhân viên'),
      ),
    );
  }

  Future<void> _refreshUnreadMessageCount() async {
    if (_refreshingMessageCount || !mounted) return;
    _refreshingMessageCount = true;
    try {
      final count = await _notificationRepository.getUnreadMessageCount();
      if (mounted) widget.unreadMessageCount.value = count;
    } catch (_) {
      // Keep the last known badge count during transient network failures.
    } finally {
      _refreshingMessageCount = false;
    }
  }

  @override
  void dispose() {
    _messageCountTimer?.cancel();
    _notificationSubscription?.cancel();
    super.dispose();
  }

  Widget _buildLaundryCatalogShortcut(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.pushNamed(AppRoutes.laundryCatalog),
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primaryLight,
                  foregroundColor: AppColors.primary,
                  child: Icon(Icons.category_outlined),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Dịch vụ theo loại đồ', style: AppTypography.title),
                      SizedBox(height: 3),
                      Text(
                        'Xem loại đồ và các dịch vụ phù hợp',
                        style: AppTypography.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: AppColors.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- Services Grid ----
  Widget _buildServicesGrid(
    BuildContext context,
    List<LaundryPriceOption> prices,
  ) {
    final uniqueServices = <int, LaundryPriceOption>{};
    for (final price in prices) {
      uniqueServices.putIfAbsent(price.serviceId, () => price);
    }
    final services = uniqueServices.values.toList(growable: false);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          mainAxisSpacing: 16,
          crossAxisSpacing: 12,
          childAspectRatio: 0.75,
        ),
        itemCount: services.length,
        itemBuilder: (context, index) {
          final service = services[index];
          return GestureDetector(
            onTap: () {
              context.pushNamed(
                AppRoutes.serviceDetail,
                pathParameters: {'id': service.serviceId.toString()},
              );
            },
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: _serviceColor(index).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    _serviceIcon(service.serviceName),
                    color: _serviceColor(index),
                    size: 28,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  service.serviceName,
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
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
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}';
  }

  IconData _serviceIcon(String name) {
    final normalized = name.toLowerCase();
    if (normalized.contains('khô')) return Icons.dry_cleaning_outlined;
    if (normalized.contains('sấy')) return Icons.air_outlined;
    if (normalized.contains('ủi')) return Icons.iron_outlined;
    return Icons.water_drop_outlined;
  }

  Color _serviceColor(int index) {
    const colors = [
      AppColors.info,
      AppColors.secondary,
      AppColors.warning,
      AppColors.success,
      AppColors.accent,
    ];
    return colors[index % colors.length];
  }
}

class _HomeData {
  const _HomeData({
    required this.prices,
    required this.orders,
    required this.roles,
    required this.profile,
  });

  final List<LaundryPriceOption> prices;
  final List<LaundryOrderRecord> orders;
  final List<String> roles;
  final AuthenticatedProfile? profile;
}
