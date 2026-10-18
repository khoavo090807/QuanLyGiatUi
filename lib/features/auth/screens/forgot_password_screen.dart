import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:app_quanly_giaiui/core/constants/app_strings.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/core/utils/validator_utils.dart';
import 'package:app_quanly_giaiui/features/auth/data/auth_repository.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  bool _isSending = false;
  bool _isVerifying = false;
  bool _otpSent = false;
  int _resendSeconds = 0;
  DateTime? _resendAvailableAt;
  Timer? _resendTimer;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _resendTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendRecoveryEmail() async {
    if (_isSending || _resendSeconds > 0) return;
    if (!_otpSent && !(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isSending = true;
      _errorMessage = null;
    });
    try {
      await AuthRepository().requestPasswordReset(_emailController.text);
      if (!mounted) return;
      setState(() {
        _otpSent = true;
        _otpController.clear();
        _resendAvailableAt = DateTime.now().add(const Duration(minutes: 3));
      });
      _startResendTimer();
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage = 'Không gửi được mã OTP. Vui lòng thử lại sau.',
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    void updateRemaining() {
      if (!mounted) return;
      final seconds =
          _resendAvailableAt?.difference(DateTime.now()).inSeconds ?? 0;
      setState(() => _resendSeconds = seconds > 0 ? seconds : 0);
      if (_resendSeconds == 0) _resendTimer?.cancel();
    }

    updateRemaining();
    _resendTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => updateRemaining(),
    );
  }

  String _formatRemainingTime() {
    final minutes = (_resendSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_resendSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Future<void> _verifyOtp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });
    try {
      await AuthRepository().verifyPasswordResetOtp(
        email: _emailController.text,
        token: _otpController.text,
      );
      if (mounted) {
        context.goNamed(AppRoutes.resetPassword, extra: true);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _errorMessage = 'Mã OTP không đúng hoặc đã hết hạn.');
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.forgotPassword)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Illustration
              Container(
                width: 120,
                height: 120,
                decoration: const BoxDecoration(
                  color: AppColors.primaryLight,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.lock_reset_outlined,
                  size: 60,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 32),

              Text(
                AppStrings.resetPassword,
                style: AppTypography.heading2,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                _otpSent
                    ? 'Nếu gmail thuộc tài khoản hợp lệ, mã OTP đã được gửi. Kiểm tra cả thư mục thư rác. Mã có hiệu lực trong 3 phút.'
                    : 'Nhập gmail tài khoản để nhận mã OTP đặt lại mật khẩu.',
                style: AppTypography.bodyText.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              if (!_otpSent) ...[
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Gmail tài khoản',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Vui lòng nhập gmail.';
                    }
                    return ValidatorUtils.validateEmail(value.trim());
                  },
                ),
              ] else ...[
                const Icon(
                  Icons.mark_email_read_outlined,
                  size: 48,
                  color: AppColors.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  _emailController.text.trim(),
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyText,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Mã OTP 6 chữ số',
                    prefixIcon: Icon(Icons.password_outlined),
                    counterText: '',
                  ),
                  validator: (value) =>
                      value == null ||
                          !RegExp(r'^\d{6}$').hasMatch(value.trim())
                      ? 'Nhập mã OTP gồm 6 chữ số.'
                      : null,
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _isVerifying ? null : _verifyOtp,
                  child: _isVerifying
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Xác minh mã OTP'),
                ),
                TextButton(
                  onPressed: _isSending || _resendSeconds > 0
                      ? null
                      : _sendRecoveryEmail,
                  child: _isSending
                      ? const Text('Đang gửi mã OTP...')
                      : Text(
                          _resendSeconds > 0
                              ? 'Gửi lại mã sau ${_formatRemainingTime()}'
                              : 'Gửi lại mã OTP',
                        ),
                ),
              ],
              if (!_otpSent)
                ElevatedButton(
                  onPressed: _isSending ? null : _sendRecoveryEmail,
                  child: _isSending
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Gửi mã OTP'),
                ),
              if (_errorMessage case final message?) ...[
                const SizedBox(height: 8),
                Text(
                  message,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.error,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              TextButton(
                onPressed: () => context.pop(),
                child: const Text('Quay lại đăng nhập'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
