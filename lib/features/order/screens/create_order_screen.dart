import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/core/utils/formatter_utils.dart';
import 'package:app_quanly_giaiui/features/order/data/order_repository.dart';
import 'package:app_quanly_giaiui/features/order/data/delivery_fee_quote.dart';
import 'package:app_quanly_giaiui/features/order/domain/cart_item.dart';
import 'package:app_quanly_giaiui/features/order/domain/cart_store.dart';
import 'package:app_quanly_giaiui/features/order/domain/laundry_order_pricing.dart';
import 'package:app_quanly_giaiui/features/loyalty/data/loyalty_repository.dart';
import 'package:app_quanly_giaiui/features/profile/data/address_repository.dart';
import 'package:app_quanly_giaiui/features/profile/data/current_location_service.dart';
import 'package:app_quanly_giaiui/features/profile/data/address_suggestion_service.dart';

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({
    this.initialPriceId,
    this.checkoutCart = false,
    this.selectedCartPriceIds,
    super.key,
  });

  final int? initialPriceId;
  final bool checkoutCart;
  final Set<int>? selectedCartPriceIds;

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _measurementController = TextEditingController();
  final _notesController = TextEditingController();
  final _promotionController = TextEditingController();
  final _repository = OrderRepository();
  final _loyaltyRepository = LoyaltyRepository();
  final _addressRepository = AddressRepository();
  final _currentLocationService = CurrentLocationService();
  final _addressSuggestionService = AddressSuggestionService();
  final _cartStore = CartStore.instance;
  final List<CartItem> _draftItems = [];
  late Future<_OrderFormData> _formDataFuture;
  Set<int>? _checkoutPriceIds;

  LaundryPriceOption? _selectedPrice;
  List<CartItem> get _cart => widget.checkoutCart
      ? _cartStore.items
            .where((item) =>
                _checkoutPriceIds == null ||
                _checkoutPriceIds!.contains(item.price.priceId))
            .toList(growable: false)
      : _draftItems;
  CustomerAddress? _selectedPickupAddress;
  CustomerAddress? _selectedDeliveryAddress;
  CurrentLocationResult? _currentPickupLocation;
  CurrentLocationResult? _currentDeliveryLocation;
  final _pickupAddressOverride = TextEditingController();
  final _deliveryAddressOverride = TextEditingController();
  bool _isResolvingPickupLocation = false;
  bool _isResolvingDeliveryLocation = false;
  bool _pickupAddressVerified = false;
  bool _deliveryAddressVerified = false;
  bool _pickupAddressWasCleared = false;
  bool _deliveryAddressWasCleared = false;
  String _paymentMethod = 'Tiền mặt';
  String _pickupMethod = 'Tại cửa hàng';
  String _serviceSearchQuery = '';
  bool _provideLaundryDetails = false;
  late DateTime _appointment;
  bool _usePointsForDiscount = false;
  String _deliveryMethod = 'Tại cửa hàng';
  int _availablePoints = 0;
  bool _isLoadingPoints = true;
  bool _pointsLoadFailed = false;
  Timer? _deliveryQuoteDebounce;
  DeliveryFeeQuote? _deliveryQuote;
  String? _quotedPickupAddress;
  String? _quotedDeliveryAddress;
  String? _deliveryQuoteError;
  bool _isLoadingDeliveryQuote = false;
  int _deliveryQuoteGeneration = 0;

  @override
  void initState() {
    super.initState();
    _checkoutPriceIds = widget.selectedCartPriceIds == null
        ? null
        : Set<int>.from(widget.selectedCartPriceIds!);
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _appointment = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10);
    _provideLaundryDetails =
        widget.checkoutCart || widget.initialPriceId != null;
    if (widget.checkoutCart) _cartStore.addListener(_onCartChanged);
    _formDataFuture = _loadFormData();
    _loadAvailablePoints();
  }

  Future<_OrderFormData> _loadFormData() async {
    const timeout = Duration(seconds: 15);
    final pricesFuture = _repository.getActivePrices().timeout(timeout);
    final addressesFuture = _addressRepository
        .getAddresses()
        .timeout(timeout)
        .catchError((_) => <CustomerAddress>[]);
    final vouchersFuture = _loyaltyRepository
        .getSummary()
        .then((summary) => summary.vouchers)
        .catchError((_) => <LoyaltyVoucher>[]);
    final result = await Future.wait<dynamic>([
      pricesFuture,
      addressesFuture,
      vouchersFuture,
    ]);
    final prices = result[0] as List<LaundryPriceOption>;
    if (widget.checkoutCart) {
      await _cartStore.restore(prices);
      if (_cart.isNotEmpty) _provideLaundryDetails = true;
    }
    return _OrderFormData(
      prices: prices,
      addresses: result[1] as List<CustomerAddress>,
      vouchers: result[2] as List<LoyaltyVoucher>,
    );
  }

  @override
  void dispose() {
    _deliveryQuoteDebounce?.cancel();
    if (widget.checkoutCart) _cartStore.removeListener(_onCartChanged);
    _measurementController.dispose();
    _notesController.dispose();
    _promotionController.dispose();
    _pickupAddressOverride.dispose();
    _deliveryAddressOverride.dispose();
    super.dispose();
  }

  void _onCartChanged() {
    if (mounted) setState(() {});
  }

  bool get _isWeightBased {
    final symbol = (_selectedPrice?.unitSymbol ?? '').toLowerCase();
    return symbol == 'kg' || symbol == 'kilogram';
  }

  num get _measurement =>
      num.tryParse(_measurementController.text.trim().replaceAll(',', '.')) ??
      0;

  int get _cartTotalMinorUnits {
    var total = 0;
    for (final item in _cart) {
      total += item.estimatedTotalMinorUnits;
    }
    return total;
  }

  int get _pointsToUse => LaundryOrderPricing.redeemablePoints(
    availablePoints: _availablePoints,
    subtotalMinorUnits: _cartTotalMinorUnits,
  );

  int get _pointsDiscount {
    if (!_usePointsForDiscount) return 0;
    return LaundryOrderPricing.pointsDiscountMinorUnits(_pointsToUse);
  }

  num _promotionDiscount(LoyaltyVoucher voucher) {
    final subtotal = _cartTotalMinorUnits / 100;
    if (!_isVoucherEligible(voucher)) return 0;
    final discount = voucher.discountType == 'Phần trăm'
        ? subtotal * voucher.discountValue / 100
        : voucher.discountValue;
    return discount.clamp(0, voucher.maximumDiscount ?? discount);
  }

  bool _isVoucherEligible(LoyaltyVoucher voucher) =>
      voucher.minimumOrder == null ||
      _cartTotalMinorUnits / 100 >= voucher.minimumOrder!;

  String _voucherCondition(LoyaltyVoucher voucher) {
    final notes = <String>[];
    if (voucher.minimumOrder != null) {
      notes.add('Đơn tối thiểu ${_formatVnd(voucher.minimumOrder!)}');
    }
    final condition = voucher.condition?.trim();
    if (condition != null && condition.isNotEmpty) notes.add(condition);
    return notes.isEmpty
        ? 'Không có điều kiện bổ sung'
        : 'Điều kiện: ${notes.join(' · ')}';
  }

  LoyaltyVoucher? _selectedEligibleVoucher(List<LoyaltyVoucher> vouchers) =>
      vouchers
          .where(
            (voucher) =>
                voucher.code == _promotionController.text &&
                _isVoucherEligible(voucher),
          )
          .firstOrNull;

  String _voucherDiscountLabel(LoyaltyVoucher voucher) {
    if (voucher.discountType != 'Phần trăm') {
      return _formatVnd(voucher.discountValue);
    }
    final percent = '${voucher.discountValue.toStringAsFixed(0)}%';
    final cap = voucher.maximumDiscount;
    return cap == null ? percent : '$percent · tối đa ${_formatVnd(cap)}';
  }

  Future<void> _showVoucherPicker(List<LoyaltyVoucher> vouchers) async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.78,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
                child: Row(
                  children: [
                    const Icon(Icons.confirmation_number_outlined,
                        color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Mã giảm giá', style: AppTypography.heading3),
                          Text(
                            '${vouchers.length} ưu đãi trong tài khoản',
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
                    _VoucherOptionCard(
                      title: 'Không sử dụng mã giảm giá',
                      code: null,
                      discountLabel: 'Giữ nguyên giá đơn hàng',
                      condition: 'Bạn có thể chọn mã khác bất cứ lúc nào.',
                      selected: _promotionController.text.isEmpty,
                      onTap: () => Navigator.pop(sheetContext, ''),
                    ),
                    const SizedBox(height: 10),
                    ...vouchers.map((voucher) {
                      final eligible = _isVoucherEligible(voucher);
                      final minimum = voucher.minimumOrder;
                      final remaining = minimum == null
                          ? 0
                          : minimum - _cartTotalMinorUnits / 100;
                      final condition = !eligible && minimum != null
                          ? 'Cần mua thêm ${_formatVnd(remaining)} · ${_voucherCondition(voucher)}'
                          : _voucherCondition(voucher);
                      final isBest = eligible &&
                          vouchers.isNotEmpty &&
                          voucher.id == vouchers.first.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _VoucherOptionCard(
                          title: voucher.title,
                          code: voucher.code,
                          discountLabel: _voucherDiscountLabel(voucher),
                          condition: condition,
                          selected: voucher.code == _promotionController.text,
                          eligible: eligible,
                          best: isBest,
                          savingAmount: eligible
                              ? _promotionDiscount(voucher)
                              : null,
                          onTap: eligible
                              ? () => Navigator.pop(sheetContext, voucher.code)
                              : null,
                        ),
                      );
                    }),
                    if (vouchers.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(24),
                        child: Center(
                          child: Text('Hiện chưa có mã giảm giá khả dụng.'),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (code == null || !mounted) return;
    setState(() => _promotionController.text = code);
  }

  Widget _voucherSection(List<LoyaltyVoucher> vouchers) {
    final selected = _selectedEligibleVoucher(vouchers);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Mã giảm giá', style: AppTypography.heading3),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: selected == null ? AppColors.surface : AppColors.primaryExtraLight,
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
                  onTap: () => _showVoucherPicker(vouchers),
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
                                selected?.title ?? 'Chọn mã giảm giá',
                                style: AppTypography.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 5),
                              if (selected == null)
                                Text(
                                  vouchers.isEmpty
                                      ? 'Chưa có mã giảm giá'
                                      : '${vouchers.length} mã có sẵn · chạm để xem chi tiết',
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
                                    _VoucherCodeTag(code: selected.code),
                                    Text(
                                      '−${_formatVnd(_promotionDiscount(selected))}',
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
                  onPressed: () => setState(() => _promotionController.clear()),
                  icon: const Icon(Icons.close, size: 20),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _discountTotalCard(List<LoyaltyVoucher> vouchers) {
    final voucher = _selectedEligibleVoucher(vouchers);
    final deliveryFee = _deliveryQuote?.totalFeeVnd ?? 0;
    final total = _finalTotal(vouchers) / 100 + deliveryFee;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryExtraLight,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.primaryLight),
      ),
      child: Column(
        children: [
          _PriceBreakdownLine(
            label: 'Tạm tính dịch vụ',
            value: _formatVnd(_cartTotalMinorUnits / 100),
          ),
          if (voucher != null) ...[
            const SizedBox(height: 8),
            _PriceBreakdownLine(
              label: 'Mã ${voucher.code}',
              value: '−${_formatVnd(_promotionDiscount(voucher))}',
              valueColor: AppColors.success,
            ),
          ],
          if (_usePointsForDiscount && _pointsDiscount > 0) ...[
            const SizedBox(height: 8),
            _PriceBreakdownLine(
              label: 'Điểm tích lũy ($_pointsToUse điểm)',
              value: '−${_formatVnd(_pointsDiscount / 100)}',
              valueColor: AppColors.success,
            ),
          ],
          if (_hasHomeDeliveryLeg && _deliveryQuote != null) ...[
            const SizedBox(height: 8),
            _PriceBreakdownLine(
              label: 'Phí giao nhận dự kiến',
              value: _formatVnd(deliveryFee),
            ),
          ],
          const Divider(height: 24),
          Row(
            children: [
              Expanded(
                child: Text('Tổng cộng', style: AppTypography.heading3),
              ),
              Text(
                _formatVnd(total),
                style: AppTypography.heading3.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          if (_hasHomeDeliveryLeg && _deliveryQuote == null) ...[
            const SizedBox(height: 6),
            const Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Chưa gồm phí giao nhận đang chờ tính.',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  int _finalTotal(List<LoyaltyVoucher> vouchers) {
    final selectedVoucher = _selectedEligibleVoucher(vouchers);
    final promotionDiscountMinorUnits = selectedVoucher == null
        ? 0
        : (_promotionDiscount(selectedVoucher) * 100).round();
    final totalDiscountMinorUnits = (_pointsDiscount +
            promotionDiscountMinorUnits)
        .clamp(0, _cartTotalMinorUnits);
    return _cartTotalMinorUnits - totalDiscountMinorUnits;
  }

  Future<void> _loadAvailablePoints() async {
    try {
      final summary = await _loyaltyRepository.getSummary();
      if (!mounted) return;
      setState(() {
        _availablePoints = summary.points;
        _isLoadingPoints = false;
        _pointsLoadFailed = false;
        if (_availablePoints == 0) _usePointsForDiscount = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingPoints = false;
        _pointsLoadFailed = true;
      });
    }
  }

  void _retryLoadingPoints() {
    setState(() {
      _isLoadingPoints = true;
      _pointsLoadFailed = false;
    });
    _loadAvailablePoints();
  }

  void _addToCart() {
    final price = _selectedPrice;
    final measurement = _measurement;
    if (price == null) return;
    if (!measurement.isFinite ||
        measurement <= 0 ||
        measurement > 99999999.99) {
      _showMessage('Nhập số lượng hoặc khối lượng hợp lệ.');
      return;
    }
    if (measurement * 100 != (measurement * 100).round()) {
      _showMessage('Số lượng chỉ được có tối đa 2 chữ số thập phân.');
      return;
    }

    final item = CartItem(price: price, measurement: measurement);
    if (widget.checkoutCart) {
      _cartStore.add(item);
      _checkoutPriceIds?.add(price.priceId);
    } else {
      _draftItems.add(item);
    }
    setState(() {
      _selectedPrice = null;
      _measurementController.clear();
    });
  }

  void _removeFromCart(int index) {
    if (widget.checkoutCart) {
      if (index < 0 || index >= _cart.length) return;
      _cartStore.removePriceIds({_cart[index].price.priceId});
    } else {
      setState(() => _draftItems.removeAt(index));
    }
  }

  void _clearCart() {
    if (widget.checkoutCart) {
      final selectedIds = _checkoutPriceIds;
      if (selectedIds == null) {
        _cartStore.clear();
      } else {
        _cartStore.removePriceIds(selectedIds);
      }
    } else {
      setState(() => _draftItems.clear());
    }
  }

  Future<void> _setStoreInspectionMode(bool storeWillInspect) async {
    if (storeWillInspect && widget.checkoutCart && _cart.isNotEmpty) {
      final shouldClear = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Bỏ các mục trong giỏ?'),
          content: const Text(
            'Khi để cửa hàng tự kiểm nhận, các dịch vụ và số lượng đang chọn sẽ không được gửi cùng đơn.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Quay lại'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Bỏ mục và tiếp tục'),
            ),
          ],
        ),
      );
      if (shouldClear != true || !mounted) return;
      _cartStore.clear();
    }

    if (!mounted) return;
    if (storeWillInspect && !widget.checkoutCart) _draftItems.clear();
    setState(() {
      _provideLaundryDetails = !storeWillInspect;
      _selectedPrice = null;
      _measurementController.clear();
    });
  }

  int? get _estimatedTotalMinorUnits {
    final price = _selectedPrice;
    if (price == null || _measurement <= 0) return null;
    return LaundryOrderPricing.lineTotalMinorUnits(
      unitPriceVnd: price.unitPriceVnd,
      quantity: _isWeightBased ? null : _measurement,
      weightKg: _isWeightBased ? _measurement : null,
    );
  }

  Future<void> _chooseAppointment() async {
    final now = DateTime.now();
    final selectedDate = await showDatePicker(
      context: context,
      initialDate: _appointment.isBefore(now) ? now : _appointment,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 30)),
    );
    if (selectedDate == null || !mounted) return;

    final selectedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_appointment),
    );
    if (selectedTime == null || !mounted) return;

    setState(() {
      _appointment = DateTime(
        selectedDate.year,
        selectedDate.month,
        selectedDate.day,
        selectedTime.hour,
        selectedTime.minute,
      );
    });
  }

  Future<void> _useCurrentLocation({required bool forDelivery}) async {
    final resolving = forDelivery
        ? _isResolvingDeliveryLocation
        : _isResolvingPickupLocation;
    if (resolving) return;
    setState(() {
      if (forDelivery) {
        _isResolvingDeliveryLocation = true;
      } else {
        _isResolvingPickupLocation = true;
      }
    });
    try {
      final location = await _currentLocationService.getCurrentAddress();
      if (!mounted) return;
      setState(() {
        if (forDelivery) {
          _currentDeliveryLocation = location;
          _selectedDeliveryAddress = null;
          _deliveryAddressVerified = true;
          _deliveryAddressOverride.text = location.address;
        } else {
          _currentPickupLocation = location;
          _selectedPickupAddress = null;
          _pickupAddressVerified = true;
          _pickupAddressOverride.text = location.address;
        }
      });
      _scheduleDeliveryQuote();
    } catch (error) {
      if (mounted) {
        final message = error is CurrentLocationException
            ? error.message
            : 'Không lấy được địa chỉ hiện tại. Vui lòng thử lại.';
        _showMessage(message);
      }
    } finally {
      if (mounted) {
        setState(() {
          if (forDelivery) {
            _isResolvingDeliveryLocation = false;
          } else {
            _isResolvingPickupLocation = false;
          }
        });
      }
    }
  }

  String? _addressFrom(
    TextEditingController override,
    CurrentLocationResult? location,
    CustomerAddress? savedAddress,
  ) {
    final entered = override.text.trim();
    if (entered.isNotEmpty) return entered;
    return location?.address.trim() ?? savedAddress?.address.trim();
  }

  String? get _pickupAddress => _addressFrom(
    _pickupAddressOverride,
    _currentPickupLocation,
    _selectedPickupAddress,
  );

  String? get _deliveryAddress => _addressFrom(
    _deliveryAddressOverride,
    _currentDeliveryLocation,
    _selectedDeliveryAddress,
  );

  String? get _quotePickupAddress =>
      _pickupMethod == 'Tại nhà' ? _pickupAddress : null;

  String? get _quoteDeliveryAddress =>
      _deliveryMethod == 'Tại nhà' ? _deliveryAddress : null;

  bool get _hasHomeDeliveryLeg =>
      _pickupMethod == 'Tại nhà' || _deliveryMethod == 'Tại nhà';

  bool get _hasCurrentDeliveryQuote {
    final quote = _deliveryQuote;
    return quote != null &&
        quote.expiresAt.isAfter(DateTime.now()) &&
        _quotedPickupAddress == _quotePickupAddress &&
        _quotedDeliveryAddress == _quoteDeliveryAddress;
  }

  void _scheduleDeliveryQuote() {
    _deliveryQuoteDebounce?.cancel();
    final generation = ++_deliveryQuoteGeneration;
    final pickup = _quotePickupAddress;
    final delivery = _quoteDeliveryAddress;

    if ((pickup == null || pickup.isEmpty) &&
        (delivery == null || delivery.isEmpty)) {
      setState(() {
        _deliveryQuote = null;
        _quotedPickupAddress = null;
        _quotedDeliveryAddress = null;
        _deliveryQuoteError = null;
        _isLoadingDeliveryQuote = false;
      });
      return;
    }

    // Address keystrokes are not confirmed locations. Wait for a saved, GPS,
    // or selected geocoder address before spending a quote request.
    final pickupReady = _pickupMethod != 'Tại nhà' ||
        (_pickupAddressVerified && pickup?.isNotEmpty == true);
    final deliveryReady = _deliveryMethod != 'Tại nhà' ||
        (_deliveryAddressVerified && delivery?.isNotEmpty == true);
    if (!pickupReady || !deliveryReady) {
      setState(() {
        _deliveryQuote = null;
        _quotedPickupAddress = null;
        _quotedDeliveryAddress = null;
        _deliveryQuoteError = null;
        _isLoadingDeliveryQuote = false;
      });
      return;
    }

    if (_hasCurrentDeliveryQuote) {
      setState(() {
        _deliveryQuoteError = null;
        _isLoadingDeliveryQuote = false;
      });
      return;
    }

    setState(() {
      _deliveryQuote = null;
      _quotedPickupAddress = null;
      _quotedDeliveryAddress = null;
      _deliveryQuoteError = null;
      _isLoadingDeliveryQuote = true;
    });
    _deliveryQuoteDebounce = Timer(const Duration(milliseconds: 1000), () {
      _fetchDeliveryQuote(generation, pickup, delivery);
    });
  }

  Future<DeliveryFeeQuote?> _fetchDeliveryQuote(
    int generation,
    String? pickup,
    String? delivery,
  ) async {
    try {
      final quote = await _repository.getDeliveryFeeQuote(
        pickupAddress: pickup,
        deliveryAddress: delivery,
      );
      if (!mounted || generation != _deliveryQuoteGeneration) return null;
      setState(() {
        _deliveryQuote = quote;
        _quotedPickupAddress = pickup;
        _quotedDeliveryAddress = delivery;
        _deliveryQuoteError = null;
        _isLoadingDeliveryQuote = false;
      });
      return quote;
    } catch (error) {
      if (!mounted || generation != _deliveryQuoteGeneration) return null;
      setState(() {
        _deliveryQuote = null;
        _deliveryQuoteError = error.toString().replaceFirst('Bad state: ', '');
        _isLoadingDeliveryQuote = false;
      });
      return null;
    }
  }

  Future<DeliveryFeeQuote?> _ensureDeliveryQuote() async {
    if (!_hasHomeDeliveryLeg) return null;
    final pickup = _quotePickupAddress;
    final delivery = _quoteDeliveryAddress;
    if ((pickup == null && _pickupMethod == 'Tại nhà') ||
        (delivery == null && _deliveryMethod == 'Tại nhà')) {
      _showMessage('Vui lòng nhập địa chỉ cho từng chặng giao nhận tại nhà.');
      return null;
    }
    if (_hasCurrentDeliveryQuote) return _deliveryQuote;

    _deliveryQuoteDebounce?.cancel();
    final generation = ++_deliveryQuoteGeneration;
    setState(() {
      _isLoadingDeliveryQuote = true;
      _deliveryQuoteError = null;
    });
    final quote = await _fetchDeliveryQuote(generation, pickup, delivery);
    if (quote == null && mounted) {
      _showMessage(_deliveryQuoteError ?? 'Không tính được phí giao nhận.');
    }
    return quote;
  }

  String _formatDistance(int meters) =>
      '${(meters / 1000).toStringAsFixed(1)} km';

  Widget _deliveryFeeLegRow({required String label, required int? feeVnd}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(
          feeVnd == null ? '—' : _formatVnd(feeVnd),
          style: AppTypography.bodyText.copyWith(color: AppColors.primary),
        ),
      ],
    );
  }

  Widget _deliveryFeeEstimate() {
    final quote = _hasCurrentDeliveryQuote ? _deliveryQuote : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Phí giao nhận theo từng chặng', style: AppTypography.heading3),
            const SizedBox(height: 8),
            if (_pickupMethod == 'Tại nhà')
              _deliveryFeeLegRow(
                label: quote == null
                    ? 'Chặng lấy đồ'
                    : 'Lấy đồ · ${_formatDistance(quote.pickupDistanceMeters)}',
                feeVnd: quote?.pickupFeeVnd,
              ),
            if (_deliveryMethod == 'Tại nhà')
              _deliveryFeeLegRow(
                label: quote == null
                    ? 'Chặng giao đồ'
                    : 'Giao đồ · ${_formatDistance(quote.deliveryDistanceMeters)}',
                feeVnd: quote?.deliveryFeeVnd,
              ),
            const SizedBox(height: 8),
            const Text(
              'Miễn phí 3 km đầu mỗi chặng; phần vượt tính 5.000đ/km và '
              'làm tròn lên 1.000đ. Quãng đường theo tuyến xe chạy từ cửa hàng.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            if (_isLoadingDeliveryQuote) ...[
              const SizedBox(height: 10),
              const LinearProgressIndicator(),
              const SizedBox(height: 6),
              const Text('Đang tính quãng đường thực tế...'),
            ] else if (_deliveryQuoteError != null) ...[
              const SizedBox(height: 10),
              Text(
                _deliveryQuoteError!,
                style: const TextStyle(color: AppColors.error),
              ),
            ] else if (quote != null) ...[
              const Divider(height: 20),
              _EstimateRow(
                label: 'Tổng phí giao nhận dự kiến',
                totalMinorUnits: quote.totalFeeVnd * 100,
                emphasize: true,
              ),
            ] else ...[
              const SizedBox(height: 8),
              const Text(
                'Nhập địa chỉ để xem phí cho các chặng tại nhà.',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showServicePicker(
    List<LaundryPriceOption> availablePrices,
  ) async {
    _serviceSearchQuery = '';
    final selected = await showModalBottomSheet<LaundryPriceOption>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final normalizedQuery = _serviceSearchQuery.trim().toLowerCase();
          final filteredPrices = availablePrices
              .where((price) {
                final label =
                    '${price.serviceName} ${price.itemTypeName} '
                            '${price.unitName} ${price.unitSymbol}'
                        .toLowerCase();
                return label.contains(normalizedQuery);
              })
              .toList(growable: false);

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 20,
                top: 16,
                right: 20,
                bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
              ),
              child: SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.75,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chọn dịch vụ và loại đồ',
                      style: AppTypography.heading3,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      autofocus: true,
                      decoration: const InputDecoration(
                        hintText: 'Tìm dịch vụ hoặc loại đồ...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) =>
                          setSheetState(() => _serviceSearchQuery = value),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: filteredPrices.isEmpty
                          ? const Center(
                              child: Text('Không tìm thấy dịch vụ phù hợp.'),
                            )
                          : ListView.separated(
                              itemCount: filteredPrices.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final price = filteredPrices[index];
                                return ListTile(
                                  leading: const Icon(
                                    Icons.local_laundry_service_outlined,
                                  ),
                                  title: Text(
                                    '${price.serviceName} · ${price.itemTypeName}',
                                  ),
                                  subtitle: Text(
                                    '${_formatVnd(price.unitPriceVnd)} / '
                                    '${price.unitSymbol}',
                                  ),
                                  onTap: () =>
                                      Navigator.pop(sheetContext, price),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (selected == null || !mounted) return;
    setState(() {
      _selectedPrice = selected;
      _measurementController.clear();
    });
  }

  Future<void> _continueToSummary(List<LoyaltyVoucher> vouchers) async {
    if (_provideLaundryDetails && _cart.isEmpty) {
      _showMessage(
        'Thêm ít nhất một loại đồ hoặc bỏ chọn mục nhập thông tin đồ giặt.',
      );
      return;
    }
    if (_pickupMethod == 'Tại nhà' && _pickupAddress == null) {
      _showMessage('Nhập, chọn hoặc dùng vị trí hiện tại cho địa chỉ lấy đồ.');
      return;
    }
    if (_pickupMethod == 'Tại nhà' && _pickupAddressOverride.text.trim().isNotEmpty && !_pickupAddressVerified) {
      _showMessage('Vui lòng chọn một địa chỉ trong danh sách gợi ý.');
      return;
    }
    if (_deliveryMethod == 'Tại nhà' && _deliveryAddress == null) {
      _showMessage('Nhập, chọn hoặc dùng vị trí hiện tại cho địa chỉ giao đồ.');
      return;
    }
    if (_deliveryMethod == 'Tại nhà' && _deliveryAddressOverride.text.trim().isNotEmpty && !_deliveryAddressVerified) {
      _showMessage('Vui lòng chọn một địa chỉ trong danh sách gợi ý.');
      return;
    }
    final deliveryQuote = await _ensureDeliveryQuote();
    if (_hasHomeDeliveryLeg && deliveryQuote == null) return;

    final selectedVoucher = vouchers
        .where(
          (voucher) =>
              voucher.code == _promotionController.text &&
              _isVoucherEligible(voucher),
        )
        .firstOrNull;
    context.pushNamed(
      AppRoutes.orderSummary,
      extra: {
        'cart': _cart,
        'clearCartAfterSubmit': widget.checkoutCart,
        'clearCartPriceIds': _checkoutPriceIds?.toList(),
        'provideLaundryDetails': _provideLaundryDetails,
        'paymentMethod': _paymentMethod,
        'pickupMethod': _pickupMethod,
        'deliveryMethod': _deliveryMethod,
        'address': _pickupMethod == 'Tại nhà' ? _pickupAddress : null,
        'deliveryAddress': _deliveryMethod == 'Tại nhà'
            ? _deliveryAddress
            : null,
        'deliveryQuoteId': deliveryQuote?.quoteId,
        'pickupDistanceMeters': deliveryQuote?.pickupDistanceMeters ?? 0,
        'pickupDeliveryFeeVnd': deliveryQuote?.pickupFeeVnd ?? 0,
        'deliveryDistanceMeters': deliveryQuote?.deliveryDistanceMeters ?? 0,
        'deliveryFeeVnd': deliveryQuote?.deliveryFeeVnd ?? 0,
        'appointment': _appointment,
        'notes': _notesController.text.trim(),
        'usePoints': _provideLaundryDetails && _usePointsForDiscount,
        'pointsUsedEstimate': _pointsToUse,
        'pointsDiscountEstimateVnd': _pointsDiscount / 100,
        'promotionCode': selectedVoucher?.code ?? '',
        'promotionDiscountEstimateVnd': selectedVoucher == null
            ? 0
            : _promotionDiscount(selectedVoucher),
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tạo đơn giặt ủi')),
      body: FutureBuilder<_OrderFormData>(
        future: _formDataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return _LoadError(
              onRetry: () {
                setState(() {
                  _formDataFuture = _loadFormData();
                });
              },
            );
          }

          final allPrices = snapshot.data!.prices;
          final addresses = snapshot.data!.addresses;
          final vouchers = List<LoyaltyVoucher>.from(snapshot.data!.vouchers)
            ..sort(
              (a, b) => _promotionDiscount(b).compareTo(_promotionDiscount(a)),
            );
          if (_provideLaundryDetails && allPrices.isEmpty) {
            return const Center(child: Text('Hiện chưa có bảng giá khả dụng.'));
          }

          final initialServiceId = widget.initialPriceId == null
              ? null
              : allPrices
                    .where((price) => price.priceId == widget.initialPriceId)
                    .firstOrNull
                    ?.serviceId;
          final addedPriceIds = _cart.map((item) => item.price.priceId).toSet();
          final scopedPrices = initialServiceId == null
              ? allPrices
              : allPrices
                    .where((price) => price.serviceId == initialServiceId)
                    .toList(growable: false);
          final availablePrices = scopedPrices
              .where((price) => !addedPriceIds.contains(price.priceId))
              .toList(growable: false);
          final selectedPrice =
              _selectedPrice != null &&
                  availablePrices.any(
                    (price) => price.priceId == _selectedPrice!.priceId,
                  )
              ? _selectedPrice
              : null;
          final selectedPickupAddressId = _selectedPickupAddress?.id;
          if (selectedPickupAddressId != null) {
            _selectedPickupAddress = addresses
                .where((address) => address.id == selectedPickupAddressId)
                .firstOrNull;
          }
          final selectedDeliveryAddressId = _selectedDeliveryAddress?.id;
          if (selectedDeliveryAddressId != null) {
            _selectedDeliveryAddress = addresses
                .where((address) => address.id == selectedDeliveryAddressId)
                .firstOrNull;
          }
          if (_selectedPickupAddress == null && _currentPickupLocation == null && !_pickupAddressWasCleared) {
            _selectedPickupAddress = addresses.where((address) => address.isDefault).firstOrNull;
            _selectedPickupAddress ??= addresses.firstOrNull;
            if (_pickupAddressOverride.text.isEmpty && _selectedPickupAddress != null) {
              _pickupAddressOverride.text = _selectedPickupAddress!.address;
              _pickupAddressVerified = true;
            }
          }
          if (_selectedDeliveryAddress == null && _currentDeliveryLocation == null && !_deliveryAddressWasCleared) {
            _selectedDeliveryAddress = addresses.where((address) => address.isDefault).firstOrNull;
            _selectedDeliveryAddress ??= addresses.firstOrNull;
            if (_deliveryAddressOverride.text.isEmpty && _selectedDeliveryAddress != null) {
              _deliveryAddressOverride.text = _selectedDeliveryAddress!.address;
              _deliveryAddressVerified = true;
            }
          }
          return Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Để cửa hàng kiểm nhận đồ và báo giá'),
                  subtitle: const Text(
                    'Bật nếu bạn chưa biết số lượng hoặc khối lượng đồ giặt.',
                  ),
                  value: !_provideLaundryDetails,
                  onChanged: _setStoreInspectionMode,
                ),
                if (!_provideLaundryDetails) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Bạn chỉ cần chọn hình thức nhận đồ và lịch hẹn ở bên dưới.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                ] else ...[
                  const SizedBox(height: 20),
                  Text('Dịch vụ và loại đồ', style: AppTypography.heading2),
                  const SizedBox(height: 12),
                  if (availablePrices.isEmpty)
                    const Text(
                      'Bạn đã thêm tất cả loại đồ có thể chọn.',
                      style: TextStyle(color: AppColors.textSecondary),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () => _showServicePicker(availablePrices),
                      icon: const Icon(Icons.search),
                      label: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          selectedPrice == null
                              ? 'Chọn dịch vụ và loại đồ giặt'
                              : '${selectedPrice.serviceName} · '
                                    '${selectedPrice.itemTypeName} '
                                    '(${selectedPrice.unitSymbol})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  if (selectedPrice != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${_formatVnd(selectedPrice.unitPriceVnd)} / '
                      '${selectedPrice.unitSymbol}',
                      style: AppTypography.bodyText.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    _isWeightBased ? 'Khối lượng dự kiến' : 'Số lượng',
                    style: AppTypography.heading3,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _measurementController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _isWeightBased
                          ? 'Khối lượng (kg)'
                          : 'Số lượng',
                      suffixText: _selectedPrice?.unitSymbol,
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (value) {
                      final measurement = num.tryParse(
                        (value ?? '').trim().replaceAll(',', '.'),
                      );
                      if (measurement == null || !measurement.isFinite) {
                        return 'Nhập số lượng hợp lệ.';
                      }
                      if (measurement <= 0 || measurement > 99999999.99) {
                        return 'Giá trị phải lớn hơn 0.';
                      }
                      if (measurement * 100 != (measurement * 100).round()) {
                        return 'Tối đa 2 chữ số thập phân.';
                      }
                      return null;
                    },
                  ),
                  if (_estimatedTotalMinorUnits case final total?) ...[
                    const SizedBox(height: 12),
                    _EstimateRow(totalMinorUnits: total),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: selectedPrice == null ? null : _addToCart,
                      icon: const Icon(Icons.add_shopping_cart_outlined),
                      label: const Text('Thêm vào đơn hàng'),
                    ),
                  ),
                  if (_cart.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Các mục đã chọn (${_cart.length})',
                            style: AppTypography.heading3,
                          ),
                        ),
                        TextButton(
                          onPressed: _clearCart,
                          child: const Text('Xóa tất cả'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ..._cart.indexed.map(
                      (entry) => _CartItemTile(
                        item: entry.$2,
                        onRemove: () => _removeFromCart(entry.$1),
                      ),
                    ),
                    _EstimateRow(totalMinorUnits: _cartTotalMinorUnits),
                    const SizedBox(height: 16),
                  ],
                ],
                const SizedBox(height: 28),
                Text(
                  'Hình thức nhân viên nhận đồ',
                  style: AppTypography.heading3,
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'Tại cửa hàng',
                      icon: Icon(Icons.storefront_outlined),
                      label: Text('Mang đến'),
                    ),
                    ButtonSegment(
                      value: 'Tại nhà',
                      icon: Icon(Icons.local_shipping_outlined),
                      label: Text('Lấy tận nơi'),
                    ),
                  ],
                  selected: {_pickupMethod},
                  onSelectionChanged: (selection) {
                    setState(() => _pickupMethod = selection.first);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _scheduleDeliveryQuote();
                    });
                  },
                ),
                if (_pickupMethod == 'Tại nhà') ...[
                  const SizedBox(height: 16),
                  _AddressInput(
                    label: 'Địa chỉ lấy đồ',
                    currentLocation: _currentPickupLocation,
                    controller: _pickupAddressOverride,
                    suggestionService: _addressSuggestionService,
                    addressVerified: _pickupAddressVerified,
                    isResolvingLocation: _isResolvingPickupLocation,
                    onAddressChanged: (_) {
                      setState(() {
                        _selectedPickupAddress = null;
                        _currentPickupLocation = null;
                        _pickupAddressVerified = false;
                        _pickupAddressWasCleared = true;
                      });
                      _scheduleDeliveryQuote();
                    },
                    onSelectSuggestion: (address) {
                      setState(() {
                        _selectedPickupAddress = null;
                        _currentPickupLocation = null;
                        _pickupAddressVerified = true;
                        _pickupAddressWasCleared = true;
                        _pickupAddressOverride.text = address;
                      });
                      _scheduleDeliveryQuote();
                    },
                    onClearAddress: () {
                      setState(() {
                        _selectedPickupAddress = null;
                        _currentPickupLocation = null;
                        _pickupAddressVerified = false;
                        _pickupAddressWasCleared = true;
                        _pickupAddressOverride.clear();
                      });
                      _scheduleDeliveryQuote();
                    },
                    onUseCurrentLocation: () =>
                        _useCurrentLocation(forDelivery: false),
                    onClearCurrentLocation: () => setState(() {
                      _currentPickupLocation = null;
                    }),
                    onManageAddresses: () async {
                      await context.pushNamed(AppRoutes.addressBook);
                      if (mounted) {
                        setState(() {
                          _selectedPickupAddress = null;
                          _formDataFuture = _loadFormData();
                        });
                        await _formDataFuture;
                        if (mounted) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _scheduleDeliveryQuote();
                          });
                        }
                      }
                    },
                  ),
                ],
                const SizedBox(height: 20),
                Text(
                  'Hình thức nhân viên giao đồ',
                  style: AppTypography.heading3,
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'Tại cửa hàng',
                      icon: Icon(Icons.storefront_outlined),
                      label: Text('Nhận tại cửa hàng'),
                    ),
                    ButtonSegment(
                      value: 'Tại nhà',
                      icon: Icon(Icons.local_shipping_outlined),
                      label: Text('Giao tận nhà'),
                    ),
                  ],
                  selected: {_deliveryMethod},
                  onSelectionChanged: (selection) {
                    setState(() => _deliveryMethod = selection.first);
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _scheduleDeliveryQuote();
                    });
                  },
                ),
                if (_deliveryMethod == 'Tại nhà') ...[
                  const SizedBox(height: 16),
                  _AddressInput(
                    label: 'Địa chỉ giao đồ',
                    currentLocation: _currentDeliveryLocation,
                    controller: _deliveryAddressOverride,
                    suggestionService: _addressSuggestionService,
                    addressVerified: _deliveryAddressVerified,
                    isResolvingLocation: _isResolvingDeliveryLocation,
                    onAddressChanged: (_) {
                      setState(() {
                        _selectedDeliveryAddress = null;
                        _currentDeliveryLocation = null;
                        _deliveryAddressVerified = false;
                        _deliveryAddressWasCleared = true;
                      });
                      _scheduleDeliveryQuote();
                    },
                    onSelectSuggestion: (address) {
                      setState(() {
                        _selectedDeliveryAddress = null;
                        _currentDeliveryLocation = null;
                        _deliveryAddressVerified = true;
                        _deliveryAddressWasCleared = true;
                        _deliveryAddressOverride.text = address;
                      });
                      _scheduleDeliveryQuote();
                    },
                    onClearAddress: () {
                      setState(() {
                        _selectedDeliveryAddress = null;
                        _currentDeliveryLocation = null;
                        _deliveryAddressVerified = false;
                        _deliveryAddressWasCleared = true;
                        _deliveryAddressOverride.clear();
                      });
                      _scheduleDeliveryQuote();
                    },
                    onUseCurrentLocation: () =>
                        _useCurrentLocation(forDelivery: true),
                    onClearCurrentLocation: () => setState(() {
                      _currentDeliveryLocation = null;
                    }),
                    onManageAddresses: () async {
                      await context.pushNamed(AppRoutes.addressBook);
                      if (mounted) {
                        setState(() {
                          _selectedDeliveryAddress = null;
                          _formDataFuture = _loadFormData();
                        });
                        await _formDataFuture;
                        if (mounted) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) _scheduleDeliveryQuote();
                          });
                        }
                      }
                    },
                  ),
                ],
                if (_hasHomeDeliveryLeg) ...[
                  const SizedBox(height: 16),
                  _deliveryFeeEstimate(),
                ],
                const SizedBox(height: 20),
                Text('Hình thức thanh toán', style: AppTypography.heading3),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'Tiền mặt',
                      icon: Icon(Icons.payments_outlined),
                      label: Text('Tiền mặt'),
                    ),
                    ButtonSegment(
                      value: 'Chuyển khoản',
                      icon: Icon(Icons.account_balance_outlined),
                      label: Text('Chuyển khoản'),
                    ),
                  ],
                  selected: {_paymentMethod},
                  onSelectionChanged: (selection) {
                    setState(() => _paymentMethod = selection.first);
                  },
                ),
                const SizedBox(height: 8),
                const Text(
                  'Phương thức đã chọn sẽ được dùng khi hóa đơn sẵn sàng; '
                  'số tiền cuối cùng được xác nhận sau khi cửa hàng kiểm nhận.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
                if (_provideLaundryDetails && _cart.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  _voucherSection(vouchers),
                  const SizedBox(height: 16),
                  _PointsDiscountRow(
                    usePoints: _usePointsForDiscount,
                    availablePoints: _availablePoints,
                    pointsToUse: _pointsToUse,
                    isLoading: _isLoadingPoints,
                    loadFailed: _pointsLoadFailed,
                    onRetry: _retryLoadingPoints,
                    onChanged: (value) =>
                        setState(() => _usePointsForDiscount = value),
                    discountAmount: _pointsDiscount,
                  ),
                  if (_usePointsForDiscount ||
                      _selectedEligibleVoucher(vouchers) != null) ...[
                    const SizedBox(height: 12),
                    _discountTotalCard(vouchers),
                  ],
                ],
                const SizedBox(height: 20),
                OutlinedButton.icon(
                  onPressed: _chooseAppointment,
                  icon: const Icon(Icons.calendar_month_outlined),
                  label: Text('Lịch hẹn: ${_formatDateTime(_appointment)}'),
                ),
                const SizedBox(height: 24),
                Text('Ghi chú xử lý', style: AppTypography.heading3),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Vết bẩn, yêu cầu riêng hoặc lưu ý khi giao nhận',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: () => _continueToSummary(vouchers),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('Xem xác nhận đơn'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} · '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _formatVnd(num value) => FormatterUtils.formatVnd(value);
}

