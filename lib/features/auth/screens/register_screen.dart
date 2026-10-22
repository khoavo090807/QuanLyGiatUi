import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:app_quanly_giaiui/core/constants/app_strings.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/features/auth/data/auth_repository.dart';

String? _pendingSignupName;
String? _pendingSignupEmail;
DateTime? _pendingSignupResendAt;

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
  String? _infoMessage;
  String? _registrationError;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _otp = TextEditingController();

  @override
  void initState() {
    super.initState();
    final email = _pendingSignupEmail;
    if (email != null) {
      _name.text = _pendingSignupName ?? '';
      _email.text = email;
      _otpSent = true;
      _resendAvailableAt = _pendingSignupResendAt;
      _startResendTimer();
    }
  }

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
    if (_isLoading || (_otpSent && _resendSeconds > 0)) return;
    if (_name.text.trim().isEmpty ||
        !_email.text.contains('@') ||
        _password.text.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nhập họ tên, Email hợp lệ và mật khẩu tối thiểu 6 ký tự.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _infoMessage = null;
      _registrationError = null;
    });
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
              'Tài khoản Email này đã đăng ký. Vui lòng đăng nhập.';
        });
        return;
      }
      setState(() {
        _registrationError = null;
        _errorMessage = null;
        _infoMessage = null;
        _otpSent = true;
        _resendAvailableAt = DateTime.now().add(const Duration(minutes: 3));
      });
      _rememberPendingSignup();
      _startResendTimer();
    } catch (error) {
      if (mounted) {
        final retryAfter = _signupRetryAfterSeconds(error);
        setState(() {
          if (retryAfter != null) {
            _resendAvailableAt = DateTime.now().add(
              Duration(seconds: retryAfter),
            );
            final pendingEmail = _pendingSignupEmail;
            final hasPendingOtp = pendingEmail == null ||
                pendingEmail.toLowerCase() == _email.text.trim().toLowerCase();
            if (hasPendingOtp) {
              _otpSent = true;
              _rememberPendingSignup();
              _infoMessage =
                  'Mã OTP đã được gửi và vẫn còn hiệu lực. Hãy kiểm tra email rồi nhập mã bên dưới. Bạn có thể yêu cầu mã mới sau khi hết thời gian chờ.';
            } else {
              _resendAvailableAt = _pendingSignupResendAt;
              _infoMessage = _pendingSignupResendAt?.isAfter(DateTime.now()) ==
                      true
                  ? 'Chưa thể gửi mã mới lúc này. Mã đã gửi đến $pendingEmail vẫn còn hiệu lực; bạn có thể tiếp tục nhập mã đó.'
                  : 'Chưa thể gửi mã mới lúc này. Vui lòng chờ rồi thử lại.';
            }
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

  void _rememberPendingSignup() {
    _pendingSignupName = _name.text.trim();
    _pendingSignupEmail = _email.text.trim();
    _pendingSignupResendAt = _resendAvailableAt;
  }

  void _clearPendingSignup() {
    _pendingSignupName = null;
    _pendingSignupEmail = null;
    _pendingSignupResendAt = null;
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
      setState(() {
        _resendSeconds = seconds > 0 ? seconds : 0;
        if (_resendSeconds == 0) {
          if (_otpSent) {
            _otpSent = false;
            _otp.clear();
          }
          _resendAvailableAt = null;
          _infoMessage = null;
          _clearPendingSignup();
        }
      });
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
      _infoMessage = null;
    });
    try {
      await AuthRepository().resendSignupConfirmationOtp(_email.text);
      if (!mounted) return;
      setState(() {
        _otp.clear();
        _resendAvailableAt = DateTime.now().add(const Duration(minutes: 3));
      });
      _rememberPendingSignup();
      _startResendTimer();
    } catch (error) {
      if (mounted) {
        final retryAfter = _signupRetryAfterSeconds(error);
        setState(() {
          if (retryAfter != null) {
            _resendAvailableAt = DateTime.now().add(
              Duration(seconds: retryAfter),
            );
            _rememberPendingSignup();
            _infoMessage =
                'Mã OTP đã được gửi và vẫn còn hiệu lực. Hãy kiểm tra email rồi nhập mã bên dưới. Bạn có thể yêu cầu mã mới sau khi hết thời gian chờ.';
          } else {
            _errorMessage =
                'Chưa thể gửi lại mã. Hãy chờ mã hiện tại hết hạn rồi thử lại.';
          }
        });
        if (retryAfter != null) _startResendTimer();
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
      _clearPendingSignup();
      if (mounted) {
        context.go(AppRoutes.splashPath);
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
                      ? (_resendSeconds > 0
                          ? 'Nhập mã OTP đã gửi đến Email để xác minh tài khoản. Mã có hiệu lực trong 3 phút.'
                          : 'Mã OTP đã hết thời gian hiệu lực. Nhập thông tin để đăng ký và nhận mã mới.')
                      : 'Tạo tài khoản bằng Email và mật khẩu.',
                  style: AppTypography.bodyText.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 28),
                if (_infoMessage case final message?) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: message.startsWith('Chưa thể gửi mã mới lúc này')
                          ? AppColors.errorLight
                          : AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      message,
                      style: AppTypography.bodySmall.copyWith(
                        color: message.startsWith(
                          'Chưa thể gửi mã mới lúc này',
                        )
                            ? AppColors.error
                            : AppColors.primary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
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
                      labelText: 'Email',
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
                    onPressed: _isLoading || (_otpSent && _resendSeconds > 0)
                        ? null
                        : _registerWithEmail,
                    child: _isLoading
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Đăng ký bằng Email'),
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
                  TextButton(
                    onPressed: _isVerifying || _isLoading
                        ? null
                        : () => setState(() {
                            _otpSent = false;
                            _otp.clear();
                            _email.clear();
                            _infoMessage = null;
                            _errorMessage = null;
                            _registrationError = null;
                          }),
                    child: const Text('Dùng email khác'),
                  ),
                ],
                if (!_otpSent && _pendingSignupEmail != null)
                  TextButton(
                    onPressed: () => setState(() {
                      _name.text = _pendingSignupName ?? '';
                      _email.text = _pendingSignupEmail!;
                      _otpSent = true;
                      _infoMessage = null;
                      _errorMessage = null;
                      _resendAvailableAt = _pendingSignupResendAt;
                      _startResendTimer();
                    }),
                    child: const Text('Tiếp tục nhập mã OTP đã nhận'),
                  ),
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
