import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app_quanly_giaiui/core/constants/app_strings.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/features/auth/data/auth_repository.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _authRepository = AuthRepository();
  late Future<AuthenticatedProfile?> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = _authRepository.getCurrentProfile();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.profile), elevation: 0),
      body: SingleChildScrollView(
        child: Column(
          children: [
            _buildProfileHeader(context),
            const SizedBox(height: 24),
            _buildMenuSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context) {
    return FutureBuilder<AuthenticatedProfile?>(
      future: _profileFuture,
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final title = snapshot.connectionState == ConnectionState.waiting
            ? 'Đang tải hồ sơ...'
            : profile?.displayName ?? 'Hồ sơ khách hàng';
        final subtitle = profile?.phone ?? profile?.email ?? '';
        final roleText = profile?.roles.isNotEmpty == true
            ? profile!.roles.join(' • ')
            : 'Khách hàng';

        return Container(
          padding: const EdgeInsets.all(20),
          color: AppColors.surface,
          child: Row(
            children: [
              CircleAvatar(
                radius: 35,
                backgroundColor: AppColors.primaryLight,
                child: const Icon(
                  Icons.person,
                  size: 40,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: AppTypography.heading2),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: AppTypography.bodyText.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 6),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        child: Text(
                          roleText,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    if (snapshot.hasError)
                      TextButton(
                        onPressed: () => setState(() {
                          _profileFuture = _authRepository.getCurrentProfile();
                        }),
                        child: const Text('Tải lại hồ sơ'),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMenuSection(BuildContext context) {
    return Column(
      children: [
        _buildMenuGroup([
          _MenuItem(
            icon: Icons.location_on_outlined,
            title: AppStrings.addresses,
              onTap: () => context.pushNamed(AppRoutes.addressBook),
          ),
          _MenuItem(
            icon: Icons.star_outline_rounded,
            title: AppStrings.loyalty,
            onTap: () => context.pushNamed(AppRoutes.loyalty),
          ),
          _MenuItem(
            icon: Icons.card_giftcard_rounded,
            title: AppStrings.vouchers,
            onTap: () => context.pushNamed(AppRoutes.loyalty),
          ),
        ]),
        const SizedBox(height: 16),
        _buildMenuGroup([
          _MenuItem(
            icon: Icons.notifications_active_outlined,
            title: AppStrings.notificationSettings,
            onTap: () {},
          ),
        ]),
        const SizedBox(height: 16),
        _buildMenuGroup([
          _MenuItem(
            icon: Icons.info_outline,
            title: AppStrings.aboutApp,
            onTap: () {},
          ),
          _MenuItem(
            icon: Icons.logout,
            title: AppStrings.logout,
            textColor: AppColors.error,
            isDestructive: true,
            onTap: () => _showLogoutDialog(context),
          ),
        ]),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _buildMenuGroup(List<_MenuItem> items) {
    return Container(
      color: AppColors.surface,
      child: Column(
        children: items.map((item) {
          return ListTile(
            leading: Icon(
              item.icon,
              color: item.isDestructive
                  ? AppColors.error
                  : AppColors.textSecondary,
            ),
            title: Text(
              item.title,
              style: AppTypography.title.copyWith(
                color: item.textColor ?? AppColors.textPrimary,
                fontWeight: item.isDestructive
                    ? FontWeight.w600
                    : FontWeight.normal,
              ),
            ),
            trailing: item.isDestructive
                ? null
                : const Icon(Icons.chevron_right, color: AppColors.border),
            onTap: item.onTap,
          );
        }).toList(),
      ),
    );
  }

  Future<void> _showLogoutDialog(BuildContext context) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Đăng xuất'),
        content: const Text(AppStrings.logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(AppStrings.cancel),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await _authRepository.signOut();
              } catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(content: Text('Không thể đăng xuất: $error')),
                  );
                }
                return;
              }
              if (mounted) this.context.goNamed(AppRoutes.login);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Đăng xuất'),
          ),
        ],
      ),
    );
  }
}

class _MenuItem {
  final IconData icon;
  final String title;
  final Color? textColor;
  final bool isDestructive;
  final VoidCallback onTap;

  _MenuItem({
    required this.icon,
    required this.title,
    this.textColor,
    this.isDestructive = false,
    required this.onTap,
  });
}
