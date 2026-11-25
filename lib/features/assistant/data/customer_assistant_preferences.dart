import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CustomerAssistantPreferences {
  CustomerAssistantPreferences._();

  static final enabled = ValueNotifier<bool>(true);
  static String _userId = 'guest';

  static Future<void> load(String? userId) async {
    _userId = userId ?? 'guest';
    final preferences = await SharedPreferences.getInstance();
    enabled.value = preferences.getBool(_enabledKey) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    enabled.value = value;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool(_enabledKey, value);
  }

  static Future<Offset?> loadPosition() async {
    final preferences = await SharedPreferences.getInstance();
    final x = preferences.getDouble(_xKey);
    final y = preferences.getDouble(_yKey);
    return x == null || y == null ? null : Offset(x, y);
  }

  static Future<void> savePosition(Offset position) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setDouble(_xKey, position.dx);
    await preferences.setDouble(_yKey, position.dy);
  }

  static String get _enabledKey => 'customer_ai_enabled_$_userId';
  static String get _xKey => 'customer_ai_x_$_userId';
  static String get _yKey => 'customer_ai_y_$_userId';
}
