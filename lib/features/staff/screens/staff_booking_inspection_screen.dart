import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/features/profile/data/address_suggestion_service.dart';
import 'package:app_quanly_giaiui/features/staff/data/staff_booking_repository.dart';

class StaffBookingInspectionScreen extends StatefulWidget {
  const StaffBookingInspectionScreen({required this.bookingId, super.key});

  final int bookingId;

  @override
  State<StaffBookingInspectionScreen> createState() =>
      _StaffBookingInspectionScreenState();
}

class _StaffBookingInspectionScreenState
    extends State<StaffBookingInspectionScreen> {
  final _repository = StaffBookingRepository();
  final _formKey = GlobalKey<FormState>();
  final _receiveAddress = TextEditingController();
  final _returnAddress = TextEditingController();
  final _note = TextEditingController();
  late Future<Map<String, dynamic>> _bookingFuture;
  Map<String, dynamic>? _booking;
  List<Map<String, dynamic>> _prices = const [];
  List<Map<String, dynamic>> _services = const [];
  List<Map<String, dynamic>> _categories = const [];
  List<Map<String, dynamic>> _garments = const [];
  List<_InspectionLine> _lines = [];
  String _receiveMethod = 'Tại nhà';
  String _returnMethod = 'Tại cửa hàng';
  String _appointmentDate = '';
  String _appointmentTime = '';
  Map<String, dynamic>? _estimate;
  bool _customerAgreed = false;
  bool _isEstimating = false;
  bool _isSaving = false;
  bool _isSubmitting = false;
  bool _draftSaved = false;
  bool _receiveAddressVerified = false;
  bool _returnAddressVerified = false;

  @override
  void initState() {
    super.initState();
    _bookingFuture = _loadBooking();
  }

  Future<Map<String, dynamic>> _loadBooking() async {
    final booking = await _repository.getBooking(widget.bookingId);
    final customer = booking['customer'] as Map<String, dynamic>? ?? {};
    final appointment = booking['appointment']?.toString() ?? '';
    final parts = appointment.split(' ');
    _booking = booking;
    _receiveMethod = booking['receive_method']?.toString() ?? 'Tại nhà';
    _returnMethod = booking['return_method']?.toString() ?? 'Tại cửa hàng';
    _receiveAddress.text = booking['receive_address']?.toString() ?? '';
    _returnAddress.text = booking['return_address']?.toString() ?? '';
    _receiveAddressVerified = _receiveAddress.text.trim().isNotEmpty;
    _returnAddressVerified = _returnAddress.text.trim().isNotEmpty;
    _note.text = booking['note']?.toString() ?? '';
    _appointmentDate =
        booking['appointment_date']?.toString() ??
        (parts.isNotEmpty ? parts.first : '');
    _appointmentTime = _validTime(
      booking['appointment_time']?.toString() ?? '',
    );
    _draftSaved = booking['inspection_draft_saved'] == true;
    if (_appointmentTime.isEmpty && parts.length > 1) {
      _appointmentTime = _validTime(parts.skip(1).join(' '));
    }

    final catalog = booking['catalog'] as Map<String, dynamic>? ?? {};
    _prices = _maps(catalog['prices'])
        .map(
          (row) => {
            ...row,
            'service_id': _asInt(row['service_id']),
            'garment_id': _asInt(row['garment_id']),
            'unit_id': _asInt(row['unit_id']),
            'unit_price': _asNum(row['unit_price']),
          },
        )
        .toList(growable: false);
    _services = _maps(catalog['services'])
        .map(
          (row) => {
            ...row,
            'id': _asInt(row['id']),
            'category_id': _asInt(row['category_id']),
          },
        )
        .toList(growable: false);
    _categories = _maps(
      catalog['categories'],
    ).map((row) => {...row, 'id': _asInt(row['id'])}).toList(growable: false);
    _garments = _maps(
      catalog['garments'],
    ).map((row) => {...row, 'id': _asInt(row['id'])}).toList(growable: false);
    _lines = _maps(booking['items']).map(_InspectionLine.fromJson).toList();
    if (_lines.isEmpty) {
      _lines = [_InspectionLine()];
    }
    if (customer.isEmpty) {
      throw const FormatException('Thiếu thông tin khách hàng.');
    }
    return booking;
  }

  List<Map<String, dynamic>> _maps(dynamic value) => value is List
      ? value
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList()
      : <Map<String, dynamic>>[];

  String _validTime(String value) {
    final match = RegExp(
      r'(?:^|[T\s])(\d{1,2}):(\d{2})(?::\d{2})?',
    ).firstMatch(value.trim());
    if (match == null) return '';
    final hour = int.tryParse(match.group(1)!);
    final minute = int.tryParse(match.group(2)!);
    if (hour == null || hour > 23 || minute == null || minute > 59) return '';
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _receiveAddress.dispose();
    _returnAddress.dispose();
    _note.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _payload({bool includeConsent = false}) {
    final items = _lines
        .map((line) {
          final price = line.selectedPrice(_prices);
          return <String, dynamic>{
            'DichVuID': line.serviceId,
            'LoaiDoGiatID': line.garmentId,
            'DonViTinhID': line.unitId,
            'SoLuong': price?['is_weight'] == true ? null : line.quantity,
            'KhoiLuong': price?['is_weight'] == true ? line.weight : null,
            'TinhTrangTruocKhiGiat': line.condition.text.trim(),
            'GhiChu': line.note.text.trim(),
          };
        })
        .toList(growable: false);
    final customer = _booking?['customer'] as Map<String, dynamic>? ?? {};
    return {
      'customer_id': customer['id'],
      'method': _receiveMethod,
      'address': _receiveMethod == 'Tại nhà'
          ? _receiveAddress.text.trim()
          : null,
      'return_method': _returnMethod,
      'return_address': _returnMethod == 'Tại nhà'
          ? _returnAddress.text.trim()
          : null,
      'scheduled_date': _appointmentDate,
      'scheduled_time': _appointmentTime,
      'notes': _note.text.trim(),
      'items': items,
      if (includeConsent) 'customer_agreed': _customerAgreed,
    };
  }

  Future<void> _calculateEstimate() async {
    if (!_formKey.currentState!.validate() || !_itemsAreComplete()) return;
    setState(() => _isEstimating = true);
    try {
      final estimate = await _repository.estimate(widget.bookingId, _payload());
      if (mounted) {
        setState(() {
          _estimate = estimate;
          _customerAgreed = false;
        });
      }
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _isEstimating = false);
    }
  }

  Future<void> _confirm() async {
    if (!_formKey.currentState!.validate() || !_itemsAreComplete()) return;
    if (_estimate == null) {
      _showError(
        'Hãy tính giá dự kiến sau khi kiểm kê trước khi xác nhận với khách.',
      );
      return;
    }
    if (!_draftSaved) {
      _showError('Hãy lưu Booking để khách xem trước khi xác nhận tạo đơn.');
      return;
    }
    if (!_customerAgreed) {
      _showError('Hãy xác nhận khách đã đồng ý với đồ thực tế và giá dự kiến.');
      return;
    }
    setState(() => _isSubmitting = true);
    try {
      final result = await _repository.confirm(
        widget.bookingId,
        _payload(includeConsent: true),
      );
      if (!mounted) return;
      final code = result['order_code']?.toString() ?? 'đã tạo';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Đã tạo đơn $code.')));
      Navigator.of(context).pop(true);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _saveDraft() async {
    if (!_formKey.currentState!.validate() || !_itemsAreComplete()) return;
    if (_estimate == null) {
      _showError('Hãy tính giá dự kiến trước khi lưu Booking cho khách xem.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _repository.saveDraft(widget.bookingId, _payload());
      if (!mounted) return;
      setState(() {
        _draftSaved = true;
        _customerAgreed = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Đã lưu cập nhật. Khách có thể xem Booking trên ứng dụng.',
          ),
        ),
      );
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  bool _itemsAreComplete() =>
      _lines.isNotEmpty &&
      _lines.every((line) {
        final price = line.selectedPrice(_prices);
        if (price == null || line.condition.text.trim().isEmpty) return false;
        if (price['is_weight'] == true) {
          return line.weight != null && line.weight! > 0;
        }
        return line.quantity != null && line.quantity! >= 1;
      });

  void _invalidateEstimate() {
    _estimate = null;
    _customerAgreed = false;
    _draftSaved = false;
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(_errorMessage(error))));
  }

  String _errorMessage(Object error) {
    final message = error is DioException
        ? (error.response?.data is Map
                  ? (error.response!.data as Map)['message']?.toString()
                  : null) ??
              'Không thể kết nối máy chủ. Kiểm tra STAFF_API_BASE_URL rồi thử lại.'
        : error.toString();
    return message;
  }

  List<Map<String, dynamic>> _serviceOptions(int? categoryId) => _services
      .where((service) => service['category_id'] == categoryId)
      .toList();

  List<Map<String, dynamic>> _priceOptions(_InspectionLine line) => _prices
      .where(
        (price) =>
            price['service_id'] == line.serviceId &&
            price['garment_id'] == line.garmentId,
      )
      .toList();

  String _priceLabel(Map<String, dynamic> price) {
    final unit = price['unit_symbol']?.toString().trim().isNotEmpty == true
        ? price['unit_symbol']
        : price['unit_name'];
    return '$unit · ${_money(price['unit_price'])}';
  }

  String _money(dynamic value) => NumberFormat.currency(
    locale: 'vi_VN',
    symbol: '₫',
    decimalDigits: 0,
  ).format(_asNum(value) ?? 0);

  Future<void> _pickDate() async {
    final initial = DateTime.tryParse(_appointmentDate) ?? DateTime.now();
    final result = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (result != null) {
      setState(() {
        _appointmentDate = DateFormat('yyyy-MM-dd').format(result);
        _invalidateEstimate();
      });
    }
  }

  Future<void> _pickTime() async {
    final parts = _appointmentTime.split(':');
    final result = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.tryParse(parts.firstOrNull ?? '') ?? 9,
        minute: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
      ),
    );
    if (result != null) {
      setState(() {
        _appointmentTime =
            '${result.hour.toString().padLeft(2, '0')}:${result.minute.toString().padLeft(2, '0')}';
        _invalidateEstimate();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      title: const Text('Kiểm kê & báo giá'),
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _bookingFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || _booking == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snapshot.hasError
                        ? _errorMessage(snapshot.error!)
                        : 'Không tải được Booking.',
                  ),
                  TextButton(
                    onPressed: () => setState(() {
                      _bookingFuture = _loadBooking();
                    }),
                    child: const Text('Thử lại'),
                  ),
                ],
              ),
            ),
          );
        }
        return Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
            children: [
              _customerCard(_booking!),
              const SizedBox(height: 18),
              _sectionTitle(
                'LỊCH NHẬN VÀ TRẢ ĐỒ',
                Icons.local_shipping_outlined,
              ),
              const SizedBox(height: 8),
              _bookingDetailsCard(),
              const SizedBox(height: 18),
              _sectionTitle('ĐỒ THỰC TẾ', Icons.dry_cleaning_outlined),
              const SizedBox(height: 8),
              ..._lines.asMap().entries.map(
                (entry) => _lineCard(entry.key, entry.value),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _lines.add(_InspectionLine());
                  _invalidateEstimate();
                }),
                icon: const Icon(Icons.add),
                label: const Text('Thêm món đồ'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _sectionTitle('GHI CHÚ VÀ GIÁ', Icons.receipt_long_outlined),
              const SizedBox(height: 8),
              TextFormField(
                controller: _note,
                maxLength: 500,
                maxLines: 2,
                onChanged: (_) => setState(_invalidateEstimate),
                decoration: const InputDecoration(
                  labelText: 'Ghi chú Booking',
                  hintText: 'Thông tin thêm khách cần biết',
                  alignLabelWithHint: true,
                  filled: true,
                  fillColor: AppColors.surface,
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _isEstimating ? null : _calculateEstimate,
                icon: _isEstimating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.calculate_outlined),
                label: const Text('Tính giá dự kiến'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              if (_estimate != null) _estimateCard(_estimate!),
              const SizedBox(height: 12),
              _reviewStatusCard(),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: (_isSaving || _isEstimating || _estimate == null)
                    ? null
                    : _saveDraft,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(
                  _draftSaved
                      ? 'Lưu lại cập nhật Booking'
                      : 'Lưu Booking cho khách xem',
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: AppColors.secondary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                value: _customerAgreed,
                onChanged: !_draftSaved || _isSubmitting || _isSaving
                    ? null
                    : (value) =>
                          setState(() => _customerAgreed = value ?? false),
                title: const Text(
                  'Khách đã xem Booking cập nhật và đồng ý bằng lời',
                ),
                subtitle: Text(
                  _draftSaved
                      ? 'Chỉ đánh dấu sau khi đã hỏi khách trực tiếp.'
                      : 'Lưu Booking trước để khách xem thông tin mới.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                tileColor: AppColors.surface,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _isSubmitting || !_draftSaved || !_customerAgreed
                    ? null
                    : _confirm,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: const Text('Khách đồng ý — xác nhận & tạo đơn'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );

  Widget _customerCard(Map<String, dynamic> booking) {
    final customer = booking['customer'] as Map<String, dynamic>? ?? {};
    return Card(
      elevation: 0,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.divider),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const CircleAvatar(
              backgroundColor: AppColors.primaryLight,
              foregroundColor: AppColors.primaryDark,
              child: Icon(Icons.person_outline),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    customer['name']?.toString() ?? 'Khách hàng',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Booking ${booking['code'] ?? ''}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.phone_outlined,
                        size: 17,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 6),
                      SelectableText(
                        customer['phone']?.toString() ??
                            'Chưa có số điện thoại',
                      ),
                    ],
                  ),
                  if (booking['assigned_employee'] != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Nhân viên phụ trách: ${booking['assigned_employee']}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title, IconData icon) => Row(
    children: [
      Icon(icon, size: 19, color: AppColors.primary),
      const SizedBox(width: 8),
      Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: .5,
          color: AppColors.textSecondary,
        ),
      ),
    ],
  );

  Widget _reviewStatusCard() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _draftSaved ? AppColors.successLight : AppColors.primaryExtraLight,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: _draftSaved
            ? AppColors.success.withValues(alpha: .35)
            : AppColors.primaryLight,
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          _draftSaved ? Icons.cloud_done_outlined : Icons.info_outline,
          color: _draftSaved ? AppColors.secondary : AppColors.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _draftSaved
                ? 'Booking đã lưu. Khách có thể xem thông tin mới trên điện thoại; chỉ tạo đơn sau khi khách đồng ý trực tiếp.'
                : 'Kiểm tra đồ, tính giá rồi lưu để khách xem Booking cập nhật trước khi xác nhận.',
            style: const TextStyle(height: 1.35),
          ),
        ),
      ],
    ),
  );

  Widget _bookingDetailsCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Lịch nhận và trả đồ',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _receiveMethod,
            decoration: const InputDecoration(labelText: 'Hình thức nhận'),
            items: _methods
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: (value) => setState(() {
              _receiveMethod = value ?? _receiveMethod;
              _invalidateEstimate();
            }),
          ),
          const SizedBox(height: 12),
          if (_receiveMethod == 'Tại nhà')
            _StaffAddressInput(
              key: const ValueKey('receive-address'),
              controller: _receiveAddress,
              label: 'Địa chỉ nhận đồ',
              isVerified: _receiveAddressVerified,
              onChanged: (_) => setState(() {
                _receiveAddressVerified = false;
                _invalidateEstimate();
              }),
              onSelect: (_) => setState(() {
                _receiveAddressVerified = true;
                _invalidateEstimate();
              }),
            ),
          if (_receiveMethod == 'Tại nhà') const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _returnMethod,
            decoration: const InputDecoration(labelText: 'Hình thức trả'),
            items: _methods
                .map(
                  (value) => DropdownMenuItem(value: value, child: Text(value)),
                )
                .toList(),
            onChanged: (value) => setState(() {
              _returnMethod = value ?? _returnMethod;
              _invalidateEstimate();
            }),
          ),
          const SizedBox(height: 12),
          if (_returnMethod == 'Tại nhà')
            _StaffAddressInput(
              key: const ValueKey('return-address'),
              controller: _returnAddress,
              label: 'Địa chỉ trả đồ',
              isVerified: _returnAddressVerified,
              onChanged: (_) => setState(() {
                _returnAddressVerified = false;
                _invalidateEstimate();
              }),
              onSelect: (_) => setState(() {
                _returnAddressVerified = true;
                _invalidateEstimate();
              }),
            ),
          if (_returnMethod == 'Tại nhà') const SizedBox(height: 12),
          const SizedBox(height: 6),
          _appointmentPicker(
            label: 'Ngày hẹn',
            value: _appointmentDate.isEmpty
                ? 'Chưa chọn ngày'
                : _appointmentDate,
            icon: Icons.calendar_month_outlined,
            onTap: _pickDate,
          ),
          const SizedBox(height: 8),
          _appointmentPicker(
            label: 'Giờ hẹn',
            value: _appointmentTime.isEmpty
                ? 'Chưa chọn giờ'
                : _appointmentTime,
            icon: Icons.schedule,
            onTap: _pickTime,
          ),
          Text('Phí nhận đã lưu: ${_money(_booking?['pickup_fee'])}'),
          Text('Phí trả đã lưu: ${_money(_booking?['return_fee'])}'),
        ],
      ),
    ),
  );

  Widget _appointmentPicker({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: AppColors.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                style: const TextStyle(color: AppColors.textPrimary),
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  TextSpan(text: value),
                ],
              ),
              softWrap: true,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _lineCard(int index, _InspectionLine line) {
    final priceOptions = _priceOptions(line);
    final selectedPrice = line.selectedPrice(_prices);
    final categoryId =
        line.categoryId ??
        _services
            .where((service) => service['id'] == line.serviceId)
            .map((service) => _asInt(service['category_id']))
            .firstOrNull;
    final serviceOptions = _serviceOptions(categoryId);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Mặt hàng ${index + 1}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                if (_lines.length > 1)
                  IconButton(
                    onPressed: () => setState(() {
                      _lines.removeAt(index).dispose();
                      _invalidateEstimate();
                    }),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Xóa mặt hàng',
                  ),
              ],
            ),
            DropdownButtonFormField<int>(
              key: ValueKey('category-$index-$categoryId'),
              initialValue: categoryId,
              decoration: const InputDecoration(labelText: 'Danh mục dịch vụ'),
              items: _categories
                  .map(
                    (row) => DropdownMenuItem<int>(
                      value: _asInt(row['id'])!,
                      child: Text(row['name'].toString()),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() {
                line.categoryId = value;
                line.serviceId = null;
                line.garmentId = null;
                line.unitId = null;
                _invalidateEstimate();
              }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey('service-$index-$categoryId-${line.serviceId}'),
              initialValue:
                  serviceOptions.any((row) => row['id'] == line.serviceId)
                  ? line.serviceId
                  : null,
              decoration: const InputDecoration(labelText: 'Dịch vụ'),
              items: serviceOptions
                  .map(
                    (row) => DropdownMenuItem<int>(
                      value: _asInt(row['id'])!,
                      child: Text(row['name'].toString()),
                    ),
                  )
                  .toList(),
              onChanged: categoryId == null
                  ? null
                  : (value) => setState(() {
                      line.categoryId = categoryId;
                      line.serviceId = value;
                      line.garmentId = null;
                      line.unitId = null;
                      _invalidateEstimate();
                    }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey(
                'garment-$index-${line.serviceId}-${line.garmentId}',
              ),
              initialValue: _garments.any((row) => row['id'] == line.garmentId)
                  ? line.garmentId
                  : null,
              decoration: const InputDecoration(labelText: 'Loại đồ giặt'),
              items: line.serviceId == null
                  ? const []
                  : _garments
                        .map(
                          (row) => DropdownMenuItem<int>(
                            value: _asInt(row['id'])!,
                            child: Text(row['name'].toString()),
                          ),
                        )
                        .toList(),
              onChanged: line.serviceId == null
                  ? null
                  : (value) => setState(() {
                      line.garmentId = value;
                      line.unitId = null;
                      _invalidateEstimate();
                    }),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              key: ValueKey(
                'unit-$index-${line.serviceId}-${line.garmentId}-${line.unitId}',
              ),
              initialValue:
                  priceOptions.any((row) => row['unit_id'] == line.unitId)
                  ? line.unitId
                  : null,
              decoration: const InputDecoration(labelText: 'Đơn vị tính'),
              items: priceOptions
                  .map(
                    (row) => DropdownMenuItem<int>(
                      value: _asInt(row['unit_id'])!,
                      child: Text(_priceLabel(row)),
                    ),
                  )
                  .toList(),
              onChanged: priceOptions.isEmpty
                  ? null
                  : (value) => setState(() {
                      line.unitId = value;
                      line.quantity = null;
                      line.weight = null;
                      _invalidateEstimate();
                    }),
            ),
            const SizedBox(height: 12),
            if (selectedPrice != null && selectedPrice['is_weight'] == true)
              TextFormField(
                key: ValueKey('weight-$index-${line.unitId}'),
                initialValue: line.weight?.toString() ?? '',
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Khối lượng thực tế (kg)',
                ),
                onChanged: (value) => setState(() {
                  line.weight = num.tryParse(value);
                  _invalidateEstimate();
                }),
                validator: (value) =>
                    selectedPrice['is_weight'] == true &&
                        (num.tryParse(value ?? '') ?? 0) <= 0
                    ? 'Nhập khối lượng lớn hơn 0.'
                    : null,
              )
            else if (selectedPrice != null)
              TextFormField(
                key: ValueKey('quantity-$index-${line.unitId}'),
                initialValue: line.quantity?.toString() ?? '',
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Số lượng thực tế',
                ),
                onChanged: (value) => setState(() {
                  line.quantity = int.tryParse(value);
                  _invalidateEstimate();
                }),
                validator: (value) =>
                    selectedPrice['is_weight'] != true &&
                        (int.tryParse(value ?? '') ?? 0) < 1
                    ? 'Nhập số lượng từ 1 trở lên.'
                    : null,
              ),
            if (selectedPrice != null) const SizedBox(height: 12),
            TextFormField(
              controller: line.condition,
              maxLength: 320,
              onChanged: (_) => setState(_invalidateEstimate),
              decoration: const InputDecoration(
                labelText: 'Tình trạng trước khi giặt *',
                hintText: 'Ví dụ: ố màu, rách, bung chỉ',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Ghi nhận tình trạng từng mặt hàng.'
                  : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: line.note,
              maxLength: 160,
              onChanged: (_) => setState(_invalidateEstimate),
              decoration: const InputDecoration(
                labelText: 'Ghi chú dòng (không bắt buộc)',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _estimateCard(Map<String, dynamic> estimate) {
    final total = estimate['ThanhTien'] ?? estimate['total_amount'];
    final subtotal = estimate['TongTien'] ?? estimate['subtotal'];
    final delivery = estimate['PhiGiaoHang'] ?? estimate['delivery_fee'];
    final promotionDiscount = estimate['TienGiamKhuyenMai'] ?? 0;
    final pointsDiscount = estimate['TienGiamDoDiem'] ?? 0;
    return Card(
      color: AppColors.primaryLight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Tổng dự kiến: ${_money(total)}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text('Tiền dịch vụ: ${_money(subtotal)}'),
            Text('Phí giao nhận: ${_money(delivery)}'),
            Text('Giảm mã: ${_money(promotionDiscount)}'),
            Text('Giảm điểm: ${_money(pointsDiscount)}'),
            if (estimate['promotion_warning'] != null)
              Text(
                estimate['promotion_warning'].toString(),
                style: const TextStyle(color: AppColors.error),
              ),
            const Text(
              'Giá cuối cùng sẽ được máy chủ kiểm tra lại khi tạo đơn.',
            ),
          ],
        ),
      ),
    );
  }

  static const _methods = ['Tại cửa hàng', 'Tại nhà'];
}

