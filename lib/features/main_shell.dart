import 'package:flutter/material.dart';
import 'package:app_quanly_giaiui/core/constants/app_strings.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/features/auth/data/auth_repository.dart';
import 'package:app_quanly_giaiui/features/history/screens/history_screen.dart';
import 'package:app_quanly_giaiui/features/home/screens/home_screen.dart';
import 'package:app_quanly_giaiui/features/notification/screens/notification_screen.dart';
import 'package:app_quanly_giaiui/features/profile/screens/profile_screen.dart';
import 'package:app_quanly_giaiui/features/staff/screens/staff_order_queue_screen.dart';

class MainShell extends StatefulWidget {
  final int initialIndex;

  const MainShell({super.key, this.initialIndex = 0});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final _authRepository = AuthRepository();
  late Future<List<String>> _rolesFuture;
  late int _selectedIndex;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialIndex;
    _rolesFuture = _authRepository.getCurrentRoles();
  }

  bool _hasStaffRole(List<String> roles) => roles.any(
        {'Nhân viên', 'Quản lý', 'Chủ cửa hàng'}.contains,
      );

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<String>>(
      future: _rolesFuture,
      builder: (context, snapshot) {
        final roles = snapshot.data ?? const <String>[];
        final isStaff = _hasStaffRole(roles);
        final selectedIndex = isStaff
            ? (_selectedIndex.clamp(0, 2))
            : (_selectedIndex.clamp(0, 3));

        final screens = isStaff
            ? const [
                StaffOrderQueueScreen(),
                NotificationScreen(),
                ProfileScreen(),
              ]
            : const [
                HomeScreen(),
                HistoryScreen(),
                NotificationScreen(),
                ProfileScreen(),
              ];

        final destinations = isStaff
            ? const [
                NavigationDestination(
                  icon: Icon(Icons.fact_check_outlined),
                  selectedIcon: Icon(Icons.fact_check, color: AppColors.primary),
                  label: 'Đơn hàng',
                ),
                NavigationDestination(
                  icon: Icon(Icons.notifications_outlined),
                  selectedIcon: Icon(Icons.notifications, color: AppColors.primary),
                  label: AppStrings.notifications,
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person, color: AppColors.primary),
                  label: AppStrings.profile,
                ),
              ]
            : const [
                NavigationDestination(
                  icon: Icon(Icons.home_outlined),
                  selectedIcon: Icon(Icons.home, color: AppColors.primary),
                  label: AppStrings.home,
                ),
                NavigationDestination(
                  icon: Icon(Icons.receipt_long_outlined),
                  selectedIcon: Icon(Icons.receipt_long, color: AppColors.primary),
                  label: AppStrings.history,
                ),
                NavigationDestination(
                  icon: Icon(Icons.notifications_outlined),
                  selectedIcon: Icon(Icons.notifications, color: AppColors.primary),
                  label: AppStrings.notifications,
                ),
                NavigationDestination(
                  icon: Icon(Icons.person_outline),
                  selectedIcon: Icon(Icons.person, color: AppColors.primary),
                  label: AppStrings.profile,
                ),
              ];

        return Scaffold(
          body: IndexedStack(
            index: selectedIndex,
            children: screens,
          ),
          bottomNavigationBar: Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  offset: const Offset(0, -5),
                ),
              ],
            ),
            child: SafeArea(
              child: NavigationBar(
                selectedIndex: selectedIndex,
                onDestinationSelected: (index) {
                  setState(() => _selectedIndex = index);
                },
                backgroundColor: AppColors.surface,
                indicatorColor: AppColors.primaryLight,
                destinations: destinations,
              ),
            ),
          ),
        );
      },
    );
  }
}
