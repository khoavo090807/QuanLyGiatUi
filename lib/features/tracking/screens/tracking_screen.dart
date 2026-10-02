import 'package:flutter/material.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/core/widgets/status_badge.dart';
import 'package:app_quanly_giaiui/features/order/data/order_repository.dart';

class TrackingScreen extends StatefulWidget {
  const TrackingScreen({
    this.orderId,
    this.bookingId,
    super.key,
  }) : assert(orderId != null || bookingId != null,
      'Either orderId or bookingId must be provided');

  final String? orderId;
  final String? bookingId;

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  final _repository = OrderRepository();
  late Future<LaundryOrderDetails> _detailsFuture;

  @override
  void initState() {
    super.initState();
    _detailsFuture = _loadDetails();
  }

  Future<LaundryOrderDetails> _loadDetails() {
    if (widget.orderId != null) {
      final id = int.tryParse(widget.orderId!);
      if (id == null) throw const FormatException('Mã đơn không hợp lệ.');
      return _repository.getOrderDetails(id);
    } else if (widget.bookingId != null) {
      final id = int.tryParse(widget.bookingId!);
      if (id == null) throw const FormatException('Mã yêu cầu không hợp lệ.');
      return _repository.getBookingDetails(id);
    }
    throw const FormatException('Mã đơn hoặc yêu cầu không hợp lệ.');
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} · '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.orderId != null
              ? 'Theo dõi đơn #${widget.orderId}'
              : 'Chi tiết yêu cầu #${widget.bookingId}',
        ),
      ),
      body: FutureBuilder<LaundryOrderDetails>(
        future: _detailsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.cloud_off_outlined, size: 44),
                    const SizedBox(height: 12),
                    const Text('Không tải được trạng thái đơn hàng.'),
                    TextButton(
                      onPressed: () => setState(() {
                        _detailsFuture = _loadDetails();
                      }),
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
              ),
            );
          }

          final details = snapshot.data!;
          final order = details.order;
          return RefreshIndicator(
            onRefresh: () async {
              final future = _loadDetails();
              setState(() {
                _detailsFuture = future;
              });
              await future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: AppColors.heroCardGradient,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      const Icon(
                        Icons.local_laundry_service_outlined,
                        size: 42,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        order.status,
                        style: AppTypography.heading2.copyWith(
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        order.orderNumber,
                        style: AppTypography.bodyText.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Text('Lịch sử trạng thái', style: AppTypography.heading3),
                const SizedBox(height: 16),
                if (details.events.isEmpty)
                  const Text('Chưa có cập nhật trạng thái.')
                else
                  ...details.events.asMap().entries.map((entry) {
                    final isLast = entry.key == details.events.length - 1;
                    final event = entry.value;
                    return _TimelineEvent(
                      title: event.status,
                      timestamp: _formatDateTime(event.occurredAt),
                      note: event.note,
                      isLast: isLast,
                    );
                  }),
                const SizedBox(height: 20),
                Text('Thông tin đơn hàng', style: AppTypography.heading3),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.divider),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      _DetailRow(
                        label: 'Dịch vụ',
                        value: order.lineDescription,
                      ),
                      _DetailRow(
                        label: 'Ngày tạo',
                        value: _formatDateTime(order.createdAt),
                      ),
                      _DetailRow(
                        label: 'Tạm tính',
                        value: '${order.totalVnd.toStringAsFixed(0)} đ',
                        valueColor: AppColors.primary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                StatusBadge(
                  text:
                      'Số tiền cuối cùng được cửa hàng xác nhận sau kiểm nhận.',
                  backgroundColor: AppColors.infoLight,
                  textColor: AppColors.info,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TimelineEvent extends StatelessWidget {
  const _TimelineEvent({
    required this.title,
    required this.timestamp,
    required this.isLast,
    this.note,
  });

  final String title;
  final String timestamp;
  final String? note;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              const Icon(
                Icons.check_circle,
                color: AppColors.primary,
                size: 22,
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    color: AppColors.primaryLight,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTypography.title),
                  const SizedBox(height: 3),
                  Text(
                    timestamp,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                  if (note != null && note!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(note!, style: AppTypography.bodySmall),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: AppTypography.bodyText.copyWith(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }
}