class _StaffAddressInput extends StatefulWidget {
  const _StaffAddressInput({
    required this.controller,
    required this.label,
    required this.isVerified,
    required this.onChanged,
    required this.onSelect,
    super.key,
  });

  final TextEditingController controller;
  final String label;
  final bool isVerified;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSelect;

  @override
  State<_StaffAddressInput> createState() => _StaffAddressInputState();
}

class _StaffAddressInputState extends State<_StaffAddressInput> {
  final _suggestionService = AddressSuggestionService();
  Timer? _debounce;
  List<String> _suggestions = const [];
  bool _isSearching = false;
  int _searchGeneration = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _search(String value) {
    _debounce?.cancel();
    final query = value.trim();
    final generation = ++_searchGeneration;
    if (query.length < 5) {
      setState(() {
        _suggestions = const [];
        _isSearching = false;
      });
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 700), () async {
      try {
        final suggestions = await _suggestionService.suggest(query);
        if (!mounted || generation != _searchGeneration) return;
        setState(() {
          _suggestions = suggestions;
          _isSearching = false;
        });
      } catch (_) {
        if (!mounted || generation != _searchGeneration) return;
        setState(() {
          _suggestions = const [];
          _isSearching = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextFormField(
        controller: widget.controller,
        maxLines: 2,
        maxLength: 255,
        textInputAction: TextInputAction.done,
        onChanged: (value) {
          widget.onChanged(value);
          _search(value);
        },
        validator: (value) {
          if (value?.trim().isNotEmpty != true) return 'Nhập ${widget.label}.';
          return widget.isVerified
              ? null
              : 'Chọn địa chỉ thật từ danh sách gợi ý.';
        },
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: 'Nhập địa chỉ để xem gợi ý',
          prefixIcon: const Icon(Icons.location_on_outlined),
        ),
      ),
      if (_isSearching)
        const LinearProgressIndicator(minHeight: 2)
      else if (_suggestions.isNotEmpty)
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: _suggestions
                .map(
                  (suggestion) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(suggestion),
                    onTap: () {
                      _searchGeneration++;
                      _debounce?.cancel();
                      widget.controller
                        ..text = suggestion
                        ..selection = TextSelection.collapsed(
                          offset: suggestion.length,
                        );
                      setState(() => _suggestions = const []);
                      widget.onSelect(suggestion);
                    },
                  ),
                )
                .toList(growable: false),
          ),
        )
      else if (widget.controller.text.trim().length >= 5 && !widget.isVerified)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Chọn địa chỉ gợi ý để xác nhận địa chỉ hợp lệ.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ],
  );
}