class _AddressInput extends StatefulWidget {
  const _AddressInput({
    required this.label,
    required this.currentLocation,
    required this.controller,
    required this.suggestionService,
    required this.addressVerified,
    required this.isResolvingLocation,
    required this.onAddressChanged,
    required this.onSelectSuggestion,
    required this.onClearAddress,
    required this.onUseCurrentLocation,
    required this.onClearCurrentLocation,
    required this.onManageAddresses,
  });

  final String label;
  final CurrentLocationResult? currentLocation;
  final TextEditingController controller;
  final AddressSuggestionService suggestionService;
  final bool addressVerified;
  final bool isResolvingLocation;
  final ValueChanged<String> onAddressChanged;
  final ValueChanged<String> onSelectSuggestion;
  final VoidCallback onClearAddress;
  final VoidCallback onUseCurrentLocation;
  final VoidCallback onClearCurrentLocation;
  final Future<void> Function() onManageAddresses;

  @override
  State<_AddressInput> createState() => _AddressInputState();
}

class _AddressInputState extends State<_AddressInput> {
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
      setState(() { _suggestions = const []; _isSearching = false; });
      return;
    }
    setState(() => _isSearching = true);
    _debounce = Timer(const Duration(milliseconds: 700), () async {
      try {
        final results = await widget.suggestionService.suggest(query);
        if (!mounted || generation != _searchGeneration) return;
        setState(() { _suggestions = results; _isSearching = false; });
      } catch (_) {
        if (!mounted || generation != _searchGeneration) return;
        setState(() { _suggestions = const []; _isSearching = false; });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.label;
    final currentLocation = widget.currentLocation;
    final controller = widget.controller;
    final isResolvingLocation = widget.isResolvingLocation;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          maxLines: 2,
          textInputAction: TextInputAction.done,
          onChanged: (value) { widget.onAddressChanged(value); _search(value); },
          decoration: InputDecoration(
            labelText: label,
            hintText: 'Nhập địa chỉ rồi chọn kết quả gợi ý',
            prefixIcon: const Icon(Icons.edit_location_alt_outlined),
            suffixIcon: controller.text.isEmpty ? null : IconButton(
              tooltip: 'Xóa địa chỉ',
              onPressed: () {
                _searchGeneration++;
                _debounce?.cancel();
                setState(() => _suggestions = const []);
                widget.onClearAddress();
              },
              icon: const Icon(Icons.close),
            ),
          ),
          validator: (value) {
            final hasAddress = (value?.trim().isNotEmpty == true && widget.addressVerified) ||
                currentLocation != null;
            return hasAddress ? null : 'Vui lòng nhập hoặc chọn $label.';
          },
        ),
        if (_isSearching)
          const LinearProgressIndicator(minHeight: 2)
        else if (_suggestions.isNotEmpty)
          Card(
            margin: EdgeInsets.zero,
            child: Column(children: _suggestions.map((suggestion) => ListTile(
              dense: true,
              leading: const Icon(Icons.location_on_outlined),
              title: Text(suggestion),
              onTap: () {
                _searchGeneration++;
                _debounce?.cancel();
                setState(() => _suggestions = const []);
                widget.onSelectSuggestion(suggestion);
              },
            )).toList(growable: false)),
          )
        else if (controller.text.trim().length >= 5 && !widget.addressVerified)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('Chọn địa chỉ gợi ý để xác nhận địa chỉ hợp lệ.',
              style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary)),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: isResolvingLocation ? null : widget.onUseCurrentLocation,
          icon: isResolvingLocation
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location),
          label: Text(
            isResolvingLocation ? 'Đang lấy vị trí...' : 'Dùng vị trí hiện tại',
          ),
        ),
        if (currentLocation case final location?)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.check_circle, color: AppColors.primary),
            title: const Text('Đang dùng vị trí hiện tại'),
            subtitle: Text(
              '${location.latitude.toStringAsFixed(6)}, '
              '${location.longitude.toStringAsFixed(6)} · '
              'sai số ±${location.accuracyMeters.ceil()} m\n'
              'Bạn có thể sửa địa chỉ ở ô phía trên.',
            ),
            trailing: IconButton(
              tooltip: 'Bỏ chọn vị trí hiện tại',
              onPressed: widget.onClearCurrentLocation,
              icon: const Icon(Icons.close),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: widget.onManageAddresses,
            icon: const Icon(Icons.edit_location_alt_outlined),
            label: const Text('Quản lý địa chỉ'),
          ),
        ),
      ],
    );
  }
}

