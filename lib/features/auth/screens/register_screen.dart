import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:app_quanly_giaiui/core/constants/app_strings.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/features/auth/data/auth_repository.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  bool _isVerifying = false;
  bool _obscurePassword = true;
  bool _otpSent = false;
  int _resendSeconds = 0;
  DateTime? _resendAvailableAt;
  Timer? _resendTimer;
  String? _errorMessage;
  String? _registrationError;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();

  @override
  void dispose() {
    _resendTimer?.cancel();
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _otp.dispose();
    super.dispose();
  }

  Future<void> _registerWithEmail() async {
    if (_isLoading || _resendSeconds > 0) return;
    if (_name.text.trim().isEmpty ||
        !_email.text.contains('@') ||
        _password.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nhập họ tên, Gmail hợp lệ và mật khẩu tối thiểu 6 ký tự.',
          ),
        ),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final registered = await AuthRepository().signUpCustomer(
        fullName: _name.text,
        email: _email.text,
        password: _password.text,
      );
      if (!mounted) return;
      if (!registered) {
        setState(() {
          _registrationError =
              'Tài khoản Gmail này đã đăng ký. Vui lòng đăng nhập.';
        });
        return;
      }
      setState(() {
        _registrationError = null;
        _errorMessage = null;
        _otpSent = true;
        _resendAvailableAt = DateTime.now().add(const Duration(minutes: 3));
      });
      _startResendTimer();
    } catch (error) {
      if (mounted) {
        final retryAfter = _signupRetryAfterSeconds(error);
        setState(() {
          if (retryAfter != null) {
            _resendAvailableAt = DateTime.now().add(
              Duration(seconds: retryAfter),
            );
            _errorMessage =
                'Mã OTP đã gửi vẫn còn hiệu lực. Vui lòng chờ rồi thử đăng ký lại.';
          } else {
            _errorMessage = 'Không thể đăng ký: $error';
          }
        });
        if (retryAfter != null) _startResendTimer();
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int? _signupRetryAfterSeconds(Object error) {
    final match = RegExp(
      r'only request this after\s+(\d+)\s+seconds?',
      caseSensitive: false,
    ).firstMatch(error.toString());
    return int.tryParse(match?.group(1) ?? '');
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

  Future<void> _resendSignupOtp() async {
    if (_isLoading || _resendSeconds > 0) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await AuthRepository().resendSignupConfirmationOtp(_email.text);
      if (!mounted) return;
      setState(() {
        _otp.clear();
        _resendAvailableAt = DateTime.now().add(const Duration(minutes: 3));
      });
      _startResendTimer();
    } catch (_) {
      if (mounted) {
        setState(
          () => _errorMessage =
              'Chưa thể gửi lại mã. Hãy chờ mã hiện tại hết hạn rồi thử lại.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _verifySignupOtp() async {
    final token = _otp.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(token)) {
      setState(() => _errorMessage = 'Nhập mã OTP gồm 6 chữ số.');
      return;
    }
    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });
    try {
      await AuthRepository().verifySignupOtp(email: _email.text, token: token);
      if (mounted) context.go(AppRoutes.splashPath);
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
      appBar: AppBar(),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(AppStrings.register, style: AppTypography.heading1),
                const SizedBox(height: 8),
                Text(
                  _otpSent
                      ? 'Nhập mã OTP đã gửi đến Gmail để xác minh tài khoản. Mã có hiệu lực trong 3 phút.'
                      : 'Tạo tài khoản bằng Gmail và mật khẩu.',
                  style: AppTypography.bodyText.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 28),
                if (!_otpSent) ...[
                  TextField(
                    controller: _name,
                    onChanged: (_) {
                      if (_registrationError != null) {
                        setState(() => _registrationError = null);
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'Họ và tên',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _email,
                    keyboardType: TextInputType.emailAddress,
                    onChanged: (_) {
                      if (_registrationError != null) {
                        setState(() => _registrationError = null);
                      }
                    },
                    decoration: const InputDecoration(
                      labelText: 'Gmail',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: _obscurePassword,
                    onChanged: (_) {
                      if (_registrationError != null) {
                        setState(() => _registrationError = null);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Mật khẩu',
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
                  ),
                ] else ...[
                  const Icon(
                    Icons.mark_email_read_outlined,
                    size: 48,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _email.text.trim(),
                    style: AppTypography.bodyText,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
                  Form(
                    key: _formKey,
                    child: TextFormField(
                      controller: _otp,
                      keyboardType: TextInputType.number,
                      textInputAction: TextInputAction.done,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                  ),
                ],
                if (_registrationError != null) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(
                      _registrationError!,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.error,
                      ),
                    ),
                  ),
                ],
                if (_errorMessage case final message?) ...[
                  const SizedBox(height: 8),
                  Text(
                    message,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                if (!_otpSent)
                  ElevatedButton(
                    onPressed: _isLoading || _resendSeconds > 0
                        ? null
                        : _registerWithEmail,
                    child: _isLoading
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            _resendSeconds > 0
                                ? 'Đăng ký lại sau ${_formatRemainingTime()}'
                                : 'Đăng ký bằng Gmail',
                          ),
                  )
                else ...[
                  ElevatedButton(
                    onPressed: _isVerifying ? null : _verifySignupOtp,
                    child: _isVerifying
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Xác minh và tạo tài khoản'),
                  ),
                  TextButton(
                    onPressed: _isLoading || _resendSeconds > 0
                        ? null
                        : _resendSignupOtp,
                    child: _isLoading
                        ? const Text('Đang gửi mã OTP...')
                        : Text(
                            _resendSeconds > 0
                                ? 'Gửi lại mã sau ${_formatRemainingTime()}'
                                : 'Gửi lại mã OTP',
                          ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(AppStrings.haveAccount, style: AppTypography.bodyText),
                    TextButton(
                      onPressed: () => context.pop(),
                      child: const Text(AppStrings.login),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