class _InspectionLine {
  _InspectionLine({
    this.serviceId,
    this.garmentId,
    this.unitId,
    this.quantity,
    this.weight,
  });

  factory _InspectionLine.fromJson(Map<String, dynamic> json) =>
      _InspectionLine(
          serviceId: _asInt(json['service_id']),
          garmentId: _asInt(json['garment_id']),
          unitId: _asInt(json['unit_id']),
          quantity: _asInt(json['quantity']),
          weight: _asNum(json['weight']),
        )
        ..condition.text = json['condition']?.toString() ?? ''
        ..note.text = json['note']?.toString() ?? '';

  int? serviceId;
  int? categoryId;
  int? garmentId;
  int? unitId;
  int? quantity;
  num? weight;
  final condition = TextEditingController();
  final note = TextEditingController();

  Map<String, dynamic>? selectedPrice(List<Map<String, dynamic>> prices) =>
      prices
          .where(
            (row) =>
                row['service_id'] == serviceId &&
                row['garment_id'] == garmentId &&
                row['unit_id'] == unitId,
          )
          .firstOrNull;

  void dispose() {
    condition.dispose();
    note.dispose();
  }
}

int? _asInt(dynamic value) {
  final parsed = value is num
      ? value
      : num.tryParse(value?.toString().trim() ?? '');
  return parsed != null && parsed.isFinite && parsed == parsed.roundToDouble()
      ? parsed.toInt()
      : null;
}

num? _asNum(dynamic value) {
  if (value is num) return value;
  return num.tryParse(value?.toString().trim() ?? '');
}
