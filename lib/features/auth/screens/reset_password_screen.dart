import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/core/utils/validator_utils.dart';
import 'package:app_quanly_giaiui/features/auth/data/auth_repository.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isSaving = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;
  bool _isCheckingRecoveryLink = true;
  bool _hasRecoverySession = false;
  String? _recoveryAccountName;
  String? _recoveryAccountEmail;
  String? _errorMessage;
  StreamSubscription<AuthState>? _authSubscription;
  Timer? _recoveryCheckTimeout;

  @override
  void initState() {
    super.initState();
    final auth = Supabase.instance.client.auth;
    _hasRecoverySession = auth.currentSession != null;
    _isCheckingRecoveryLink = !_hasRecoverySession;
    _setRecoveryAccount(auth.currentUser);

    // The app link can open this route a moment before Supabase finishes
    // exchanging its one-time code for a recovery session. Listen for that
    // event so we don't incorrectly show the expired-link screen meanwhile.
    _authSubscription = auth.onAuthStateChange.listen(
      (state) {
        if (state.event == AuthChangeEvent.passwordRecovery && mounted) {
          _recoveryCheckTimeout?.cancel();
          setState(() {
            _hasRecoverySession = state.session != null;
            _isCheckingRecoveryLink = false;
            _setRecoveryAccount(state.session?.user);
          });
        }
      },
      onError: (Object _) => _finishRecoveryCheck(),
    );

    if (_isCheckingRecoveryLink) {
      _recoveryCheckTimeout = Timer(
        const Duration(seconds: 10),
        _finishRecoveryCheck,
      );
    }
  }

  void _finishRecoveryCheck() {
    if (!mounted || !_isCheckingRecoveryLink) return;
    _recoveryCheckTimeout?.cancel();
    setState(() {
      _hasRecoverySession =
          Supabase.instance.client.auth.currentSession != null;
      _isCheckingRecoveryLink = false;
      _setRecoveryAccount(Supabase.instance.client.auth.currentUser);
    });
  }

  void _setRecoveryAccount(User? user) {
    final metadata = user?.userMetadata;
    _recoveryAccountName = metadata?['full_name'] as String? ??
        metadata?['name'] as String?;
    _recoveryAccountEmail = user?.email;
  }

  @override
  void dispose() {
    _recoveryCheckTimeout?.cancel();
    _authSubscription?.cancel();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _savePassword() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final repository = AuthRepository();
      await repository.updatePassword(_passwordController.text);
      await repository.signOut();
      if (mounted) context.goNamed(AppRoutes.login);
    } catch (error) {
      if (mounted) {
        setState(() {
          _errorMessage = error is AuthException
              ? error.message
              : 'Không thể cập nhật mật khẩu. Hãy yêu cầu liên kết mới.';
        });
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasRecoverySession = _hasRecoverySession;
    return Scaffold(
      appBar: AppBar(title: const Text('Đặt mật khẩu mới')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.lock_reset_outlined,
                    size: 56,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _isCheckingRecoveryLink
                        ? 'Đang xác minh liên kết đặt lại mật khẩu...'
                        : hasRecoverySession
                        ? 'Tạo mật khẩu mới cho tài khoản của bạn.'
                        : 'Liên kết không hợp lệ hoặc đã hết hạn.',
                    style: AppTypography.bodyText,
                    textAlign: TextAlign.center,
                  ),
                  if (_isCheckingRecoveryLink) ...[
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator()),
                  ] else if (hasRecoverySession) ...[
                    const SizedBox(height: 24),
                    _RecoveryAccountCard(
                      name: _recoveryAccountName,
                      email: _recoveryAccountEmail,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu mới',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscurePassword
                              ? 'Hiện mật khẩu'
                              : 'Ẩn mật khẩu',
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: ValidatorUtils.validatePassword,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirmation,
                      decoration: InputDecoration(
                        labelText: 'Xác nhận mật khẩu mới',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          tooltip: _obscureConfirmation
                              ? 'Hiện mật khẩu'
                              : 'Ẩn mật khẩu',
                          onPressed: () => setState(
                            () => _obscureConfirmation = !_obscureConfirmation,
                          ),
                          icon: Icon(
                            _obscureConfirmation
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) =>
                          ValidatorUtils.validateConfirmPassword(
                            value,
                            _passwordController.text,
                          ),
                    ),
                    if (_errorMessage case final message?) ...[
                      const SizedBox(height: 12),
                      Text(
                        message,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.error,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _savePassword,
                      child: _isSaving
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Lưu mật khẩu mới'),
                    ),
                  ] else ...[
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: () =>
                          context.goNamed(AppRoutes.forgotPassword),
                      child: const Text('Yêu cầu liên kết mới'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RecoveryAccountCard extends StatelessWidget {
  const _RecoveryAccountCard({this.name, this.email});

  final String? name;
  final String? email;

  @override
  Widget build(BuildContext context) {
    final displayName = name?.trim();
    final displayEmail = email?.trim();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primaryLight,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.surface,
            child: Icon(Icons.person_outline, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Đang đặt lại mật khẩu cho',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                if (displayName != null && displayName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(displayName, style: AppTypography.bodyText),
                ],
                if (displayEmail != null && displayEmail.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    displayEmail,
                    style: AppTypography.bodySmall,
                    overflow: TextOverflow.ellipsis,
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
