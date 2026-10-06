import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_quanly_giaiui/features/order/data/order_repository.dart';
import 'package:app_quanly_giaiui/features/order/domain/cart_item.dart';

/// Shared, locally persisted draft cart for a customer's next laundry order.
class CartStore extends ChangeNotifier {
  CartStore._();

  static final CartStore instance = CartStore._();
  static const _storageKey = 'laundry_order_cart_v1';

  final List<CartItem> _items = [];
  Future<void>? _restoreFuture;
  bool _isRestored = false;
  int _unavailableItems = 0;
  final Set<int> _priceChangedPriceIds = {};

  List<CartItem> get items => List.unmodifiable(_items);
  bool get isRestored => _isRestored;
  int get unavailableItems => _unavailableItems;
  int get priceChangedItems => _priceChangedPriceIds.length;
  int get itemCount => _items.length;
  int get subtotalMinorUnits => _items.fold(
    0,
    (total, item) => total + item.estimatedTotalMinorUnits,
  );

  Future<void> restore(List<LaundryPriceOption> activePrices) {
    if (_isRestored) {
      _refreshActivePrices(activePrices);
      return Future<void>.value();
    }
    return _restoreFuture ??= _restore(activePrices);
  }

  void _refreshActivePrices(List<LaundryPriceOption> activePrices) {
    final pricesById = {
      for (final price in activePrices) price.priceId: price,
    };
    var changed = false;
    for (var index = _items.length - 1; index >= 0; index--) {
      final item = _items[index];
      final currentPrice = pricesById[item.price.priceId];
      if (currentPrice == null) {
        _items.removeAt(index);
        _unavailableItems++;
        changed = true;
      } else if (currentPrice.unitPriceVnd != item.price.unitPriceVnd ||
          currentPrice.serviceName != item.price.serviceName ||
          currentPrice.itemTypeName != item.price.itemTypeName) {
        _items[index] = CartItem(
          price: currentPrice,
          measurement: item.measurement,
        );
        if (currentPrice.unitPriceVnd != item.price.unitPriceVnd) {
          _priceChangedPriceIds.add(currentPrice.priceId);
        }
        changed = true;
      }
    }
    if (changed) _changed();
  }

  Future<void> _restore(List<LaundryPriceOption> activePrices) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final rawItems = preferences.getString(_storageKey);
      if (rawItems != null) {
        final decoded = jsonDecode(rawItems);
        if (decoded is List) {
          final pricesById = {
            for (final price in activePrices) price.priceId: price,
          };
          for (final rawItem in decoded) {
            if (rawItem is! Map) continue;
            final priceId = (rawItem['banggiaid'] as num?)?.toInt();
            final measurement = rawItem['measurement'] as num?;
            if (priceId == null || measurement == null || measurement <= 0) {
              continue;
            }
            final price = pricesById[priceId];
            if (price == null) {
              _unavailableItems++;
              continue;
            }
            final previousPrice = rawItem['unitPriceVnd'] as num?;
            if (previousPrice != null &&
                previousPrice != price.unitPriceVnd) {
              _priceChangedPriceIds.add(priceId);
            }
            final existingIndex = _items.indexWhere(
              (item) => item.price.priceId == priceId,
            );
            if (existingIndex == -1) {
              _items.add(CartItem(price: price, measurement: measurement));
            } else {
              final existing = _items[existingIndex];
              _items[existingIndex] = CartItem(
                price: price,
                measurement: existing.measurement + measurement,
              );
            }
          }
        }
      }
    } catch (_) {
      // A damaged local draft should not prevent opening the order flow.
      _items.clear();
    } finally {
      _isRestored = true;
      _restoreFuture = null;
      notifyListeners();
    }
    await _persist();
  }

  void add(CartItem item) {
    assert(_isRestored, 'Restore the cart before changing it.');
    final index = _items.indexWhere(
      (existing) => existing.price.priceId == item.price.priceId,
    );
    if (index == -1) {
      _items.add(item);
    } else {
      final existing = _items[index];
      _items[index] = CartItem(
        price: item.price,
        measurement: existing.measurement + item.measurement,
      );
    }
    _changed();
  }

  void setMeasurement(int index, num measurement) {
    if (index < 0 || index >= _items.length || measurement <= 0) return;
    final item = _items[index];
    _items[index] = CartItem(price: item.price, measurement: measurement);
    _changed();
  }

  void removeAt(int index) {
    if (index < 0 || index >= _items.length) return;
    final removed = _items.removeAt(index);
    _priceChangedPriceIds.remove(removed.price.priceId);
    if (_items.isEmpty) {
      _unavailableItems = 0;
      _priceChangedPriceIds.clear();
    }
    _changed();
  }

  void clear() {
    if (_items.isEmpty &&
        _unavailableItems == 0 &&
        _priceChangedPriceIds.isEmpty) {
      return;
    }
    _items.clear();
    _unavailableItems = 0;
    _priceChangedPriceIds.clear();
    _changed();
  }

  void _changed() {
    notifyListeners();
    _persist();
  }

  Future<void> _persist() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(
        _storageKey,
        jsonEncode(
          _items
              .map(
                (item) => {
                  'banggiaid': item.price.priceId,
                  'measurement': item.measurement,
                  'unitPriceVnd': item.price.unitPriceVnd,
                },
              )
              .toList(),
        ),
      );
    } catch (_) {
      // Cart stays usable for this session if local storage is unavailable.
    }
  }
}