class _OrderFormData {
  const _OrderFormData({
    required this.prices,
    required this.addresses,
    required this.vouchers,
  });

  final List<LaundryPriceOption> prices;
  final List<CustomerAddress> addresses;
  final List<LoyaltyVoucher> vouchers;
}

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({required this.item, required this.onRemove});

  final CartItem item;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.local_laundry_service_outlined),
        title: Text('${item.price.serviceName} · ${item.price.itemTypeName}'),
        subtitle: Text(
          '${item.measurement} ${item.price.unitSymbol} · '
          '${FormatterUtils.formatVnd(item.price.unitPriceVnd)}/${item.price.unitSymbol}',
        ),
        trailing: IconButton(
          tooltip: 'Xóa mục này',
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline),
        ),
      ),
    );
  }
}

class _EstimateRow extends StatelessWidget {
  const _EstimateRow({
    this.label = 'Tạm tính',
    required this.totalMinorUnits,
    this.emphasize = false,
  });

  final String label;
  final int totalMinorUnits;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label),
        Text(
          FormatterUtils.formatVnd(totalMinorUnits / 100),
          style: (emphasize ? AppTypography.title : AppTypography.bodyText)
              .copyWith(color: AppColors.primary),
        ),
      ],
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 40),
            const SizedBox(height: 12),
            const Text('Không tải được dữ liệu đặt đơn.'),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ),
      ),
    );
  }
}

