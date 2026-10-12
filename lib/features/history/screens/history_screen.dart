import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app_quanly_giaiui/core/constants/app_strings.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/core/utils/formatter_utils.dart';
import 'package:app_quanly_giaiui/core/widgets/status_badge.dart';
import 'package:app_quanly_giaiui/features/order/data/order_repository.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.onVisibilityChanged});

  final void Function(void Function(bool))? onVisibilityChanged;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  late final TabController _tabController;
  final _repository = OrderRepository();
  late Future<List<LaundryOrderHistoryPage>> _ordersFuture;
  bool _isCancelling = false;
  Timer? _autoRefreshTimer;
  bool _isVisible = true;
  final List<List<LaundryOrderRecord>> _ordersByTab = [[], [], []];
  final List<int> _totalCountByTab = [0, 0, 0];
  final List<bool> _isLoadingMoreByTab = [false, false, false];
  final List<bool> _hasLoadMoreErrorByTab = [false, false, false];
  final List<int> _requestVersionByTab = [0, 0, 0];
  final List<ScrollController> _tabScrollControllers = [];
  static const _pageSize = 20;
  static const _statusGroups = ['processing', 'completed', 'cancelled'];

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this);
    _ordersFuture = _fetchHistory();
    for (var tab = 0; tab < 3; tab++) {
      final tabIndex = tab;
      _tabScrollControllers.add(
        ScrollController()..addListener(() => _onTabScroll(tabIndex)),
      );
    }
    _startAutoRefresh();
    widget.onVisibilityChanged?.call(setVisibility);
  }

  void _startAutoRefresh() {
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_isVisible && mounted) {
        _loadHistory();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isVisible) {
      _loadHistory();
    }
  }

  void setVisibility(bool visible) {
    _isVisible = visible;
    if (visible && mounted) {
      _loadHistory();
    }
  }

  void _loadHistory() {
    setState(() {
      _ordersFuture = _fetchHistory(preserveLoaded: true);
    });
  }

  Future<List<LaundryOrderHistoryPage>> _fetchHistory({
    bool preserveLoaded = false,
  }) async {
    for (var tab = 0; tab < _requestVersionByTab.length; tab++) {
      _requestVersionByTab[tab]++;
    }
    final pages = await Future.wait(
      List.generate(3, (tab) async {
        final targetCount = preserveLoaded && _ordersByTab[tab].length > _pageSize
            ? _ordersByTab[tab].length
            : _pageSize;
        final loaded = <LaundryOrderRecord>[];
        var totalCount = 0;
        do {
          final page = await _repository.getCustomerHistoryPage(
            statusGroup: _statusGroups[tab],
            offset: loaded.length,
            limit: _pageSize,
          );
          totalCount = page.totalCount;
          loaded.addAll(page.orders);
          if (!preserveLoaded || page.orders.isEmpty) break;
        } while (loaded.length < targetCount && loaded.length < totalCount);
        return LaundryOrderHistoryPage(
          orders: loaded,
          totalCount: totalCount,
        );
      }),
    );
    if (mounted) {
      for (var tab = 0; tab < pages.length; tab++) {
        _ordersByTab[tab] = pages[tab].orders;
        _totalCountByTab[tab] = pages[tab].totalCount;
        _isLoadingMoreByTab[tab] = false;
        _hasLoadMoreErrorByTab[tab] = false;
      }
    }
    return pages;
  }

  void _onTabScroll(int tab) {
    final controller = _tabScrollControllers[tab];
    if (!controller.hasClients || controller.position.extentAfter >= 300 ||
        _isLoadingMoreByTab[tab] ||
        _ordersByTab[tab].length >= _totalCountByTab[tab]) {
      return;
    }
    _loadMore(tab);
  }

  Future<void> _loadMore(int tab) async {
    if (_isLoadingMoreByTab[tab] ||
        _ordersByTab[tab].length >= _totalCountByTab[tab]) {
      return;
    }
    final requestVersion = _requestVersionByTab[tab];
    setState(() {
      _isLoadingMoreByTab[tab] = true;
      _hasLoadMoreErrorByTab[tab] = false;
    });
    try {
      final page = await _repository.getCustomerHistoryPage(
        statusGroup: _statusGroups[tab],
        offset: _ordersByTab[tab].length,
        limit: _pageSize,
      );
      if (!mounted || requestVersion != _requestVersionByTab[tab]) return;
      setState(() {
        _ordersByTab[tab] = [..._ordersByTab[tab], ...page.orders];
        _totalCountByTab[tab] = page.orders.isEmpty
            ? _ordersByTab[tab].length
            : page.totalCount;
      });
    } catch (_) {
      if (mounted && requestVersion == _requestVersionByTab[tab]) {
        setState(() => _hasLoadMoreErrorByTab[tab] = true);
      }
    } finally {
      if (mounted && requestVersion == _requestVersionByTab[tab]) {
        setState(() => _isLoadingMoreByTab[tab] = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    _tabController.dispose();
    for (final controller in _tabScrollControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    setState(() {
      _ordersFuture = _fetchHistory(preserveLoaded: true);
    });
    await _ordersFuture;
  }

  Future<void> _cancelBooking(LaundryOrderRecord booking) async {
    final bookingId = booking.bookingId;
    if (!booking.canCancelBooking || bookingId == null || _isCancelling) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hủy yêu cầu đặt giặt?'),
        content: const Text('Bạn chỉ có thể hủy trước khi cửa hàng tiếp nhận.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Quay lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Hủy yêu cầu'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isCancelling = true);
    try {
      await _repository.cancelBooking(bookingId);
      await _refresh();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể hủy yêu cầu: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.orderHistory),
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMuted,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Đang xử lý'),
            Tab(text: 'Hoàn tất'),
            Tab(text: 'Đã hủy'),
          ],
        ),
      ),
      body: FutureBuilder<List<LaundryOrderHistoryPage>>(
        future: _ordersFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _StateMessage(
              icon: Icons.cloud_off_outlined,
              message: 'Không tải được lịch sử đơn hàng.',
              action: TextButton(
                onPressed: () => setState(() {
                  _ordersFuture = _fetchHistory();
                }),
                child: const Text('Thử lại'),
              ),
            );
          }

          return TabBarView(
            controller: _tabController,
            children: List.generate(3, (tab) {
              final orders = _ordersByTab[tab];
              final hasMore = orders.length < _totalCountByTab[tab];
              return RefreshIndicator(
                onRefresh: _refresh,
                child: orders.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 140),
                          _StateMessage(
                            icon: Icons.receipt_long_outlined,
                            message: 'Chưa có đơn hàng trong mục này.',
                          ),
                        ],
                      )
                    : ListView.separated(
                        controller: _tabScrollControllers[tab],
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(16),
                        itemCount: orders.length + (hasMore ? 1 : 0),
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          if (index == orders.length) {
                            if (_isLoadingMoreByTab[tab]) {
                              return const Padding(
                                padding: EdgeInsets.all(20),
                                child: Center(
                                  child: SizedBox.square(
                                    dimension: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                              );
                            }
                            if (_hasLoadMoreErrorByTab[tab]) {
                              return Center(
                                child: TextButton(
                                  onPressed: () => _loadMore(tab),
                                  child: const Text('Thử tải thêm'),
                                ),
                              );
                            }
                            return const SizedBox(height: 20);
                          }
                          final order = orders[index];
                          return _OrderCard(
                            order: order,
                            onViewDetails: () {
                              if (order.orderId != null) {
                                context.pushNamed(
                                  AppRoutes.trackingDetail,
                                  pathParameters: {
                                    'id': order.orderId.toString(),
                                  },
                                );
                              } else if (order.bookingId != null) {
                                context.pushNamed(
                                  AppRoutes.trackingDetail,
                                  pathParameters: {
                                    'id': 'booking_${order.bookingId}',
                                  },
                                );
                              }
                            },
                            onCancelBooking: _isCancelling
                                ? null
                                : () => _cancelBooking(order),
                          );
                        },
                      ),
              );
            }),
          );
        },
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.onViewDetails,
    required this.onCancelBooking,
  });

  final LaundryOrderRecord order;
  final VoidCallback onViewDetails;
  final VoidCallback? onCancelBooking;

  @override
  Widget build(BuildContext context) {
    final status = order.status;
    final statusBadge = switch (status) {
      'Đã hủy' => StatusBadge(
          text: status,
          backgroundColor: AppColors.errorLight,
          textColor: AppColors.error,
        ),
      'Đã giao' || 'Đã thanh toán' || 'Hoàn thành' =>
        StatusBadge.completed(text: status),
      'Chờ tiếp nhận' || 'Chờ xác nhận' || 'Đã tiếp nhận' || 'Đang giặt' || 'Chờ trả đồ' =>
        StatusBadge.active(text: status),
      _ => StatusBadge.pending(text: status),
    };

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onViewDetails,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '#${order.orderNumber}',
                      style: AppTypography.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: statusBadge,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                order.lineDescription,
                style: AppTypography.bodyText,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    FormatterUtils.formatDate(order.createdAt),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textMuted,
                    ),
                  ),
                  Text(
                    FormatterUtils.formatVnd(
                      (order.finalTotalVnd ?? order.totalVnd).toDouble(),
                    ),
                    style: AppTypography.title.copyWith(
                      color: AppColors.primary,
                    ),
                  ),
                ],
              ),
              if (order.canCancelBooking) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onCancelBooking,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Hủy yêu cầu'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({required this.icon, required this.message, this.action});

  final IconData icon;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(
            message,
            style: AppTypography.bodyText.copyWith(color: AppColors.textMuted),
          ),
          if (action != null) ...[const SizedBox(height: 12), action!],
        ],
      ),
    );
  }
}
