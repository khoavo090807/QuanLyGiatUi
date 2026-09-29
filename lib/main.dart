import 'package:flutter/material.dart';
import 'package:app_quanly_giaiui/core/constants/app_constants.dart';
import 'package:app_quanly_giaiui/core/config/supabase_config.dart';
import 'package:app_quanly_giaiui/core/navigation/app_router.dart';
import 'package:app_quanly_giaiui/core/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SupabaseConfig.initialize();
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // themeMode: ThemeMode.light, // Ignore dark mode for now
      routerConfig: AppRouter.router,
    );
  }
}
