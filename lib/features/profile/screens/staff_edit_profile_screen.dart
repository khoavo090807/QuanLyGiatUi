import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:app_quanly_giaiui/core/navigation/app_routes.dart';
import 'package:app_quanly_giaiui/core/theme/app_colors.dart';
import 'package:app_quanly_giaiui/core/utils/validator_utils.dart';
import 'package:app_quanly_giaiui/features/auth/data/staff_api_auth_repository.dart';

class StaffEditProfileScreen extends StatefulWidget {
  const StaffEditProfileScreen({super.key});

  @override
  State<StaffEditProfileScreen> createState() => _StaffEditProfileScreenState();
}

class _StaffEditProfileScreenState extends State<StaffEditProfileScreen> {
  final _auth = StaffApiAuthRepository.instance;
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  late Future<Map<String, dynamic>> _profile;
  String? _avatarUrl;
  bool _saving = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _profile = _auth.getProfile();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final image = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 800,
      );
      if (image == null || !mounted) return;
      final extension = image.name.split('.').last.toLowerCase();
      if (!const {'jpg', 'jpeg', 'png', 'webp'}.contains(extension)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chỉ hỗ trợ ảnh JPG, PNG hoặc WebP')),
        );
        return;
      }
      final avatarUrl = await _auth.uploadAvatar(
        await image.readAsBytes(),
        extension,
      );
      if (mounted) setState(() => _avatarUrl = avatarUrl);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể tải ảnh lên: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await _auth.updateProfile(
        name: _name.text,
        phone: _phone.text,
      );
      if (mounted) context.goNamed(AppRoutes.staffQueue, extra: 3);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Không thể cập nhật hồ sơ: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Chỉnh sửa hồ sơ')),
    body: FutureBuilder<Map<String, dynamic>>(
      future: _profile,
      builder: (context, snapshot) {
        final profile = snapshot.data;
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError || profile == null) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Không thể tải hồ sơ nhân viên.'),
                TextButton(
                  onPressed: () => setState(() => _profile = _auth.getProfile()),
                  child: const Text('Thử lại'),
                ),
              ],
            ),
          );
        }
        if (!_loaded) {
          _name.text = profile['name'] as String? ?? '';
          _phone.text = profile['phone'] as String? ?? '';
          _avatarUrl = profile['avatar_url'] as String?;
          _loaded = true;
        }
        return Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 38,
                      backgroundColor: AppColors.primaryLight,
                      backgroundImage: _avatarUrl == null || _avatarUrl!.isEmpty
                          ? null
                          : NetworkImage(_avatarUrl!),
                      child: _avatarUrl == null || _avatarUrl!.isEmpty
                          ? const Icon(
                              Icons.person,
                              size: 42,
                              color: AppColors.primary,
                            )
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Material(
                        color: AppColors.primary,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _saving ? null : _pickAvatar,
                          child: const Padding(
                            padding: EdgeInsets.all(7),
                            child: Icon(
                              Icons.camera_alt,
                              size: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Họ và tên'),
                validator: ValidatorUtils.validateName,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Số điện thoại'),
                validator: ValidatorUtils.validatePhone,
              ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Lưu thay đổi'),
              ),
            ],
          ),
        );
      },
    ),
  );
}
