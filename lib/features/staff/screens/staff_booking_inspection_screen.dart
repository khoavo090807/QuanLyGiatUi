import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
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
  final _addressSuggestions = AddressSuggestionService();
  late Future<Map<String, dynamic>> _bookingFuture;
  Map<String, dynamic>? _booking;
  List<Map<String, dynamic>> _prices = const [];
  List<Map<String, dynamic>> _services = const [];
  List<Map<String, dynamic>> _categories = const [];
  List<Map<String, dynamic>> _garments = const [];
  List<Map<String, dynamic>> _vouchers = const [];
  List<_InspectionLine> _lines = [];
  int? _selectedPromotionId;
  int _availablePoints = 0;
  bool _usePoints = false;
  String _receiveMethod = 'Tại nhà';
  String _returnMethod = 'Tại cửa hàng';
  String _appointmentDate = '';
  String _appointmentTime = '';
  Map<String, dynamic>? _estimate;
  bool _customerAgreed = false;
  bool _isEstimating = false;
  bool _isSaving = false;
  bool _isSubmitting = false;
  bool _isCancelling = false;
  bool _draftSaved = false;
  bool _returnAddressVerified = false;
  bool _isSuggestingAddress = false;
  Timer? _addressDebounce;
  List<String> _returnAddressOptions = const [];
  int _addressSearchGeneration = 0;

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
    _returnAddressVerified = _returnAddress.text.trim().isNotEmpty;
    _note.text = booking['note']?.toString() ?? '';
    _appointmentDate =
        booking['appointment_date']?.toString() ??
        (parts.isNotEmpty ? parts.first : '');
    _appointmentTime = _validTime(
      booking['appointment_time']?.toString() ?? '',
    );
    _draftSaved = booking['inspection_draft_saved'] == true;
    _availablePoints = _asInt(booking['available_points']) ?? 0;
    _selectedPromotionId = _asInt(booking['selected_promotion_id']);
    _usePoints = (_asInt(booking['selected_points']) ?? 0) > 0;
    _vouchers = _maps(booking['available_vouchers']);
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
    _addressDebounce?.cancel();
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
      'promotion_id': _selectedPromotionId,
      'points_used': _usePoints ? _availablePoints : 0,
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

  Future<void> _refuseQuote() async {
    if (_isSubmitting || _isSaving || _isEstimating || _isCancelling) return;
    final formKey = GlobalKey<FormState>();
    var rejectionReason = '';
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Xác nhận khách từ chối báo giá'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Booking sẽ bị hủy, không tạo đơn và không thu phí nhận đồ. '
              'Dữ liệu kiểm kê cùng lý do sẽ được lưu để tra cứu.',
            ),
            const SizedBox(height: 16),
            Form(
              key: formKey,
              child: TextFormField(
                autofocus: true,
                minLines: 3,
                maxLines: 5,
                maxLength: 500,
                onChanged: (value) => rejectionReason = value,
                decoration: const InputDecoration(
                  labelText: 'Lý do khách từ chối *',
                  alignLabelWithHint: true,
                  errorMaxLines: 2,
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Vui lòng nhập lý do khách từ chối.'
                    : null,
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        buttonPadding: EdgeInsets.zero,
        actions: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text(
                    'Quay lại kiểm kê',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    minimumSize: const Size.fromHeight(52),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  onPressed: () {
                    if (formKey.currentState?.validate() != true) return;
                    Navigator.pop(dialogContext, rejectionReason.trim());
                  },
                  child: const Text(
                    'Hủy Booking và lưu lý do',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (reason == null || !mounted) return;

    setState(() => _isCancelling = true);
    try {
      await _repository.refuseQuote(widget.bookingId, {
        ..._payload(),
        'rejection_reason': reason,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã hủy Booking và lưu lý do khách từ chối.'),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      _showError(error);
    } finally {
      if (mounted) setState(() => _isCancelling = false);
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

  void _searchReturnAddress(String value) {
    _addressDebounce?.cancel();
    final query = value.trim();
    final generation = ++_addressSearchGeneration;
    if (query.length < 5) {
      setState(() {
        _returnAddressOptions = const [];
        _isSuggestingAddress = false;
      });
      return;
    }
    setState(() => _isSuggestingAddress = true);
    _addressDebounce = Timer(const Duration(milliseconds: 700), () async {
      try {
        final suggestions = await _addressSuggestions.suggest(query);
        if (!mounted || generation != _addressSearchGeneration) return;
        setState(() {
          _returnAddressOptions = suggestions;
          _isSuggestingAddress = false;
        });
      } catch (_) {
        if (!mounted || generation != _addressSearchGeneration) return;
        setState(() {
          _returnAddressOptions = const [];
          _isSuggestingAddress = false;
        });
      }
    });
  }

  void _selectReturnAddress(String address) {
    _addressSearchGeneration++;
    _addressDebounce?.cancel();
    _returnAddress
      ..text = address
      ..selection = TextSelection.collapsed(offset: address.length);
    setState(() {
      _returnAddressVerified = true;
      _returnAddressOptions = const [];
      _invalidateEstimate();
    });
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
                'THÔNG TIN NHẬN VÀ GIAO ĐỒ',
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
              _sectionTitle('ƯU ĐÃI CỦA KHÁCH', Icons.local_offer_outlined),
              const SizedBox(height: 8),
              _rewardChoices(),
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
              if (_estimate != null) _estimateCard(_estimate!),
              const SizedBox(height: 12),
              _reviewStatusCard(),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: (_isSaving || _isEstimating)
                    ? null
                    : _estimate == null
                    ? _calculateEstimate
                    : _saveDraft,
                icon: _isSaving || _isEstimating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        _estimate == null
                            ? Icons.calculate_outlined
                            : Icons.save_outlined,
                      ),
                label: Text(
                  _estimate == null
                      ? 'Tính giá để lưu Booking'
                      : _draftSaved
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
                  'Nhân viên xác nhận khách đã đồng ý bằng lời',
                ),
                subtitle: Text(
                  _draftSaved
                      ? 'Hãy báo kết quả kiểm kê và tổng tiền rồi hỏi khách trực tiếp; khách không cần thao tác trên ứng dụng.'
                      : 'Lưu thông tin kiểm kê và tính giá trước khi báo khách trực tiếp.',
                ),
                controlAffinity: ListTileControlAffinity.leading,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                tileColor: AppColors.surface,
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed:
                    _isCancelling || _isSaving || _isEstimating || _isSubmitting
                    ? null
                    : _refuseQuote,
                icon: _isCancelling
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cancel_outlined),
                label: const Text('Khách từ chối — Hủy Booking'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
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
            'Lịch nhận và giao đồ',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _infoLine(
            Icons.storefront_outlined,
            'Hình thức nhận đồ',
            _receiveMethod,
          ),
          if (_receiveMethod == 'Tại nhà')
            _infoLine(
              Icons.location_on_outlined,
              'Địa chỉ nhận đồ',
              _receiveAddress.text,
            ),
          _infoLine(
            Icons.calendar_month_outlined,
            'Ngày hẹn',
            _appointmentDate.isEmpty ? 'Chưa chọn ngày' : _appointmentDate,
          ),
          _infoLine(
            Icons.schedule,
            'Giờ hẹn',
            _appointmentTime.isEmpty ? 'Chưa chọn giờ' : _appointmentTime,
          ),
          const Divider(height: 24),
          DropdownButtonFormField<String>(
            initialValue: _returnMethod,
            decoration: const InputDecoration(labelText: 'Hình thức giao đồ'),
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
          if (_returnMethod == 'Tại nhà') ...[
            const SizedBox(height: 12),
            _deliveryAddressField(),
          ],
          _infoLine(
            Icons.payments_outlined,
            'Phí nhận đã lưu',
            _money(_booking?['pickup_fee']),
          ),
          _infoLine(
            Icons.payments_outlined,
            'Phí giao đã lưu',
            _money(_booking?['return_fee']),
          ),
        ],
      ),
    ),
  );

  Widget _infoLine(IconData icon, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 2),
              SelectableText(
                value,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _deliveryAddressField() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      TextFormField(
        controller: _returnAddress,
        maxLines: 2,
        maxLength: 255,
        textInputAction: TextInputAction.done,
        onChanged: (value) {
          setState(() {
            _returnAddressVerified = false;
            _invalidateEstimate();
          });
          _searchReturnAddress(value);
        },
        validator: (value) {
          if (_returnMethod != 'Tại nhà') return null;
          if (value?.trim().isNotEmpty != true) {
            return 'Nhập địa chỉ giao đồ.';
          }
          return _returnAddressVerified
              ? null
              : 'Chọn địa chỉ giao đồ từ danh sách gợi ý.';
        },
        decoration: const InputDecoration(
          labelText: 'Địa chỉ giao đồ',
          hintText: 'Nhập địa chỉ để xem gợi ý',
          prefixIcon: Icon(Icons.location_on_outlined),
        ),
      ),
      if (_isSuggestingAddress)
        const LinearProgressIndicator(minHeight: 2)
      else if (_returnAddressOptions.isNotEmpty)
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: _returnAddressOptions
                .map(
                  (address) => ListTile(
                    dense: true,
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(address),
                    onTap: () => _selectReturnAddress(address),
                  ),
                )
                .toList(growable: false),
          ),
        )
      else if (_returnAddress.text.trim().length >= 5 &&
          !_returnAddressVerified)
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text(
            'Chọn địa chỉ đề xuất để xác nhận địa chỉ giao đồ.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
        ),
      const SizedBox(height: 12),
    ],
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
    final garmentOptions = _garments
        .where(
          (garment) => _prices.any(
            (price) =>
                price['service_id'] == line.serviceId &&
                price['garment_id'] == garment['id'],
          ),
        )
        .toList();
    final selectedGarmentHasPrice = garmentOptions.any(
      (garment) => garment['id'] == line.garmentId,
    );
    final selectedGarment = _garments
        .where((garment) => garment['id'] == line.garmentId)
        .firstOrNull;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                    icon: const Icon(
                      Icons.delete_outline,
                      color: AppColors.error,
                    ),
                    tooltip: 'Xóa mặt hàng',
                  ),
              ],
            ),
            const SizedBox(height: 12),
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
              initialValue: selectedGarmentHasPrice ? line.garmentId : null,
              decoration: const InputDecoration(labelText: 'Loại đồ giặt'),
              items: garmentOptions
                  .map(
                    (row) => DropdownMenuItem<int>(
                      value: _asInt(row['id'])!,
                      child: Text(row['name'].toString()),
                    ),
                  )
                  .toList(),
              onChanged: line.serviceId == null || garmentOptions.isEmpty
                  ? null
                  : (value) => setState(() {
                      line.garmentId = value;
                      line.unitId = null;
                      _invalidateEstimate();
                    }),
            ),
            if (line.serviceId != null &&
                (garmentOptions.isEmpty ||
                    (line.garmentId != null && !selectedGarmentHasPrice)))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  garmentOptions.isEmpty
                      ? 'Dịch vụ này chưa có loại đồ nào trong bảng giá.'
                      : '${selectedGarment?['name'] ?? 'Loại đồ đã chọn'} chưa có giá cho dịch vụ này. Hãy chọn loại đồ được hỗ trợ.',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 12,
                  ),
                ),
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
    final subtotal = estimate['TongTien'] ?? estimate['subtotal'];
    final promotionDiscount = estimate['TienGiamKhuyenMai'] ?? 0;
    final pointsDiscount = estimate['TienGiamDoDiem'] ?? 0;
    final totalDiscount =
        (_asNum(promotionDiscount) ?? 0) + (_asNum(pointsDiscount) ?? 0);
    final items = _maps(estimate['items']);
    final pickupFee = estimate['PhiNhanDo'] ?? _booking?['pickup_fee'];
    final returnFee = estimate['PhiGiaoDo'] ?? _booking?['return_fee'];
    final pickupDistance =
        estimate['pickup_distance_meters'] ??
        _booking?['pickup_distance_meters'];
    final returnDistance =
        estimate['return_distance_meters'] ??
        _booking?['return_distance_meters'];
    final paymentMethod =
        _booking?['payment_method']?.toString() ?? 'Chưa xác định';
    return Card(
      color: AppColors.surface,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dịch vụ (${items.length} mục)',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            ...items.map((item) {
              final service = item['service_name']?.toString() ?? 'Dịch vụ';
              final garment = item['garment_name']?.toString();
              final amount = item['amount']?.toString() ?? '';
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            garment == null || garment.isEmpty
                                ? service
                                : '$service · $garment',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(_money(item['subtotal'])),
                      ],
                    ),
                    if (amount.isNotEmpty)
                      Text(
                        '$amount × ${_money(item['unit_price'])}',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                        ),
                      ),
                  ],
                ),
              );
            }),
            const Divider(),
            Text('Thanh toán', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _estimateRow('Hình thức', paymentMethod),
            const SizedBox(height: 12),
            Text('Tạm tính', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _estimateRow('Tổng tiền đơn hàng theo bảng giá', _money(subtotal)),
            _estimateRow(
              'Phí nhận đồ${_distanceLabel(pickupDistance)}',
              _money(pickupFee),
            ),
            _estimateRow(
              'Phí giao đồ${_distanceLabel(returnDistance)}',
              _money(returnFee),
            ),
            _estimateRow(
              'Giảm từ mã khuyến mãi',
              '-${_money(promotionDiscount)}',
            ),
            _estimateRow('Giảm từ điểm', '-${_money(pointsDiscount)}'),
            _estimateRow('Tổng tiền được giảm', '-${_money(totalDiscount)}'),
            _estimateRow(
              'Tổng tiền thanh toán',
              _money(estimate['ThanhTien'] ?? estimate['total_amount']),
              emphasize: true,
            ),
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

  Widget _estimateRow(String label, String value, {bool emphasize = false}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: emphasize
                      ? AppColors.primary
                      : AppColors.textSecondary,
                  fontWeight: emphasize ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              value,
              style: TextStyle(
                color: emphasize ? AppColors.primary : AppColors.textPrimary,
                fontWeight: emphasize ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      );

  String _distanceLabel(dynamic meters) {
    final distance = _asNum(meters);
    if (distance == null || distance <= 0) return '';
    final km = distance / 1000;
    final text = km == km.roundToDouble()
        ? km.toStringAsFixed(0)
        : km.toStringAsFixed(1);
    return ' · $text km';
  }

  num get _inspectionSubtotal => _lines.fold<num>(0, (total, line) {
    final price = line.selectedPrice(_prices);
    if (price == null) return total;
    final quantity = price['is_weight'] == true ? line.weight : line.quantity;
    if (quantity == null || quantity <= 0) return total;
    return total + quantity * (_asNum(price['unit_price']) ?? 0);
  });

  Map<String, dynamic>? get _selectedEligibleVoucher => _vouchers
      .where(
        (voucher) =>
            _asInt(voucher['id']) == _selectedPromotionId &&
            _isVoucherEligible(voucher),
      )
      .firstOrNull;

  bool _isVoucherEligible(Map<String, dynamic> voucher) =>
      _asNum(voucher['minimum']) == null ||
      _inspectionSubtotal >= _asNum(voucher['minimum'])!;

  num _voucherDiscount(Map<String, dynamic> voucher) {
    if (!_isVoucherEligible(voucher)) return 0;
    final subtotal = _inspectionSubtotal;
    final value = _asNum(voucher['value']) ?? 0;
    final discount = voucher['type'] == 'Phần trăm'
        ? subtotal * value / 100
        : value;
    return discount
        .clamp(0, _asNum(voucher['maximum']) ?? discount)
        .clamp(0, subtotal);
  }

  String _voucherCondition(Map<String, dynamic> voucher) {
    final notes = <String>[];
    final minimum = _asNum(voucher['minimum']);
    if (minimum != null) notes.add('Đơn tối thiểu ${_money(minimum)}');
    final condition = voucher['condition']?.toString().trim() ?? '';
    if (condition.isNotEmpty) notes.add(condition);
    return notes.isEmpty
        ? 'Không có điều kiện bổ sung'
        : 'Điều kiện: ${notes.join(' · ')}';
  }

  String _voucherDiscountLabel(Map<String, dynamic> voucher) {
    if (voucher['type'] != 'Phần trăm') return _money(voucher['value']);
    final percent = '${(_asNum(voucher['value']) ?? 0).toStringAsFixed(0)}%';
    final maximum = _asNum(voucher['maximum']);
    return maximum == null ? percent : '$percent · tối đa ${_money(maximum)}';
  }

  int get _pointsToUse {
    final serverPoints = _asInt(_estimate?['DiemSuDung']);
    if (serverPoints != null) return serverPoints;
    final remaining =
        _inspectionSubtotal -
        (_selectedEligibleVoucher == null
            ? 0
            : _voucherDiscount(_selectedEligibleVoucher!)) +
        (_asNum(_booking?['pickup_fee']) ?? 0) +
        (_asNum(_booking?['return_fee']) ?? 0);
    return remaining.clamp(0, _availablePoints).floor();
  }

  Widget _rewardChoices() => Column(
    children: [
      _voucherSection(),
      const SizedBox(height: 16),
      _pointsDiscountRow(),
    ],
  );

  Widget _voucherSection() {
    final selected = _selectedEligibleVoucher;
    return Container(
      decoration: BoxDecoration(
        color: selected == null
            ? AppColors.surface
            : AppColors.primaryExtraLight,
        border: Border.all(
          color: selected == null ? AppColors.border : AppColors.primary,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: _showVoucherPicker,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: selected == null
                            ? AppColors.background
                            : AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.local_offer_outlined,
                        color: selected == null
                            ? AppColors.textSecondary
                            : AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selected?['title']?.toString() ??
                                'Chọn mã giảm giá',
                            style: AppTypography.title,
                          ),
                          const SizedBox(height: 5),
                          if (selected == null)
                            Text(
                              _vouchers.isEmpty
                                  ? 'Chưa có mã giảm giá'
                                  : '${_vouchers.length} mã có sẵn · chạm để xem chi tiết',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            )
                          else ...[
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                _StaffVoucherCodeTag(
                                  code: selected['code'].toString(),
                                ),
                                Text(
                                  '−${_money(_voucherDiscount(selected))}',
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.success,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _voucherCondition(selected),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right, color: AppColors.textMuted),
                  ],
                ),
              ),
            ),
          ),
          if (selected != null)
            IconButton(
              tooltip: 'Bỏ mã giảm giá',
              onPressed: () => setState(() {
                _selectedPromotionId = null;
                _invalidateEstimate();
              }),
              icon: const Icon(Icons.close, size: 20),
            ),
        ],
      ),
    );
  }

  Widget _pointsDiscountRow() {
    final discount = _usePoints ? _pointsToUse : 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _usePoints ? AppColors.primaryLight : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _usePoints ? AppColors.primary : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          Switch(
            value: _usePoints,
            onChanged: _availablePoints == 0
                ? null
                : (value) => setState(() {
                    _usePoints = value;
                    _invalidateEstimate();
                  }),
            activeThumbColor: AppColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sử dụng điểm tích lũy', style: AppTypography.title),
                if (_usePoints && discount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Giảm ${_money(discount)}',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Dùng $discount điểm · còn ${_availablePoints - discount} điểm',
                    style: AppTypography.caption,
                  ),
                ] else if (_usePoints)
                  Text(
                    'Đơn hàng chưa đủ giá trị để dùng điểm.',
                    style: AppTypography.caption,
                  )
                else if (_availablePoints == 0)
                  Text('Không có điểm để sử dụng', style: AppTypography.caption)
                else ...[
                  const SizedBox(height: 4),
                  Text(
                    '$_availablePoints điểm khả dụng',
                    style: AppTypography.caption,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showVoucherPicker() async {
    String? selectedCode = _vouchers
        .where((voucher) => _asInt(voucher['id']) == _selectedPromotionId)
        .map((voucher) => voucher['code']?.toString())
        .firstOrNull;
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * .78,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.confirmation_number_outlined,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Mã giảm giá', style: AppTypography.heading3),
                            Text(
                              '${_vouchers.length} ưu đãi trong tài khoản',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    children: [
                      ..._vouchers.map((voucher) {
                        final id = _asInt(voucher['id']);
                        if (id == null) return const SizedBox.shrink();
                        final eligible = _isVoucherEligible(voucher);
                        final minimum = _asNum(voucher['minimum']);
                        final remaining = minimum == null
                            ? 0
                            : minimum - _inspectionSubtotal;
                        final condition = !eligible && minimum != null
                            ? 'Cần mua thêm ${_money(remaining)} · ${_voucherCondition(voucher)}'
                            : _voucherCondition(voucher);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _StaffVoucherOptionCard(
                            title: voucher['title']?.toString() ?? 'Ưu đãi',
                            code: voucher['code']?.toString() ?? '',
                            discountLabel: _voucherDiscountLabel(voucher),
                            condition: condition,
                            selected:
                                voucher['code']?.toString() == selectedCode,
                            eligible: eligible,
                            best:
                                eligible &&
                                _vouchers.isNotEmpty &&
                                id == _asInt(_vouchers.first['id']),
                            savingAmount: eligible
                                ? _voucherDiscount(voucher)
                                : null,
                            savingAmountLabel: eligible
                                ? _money(_voucherDiscount(voucher))
                                : null,
                            onTap:
                                eligible ||
                                    voucher['code']?.toString() == selectedCode
                                ? () => setSheetState(
                                    () => selectedCode =
                                        selectedCode == voucher['code']
                                        ? null
                                        : voucher['code']?.toString(),
                                  )
                                : null,
                          ),
                        );
                      }),
                      if (_vouchers.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text('Hiện chưa có mã giảm giá khả dụng.'),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () =>
                          Navigator.pop(sheetContext, selectedCode ?? ''),
                      child: const Text('Xong'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedPromotionId = _vouchers
          .where((voucher) => voucher['code']?.toString() == selected)
          .map((voucher) => _asInt(voucher['id']))
          .firstOrNull;
      _invalidateEstimate();
    });
  }

  static const _methods = ['Tại cửa hàng', 'Tại nhà'];
}

class _StaffVoucherOptionCard extends StatelessWidget {
  const _StaffVoucherOptionCard({
    required this.title,
    required this.code,
    required this.discountLabel,
    required this.condition,
    required this.selected,
    required this.eligible,
    required this.onTap,
    this.best = false,
    this.savingAmount,
    this.savingAmountLabel,
  });

  final String title;
  final String code;
  final String discountLabel;
  final String condition;
  final bool selected;
  final bool eligible;
  final bool best;
  final num? savingAmount;
  final String? savingAmountLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final background = !eligible
        ? AppColors.background
        : selected
        ? AppColors.primaryLight
        : AppColors.surface;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.divider,
              width: selected ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: selected ? AppColors.primaryLight : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.confirmation_number_outlined,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: AppTypography.title.copyWith(
                              color: eligible
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                              fontWeight: selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        if (best)
                          const Icon(
                            Icons.star_rounded,
                            size: 17,
                            color: AppColors.warning,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 7,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _StaffVoucherCodeTag(code: code),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: eligible
                                ? AppColors.successLight
                                : AppColors.warningLight,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            discountLabel,
                            style: AppTypography.caption.copyWith(
                              color: eligible
                                  ? AppColors.secondary
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (savingAmount != null && savingAmount! > 0)
                          Text(
                            'Tiết kiệm $savingAmountLabel',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.success,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      condition,
                      style: AppTypography.bodySmall.copyWith(
                        color: eligible
                            ? AppColors.textSecondary
                            : AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected ? AppColors.primary : AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StaffVoucherCodeTag extends StatelessWidget {
  const _StaffVoucherCodeTag({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: AppColors.primaryLight),
      borderRadius: BorderRadius.circular(6),
    ),
    child: Text(
      code,
      style: AppTypography.caption.copyWith(
        color: AppColors.primaryDark,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.4,
      ),
    ),
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