class _PointsDiscountRow extends StatelessWidget {
  const _PointsDiscountRow({
    required this.usePoints,
    required this.availablePoints,
    required this.pointsToUse,
    required this.isLoading,
    required this.loadFailed,
    required this.onRetry,
    required this.onChanged,
    required this.discountAmount,
  });

  final bool usePoints;
  final int availablePoints;
  final int pointsToUse;
  final bool isLoading;
  final bool loadFailed;
  final VoidCallback onRetry;
  final ValueChanged<bool> onChanged;
  final int discountAmount;

  String _formatVnd(num value) => FormatterUtils.formatVnd(value / 100);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: usePoints ? AppColors.primaryLight : AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: usePoints ? AppColors.primary : AppColors.divider,
        ),
      ),
      child: Row(
        children: [
          Switch(
            value: usePoints,
            onChanged: isLoading || loadFailed || availablePoints == 0
                ? null
                : onChanged,
            activeThumbColor: AppColors.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sử dụng điểm tích lũy', style: AppTypography.title),
                if (isLoading)
                  Text('Đang tải số dư điểm...', style: AppTypography.caption)
                else if (loadFailed) ...[
                  Text(
                    'Không tải được số dư điểm.',
                    style: AppTypography.caption,
                  ),
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Thử lại'),
                  ),
                ] else if (usePoints && discountAmount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Giảm ${_formatVnd(discountAmount)}',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    'Dùng $pointsToUse điểm · còn ${availablePoints - pointsToUse} điểm',
                    style: AppTypography.caption,
                  ),
                ] else if (usePoints)
                  Text(
                    availablePoints == 0
                        ? 'Không có điểm để sử dụng'
                        : 'Đơn hàng chưa đủ giá trị để dùng điểm.',
                    style: AppTypography.caption,
                  )
                else if (availablePoints == 0)
                  Text('Không có điểm để sử dụng', style: AppTypography.caption)
                else ...[
                  const SizedBox(height: 4),
                  Text(
                    '$availablePoints điểm khả dụng',
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
}

class _PriceBreakdownLine extends StatelessWidget {
  const _PriceBreakdownLine({
    required this.label,
    required this.value,
    this.valueColor,
  });

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(label, style: AppTypography.bodySmall),
      ),
      Text(
        value,
        style: AppTypography.bodySmall.copyWith(
          color: valueColor ?? AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    ],
  );
}

class _VoucherOptionCard extends StatelessWidget {
  const _VoucherOptionCard({
    required this.title,
    required this.code,
    required this.discountLabel,
    required this.condition,
    required this.selected,
    required this.onTap,
    this.eligible = true,
    this.best = false,
    this.savingAmount,
  });

  final String title;
  final String? code;
  final String discountLabel;
  final String condition;
  final bool selected;
  final bool eligible;
  final bool best;
  final num? savingAmount;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final background = !eligible
        ? AppColors.background
        : selected
        ? AppColors.primaryExtraLight
        : AppColors.surface;
    final borderColor = selected ? AppColors.primary : AppColors.divider;
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
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
                  code == null
                      ? Icons.block_outlined
                      : Icons.confirmation_number_outlined,
                  color: selected ? AppColors.primary : AppColors.textSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: AppTypography.title.copyWith(
                              color: eligible
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                        if (best) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.star_rounded,
                              size: 17, color: AppColors.warning),
                        ],
                        if (selected) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.check_circle,
                              size: 19, color: AppColors.primary),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 7,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (code != null) _VoucherCodeTag(code: code!),
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
                            'Tiết kiệm ${FormatterUtils.formatVnd(savingAmount!)}',
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
                        color: eligible ? AppColors.textSecondary : AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VoucherCodeTag extends StatelessWidget {
  const _VoucherCodeTag({required this.code});

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
