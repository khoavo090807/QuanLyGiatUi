import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/features/order/data/order_repository.dart';
import 'package:app_quanly_giaiui/features/order/domain/cart_item.dart';
import 'package:app_quanly_giaiui/features/order/domain/laundry_order_pricing.dart';
import 'package:app_quanly_giaiui/features/profile/data/address_repository.dart';
import 'package:app_quanly_giaiui/features/profile/data/current_location_service.dart';

class CreateOrderScreen extends StatefulWidget {
  const CreateOrderScreen({this.initialPriceId, super.key});

  final int? initialPriceId;

  @override
  State<CreateOrderScreen> createState() => _CreateOrderScreenState();
}

class _CreateOrderScreenState extends State<CreateOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _measurementController = TextEditingController();
  final _notesController = TextEditingController();
  final _repository = OrderRepository();
  final _addressRepository = AddressRepository();
  final _currentLocationService = CurrentLocationService();
  late Future<_OrderFormData> _formDataFuture;

  LaundryPriceOption? _selectedPrice;
  final List<CartItem> _cart = [];
  CustomerAddress? _selectedAddress;
  CurrentLocationResult? _currentPickupLocation;
  bool _isResolvingLocation = false;
  String _pickupMethod = 'Tại cửa hàng';
  String _serviceSearchQuery = '';
  bool _provideLaundryDetails = false;
  late DateTime _appointment;

  @override
  void initState() {
    super.initState();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    _appointment = DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 10);
    _formDataFuture = _loadFormData();
  }

  Future<_OrderFormData> _loadFormData() async {
    const timeout = Duration(seconds: 15);
    final pricesFuture = _repository.getActivePrices().timeout(timeout);
    final addressesFuture = _addressRepository
        .getAddresses()
        .timeout(timeout)
        .catchError((_) => <CustomerAddress>[]);
    final result = await Future.wait<dynamic>([pricesFuture, addressesFuture]);
    return _OrderFormData(
      prices: result[0] as List<LaundryPriceOption>,
      addresses: result[1] as List<CustomerAddress>,
    );
  }

  @override
  void dispose() {
    _measurementController.dispose();
    _notesController.dispose();
    super.dispose();
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

    setState(() {
      _cart.add(CartItem(price: price, measurement: measurement));
      _selectedPrice = null;
      _measurementController.clear();
    });
  }

  void _removeFromCart(int index) {
    setState(() {
      _cart.removeAt(index);
    });
  }

  void _clearCart() {
    setState(() {
      _cart.clear();
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

  Future<void> _useCurrentLocation() async {
    if (_isResolvingLocation) return;
    setState(() => _isResolvingLocation = true);
    try {
      final location = await _currentLocationService.getCurrentAddress();
      if (!mounted) return;
      setState(() {
        _currentPickupLocation = location;
        _selectedAddress = null;
      });
    } catch (error) {
      if (mounted) {
        final message = error is CurrentLocationException
            ? error.message
            : 'Không lấy được địa chỉ hiện tại. Vui lòng thử lại.';
        _showMessage(message);
      }
    } finally {
      if (mounted) setState(() => _isResolvingLocation = false);
    }
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

  void _continueToSummary() {
    if (_provideLaundryDetails && _cart.isEmpty) {
      _showMessage(
        'Thêm ít nhất một loại đồ hoặc bỏ chọn mục nhập thông tin đồ giặt.',
      );
      return;
    }
    if (_pickupMethod == 'Tại nhà' &&
        _selectedAddress == null &&
        _currentPickupLocation == null) {
      _showMessage('Chọn địa chỉ đã lưu hoặc dùng vị trí hiện tại.');
      return;
    }

    context.pushNamed(
      AppRoutes.orderSummary,
      extra: {
        'cart': _cart,
        'provideLaundryDetails': _provideLaundryDetails,
        'pickupMethod': _pickupMethod,
        'address': _pickupMethod == 'Tại nhà'
            ? _currentPickupLocation?.address ?? _selectedAddress?.address
            : null,
        'appointment': _appointment,
        'notes': _notesController.text.trim(),
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
          final selectedAddressId = _selectedAddress?.id;
          if (selectedAddressId != null) {
            _selectedAddress = addresses
                .where((address) => address.id == selectedAddressId)
                .firstOrNull;
          }
          if (_selectedAddress == null && _currentPickupLocation == null) {
            for (final address in addresses) {
              if (address.isDefault) {
                _selectedAddress = address;
                break;
              }
            }
            _selectedAddress ??= addresses.firstOrNull;
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
                  onChanged: (storeWillInspect) => setState(() {
                    _provideLaundryDetails = !storeWillInspect;
                    _selectedPrice = null;
                    _measurementController.clear();
                    if (storeWillInspect) _cart.clear();
                  }),
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
                  ],
                ],
                const SizedBox(height: 28),
                Text('Hình thức nhận đồ', style: AppTypography.heading3),
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
                  },
                ),
                if (_pickupMethod == 'Tại nhà') ...[
                  const SizedBox(height: 16),
                  if (addresses.isEmpty)
                    const Text('Thêm địa chỉ trước khi đặt lấy đồ tại nhà.')
                  else
                    DropdownButtonFormField<int>(
                      key: ValueKey(
                        addresses.map((address) => address.id).join(','),
                      ),
                      initialValue: _selectedAddress?.id,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Địa chỉ lấy đồ',
                        prefixIcon: Icon(Icons.location_on_outlined),
                      ),
                      items: addresses.map((address) {
                        return DropdownMenuItem(
                          value: address.id,
                          child: Text(
                            address.address,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (addressId) => setState(() {
                        _selectedAddress = addressId == null
                            ? null
                            : addresses.firstWhere(
                                (address) => address.id == addressId,
                              );
                        _currentPickupLocation = null;
                      }),
                      validator: (value) =>
                          value == null && _currentPickupLocation == null
                          ? 'Chọn địa chỉ nhận đồ.'
                          : null,
                    ),
                  OutlinedButton.icon(
                    onPressed: _isResolvingLocation
                        ? null
                        : _useCurrentLocation,
                    icon: _isResolvingLocation
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.my_location),
                    label: Text(
                      _isResolvingLocation
                          ? 'Đang lấy vị trí...'
                          : 'Dùng vị trí hiện tại',
                    ),
                  ),
                  if (_currentPickupLocation case final location?)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(
                        Icons.check_circle,
                        color: AppColors.primary,
                      ),
                      title: const Text('Đang dùng vị trí hiện tại'),
                      subtitle: Text(
                        '${location.address}\n'
                        '${location.latitude.toStringAsFixed(6)}, '
                        '${location.longitude.toStringAsFixed(6)} · '
                        'sai số ±${location.accuracyMeters.ceil()} m',
                      ),
                      trailing: IconButton(
                        tooltip: 'Bỏ chọn vị trí hiện tại',
                        onPressed: () =>
                            setState(() => _currentPickupLocation = null),
                        icon: const Icon(Icons.close),
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () async {
                        await context.pushNamed(AppRoutes.addressBook);
                        if (mounted) {
                          setState(() {
                            _selectedAddress = null;
                            _formDataFuture = _loadFormData();
                          });
                        }
                      },
                      icon: const Icon(Icons.edit_location_alt_outlined),
                      label: const Text('Quản lý địa chỉ'),
                    ),
                  ),
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
                  onPressed: _continueToSummary,
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

  String _formatVnd(num value) => '${value.toStringAsFixed(0)} đ';
}

class _OrderFormData {
  const _OrderFormData({required this.prices, required this.addresses});

  final List<LaundryPriceOption> prices;
  final List<CustomerAddress> addresses;
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
          '${item.price.unitPriceVnd.toStringAsFixed(0)} đ/${item.price.unitSymbol}',
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
  const _EstimateRow({required this.totalMinorUnits});

  final int totalMinorUnits;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text('Tạm tính'),
        Text(
          '${(totalMinorUnits / 100).toStringAsFixed(0)} đ',
          style: AppTypography.title.copyWith(color: AppColors.primary),
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
