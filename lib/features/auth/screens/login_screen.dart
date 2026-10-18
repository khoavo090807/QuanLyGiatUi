import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_quanly_giaiui/core/constants/app_strings.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/theme/app_typography.dart';
import 'package:app_quanly_giaiui/features/auth/data/auth_repository.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isStaffLogin = false;
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _loginError;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_emailController.text.trim().isEmpty ||
        _passwordController.text.isEmpty) {
      setState(
        () => _loginError = _isStaffLogin
            ? 'Nhập gmail và mật khẩu do quản trị viên cấp.'
            : 'Vui lòng nhập gmail và mật khẩu.',
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _loginError = null;
    });
    try {
      final repository = AuthRepository();
      await repository.signInWithPassword(
        email: _emailController.text,
        password: _passwordController.text,
      );
      await repository.ensureCustomerProfile();
      final roles = await repository.getCurrentRoles();
      final isStaff = roles.any(
        {'Nhân viên', 'Quản lý', 'Chủ cửa hàng'}.contains,
      );
      if (_isStaffLogin && !isStaff) {
        await repository.signOut();
        throw const AuthException(
          'Tài khoản chưa được cấp vai trò nhân viên hoặc quản lý.',
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() => _loginError = _loginErrorMessage(error));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _loginErrorMessage(Object error) {
    if (error is AuthException) {
      if (error.message.toLowerCase().contains('invalid login credentials')) {
        return 'Tài khoản hoặc mật khẩu không đúng.';
      }
      return error.message;
    }
    return 'Không thể đăng nhập. Vui lòng thử lại.';
  }

  Future<void> _loginWithGoogle() async {
    setState(() => _isLoading = true);
    try {
      await AuthRepository().signInWithGoogle();
    } catch (error) {
      if (mounted) {
        final message = error is AuthException
            ? error.message
            : 'Không thể đăng nhập. Vui lòng thử lại.';
        _showMessage(message);
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.local_laundry_service_rounded, size: 80, color: AppColors.primary),
                const SizedBox(height: 24),
                Text(AppStrings.login, style: AppTypography.heading1, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  _isStaffLogin
                      ? 'Dành cho nhân viên, quản lý và chủ cửa hàng.'
                      : 'Đăng nhập bằng gmail và mật khẩu hoặc tài khoản Google.',
                  style: AppTypography.bodyText.copyWith(color: AppColors.textSecondary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 28),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      icon: Icon(Icons.account_circle_outlined),
                      label: Text('Khách hàng'),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      icon: Icon(Icons.badge_outlined),
                      label: Text('Nhân viên'),
                    ),
                  ],
                  selected: {_isStaffLogin},
                  onSelectionChanged: (selection) {
                    setState(() {
                      _isStaffLogin = selection.first;
                      _loginError = null;
                    });
                  },
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  onChanged: (_) {
                    if (_loginError != null) {
                      setState(() => _loginError = null);
                    }
                  },
                  decoration: const InputDecoration(
                    labelText: 'Gmail tài khoản',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  onChanged: (_) {
                    if (_loginError != null) {
                      setState(() => _loginError = null);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: AppStrings.password,
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                    ),
                  ),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (_loginError != null)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Text(
                            _loginError!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.caption.copyWith(
                              color: AppColors.error,
                            ),
                          ),
                        ),
                      )
                    else
                      const Spacer(),
                    TextButton(
                      onPressed: () =>
                          context.pushNamed(AppRoutes.forgotPassword),
                      child: const Text('Quên mật khẩu?'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _login,
                  icon: _isLoading
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.login, size: 24),
                  label: const Text('Đăng nhập tài khoản'),
                ),
                if (!_isStaffLogin)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: OutlinedButton.icon(
                      onPressed: _isLoading ? null : _loginWithGoogle,
                      icon: const Icon(Icons.g_mobiledata, size: 30),
                      label: const Text('Tiếp tục với Google'),
                    ),
                  ),
                if (!_isStaffLogin) ...[
                  const SizedBox(height: 16),
                  Text(
                    'Tài khoản khách hàng mới sẽ được tạo tự động sau khi xác thực Google.',
                    textAlign: TextAlign.center,
                    style: AppTypography.caption,
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(AppStrings.noAccount, style: AppTypography.bodyText),
                    TextButton(
                      onPressed: () => context.pushNamed(AppRoutes.register),
                      child: const Text(AppStrings.register),
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
