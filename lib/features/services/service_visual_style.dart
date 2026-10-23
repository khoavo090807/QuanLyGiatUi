import 'package:flutter/material.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/features/order/data/order_repository.dart';

class ServiceVisualStyle {
  const ServiceVisualStyle({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  Color get backgroundColor => color.withValues(alpha: 0.12);

  static ServiceVisualStyle forService(LaundryPriceOption service) {
    return _forLabel(service.serviceTypeName) ??
        _forLabel(service.serviceName) ??
        const ServiceVisualStyle(
          icon: Icons.local_laundry_service_outlined,
          color: AppColors.info,
        );
  }

  static ServiceVisualStyle? _forLabel(String? label) {
    final normalized = label?.trim().toLowerCase() ?? '';
    if (normalized.contains('sấy')) {
      return const ServiceVisualStyle(
        icon: Icons.air_outlined,
        color: AppColors.success,
      );
    }
    if (normalized.contains('khô')) {
      return const ServiceVisualStyle(
        icon: Icons.dry_cleaning_outlined,
        color: AppColors.primary,
      );
    }
    if (normalized.contains('tẩy')) {
      return const ServiceVisualStyle(
        icon: Icons.cleaning_services_outlined,
        color: AppColors.secondary,
      );
    }
    if (normalized.contains('ủi')) {
      return const ServiceVisualStyle(
        icon: Icons.iron_outlined,
        color: AppColors.warning,
      );
    }
    if (normalized.contains('giặt')) {
      return const ServiceVisualStyle(
        icon: Icons.water_drop_outlined,
        color: AppColors.accent,
      );
    }
    return null;
  }
}
