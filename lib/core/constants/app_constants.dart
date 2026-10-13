class AppConstants {
  AppConstants._();

  static const String appName = 'Sky Laundry';
  
  // Storage Keys
  static const String keyToken = 'auth_token';
  static const String keyUserId = 'user_id';
  static const String keyIsFirstAppLaunch = 'is_first_launch';
  
  // Asset Paths
  static const String imagePath = 'assets/images/';
  static const String iconPath = 'assets/icons/';
  static const String lottiePath = 'assets/lottie/';
  
  // API (Placeholder for future)
  static const String baseUrl = 'https://api.skylaundry.vn/v1';
  static const String paymentConfigUrl = String.fromEnvironment(
    'PAYMENT_CONFIG_URL',
    defaultValue: 'https://sky-laundry.vercel.app/api/v1/payment-config',
  );
  
  // Timeout
  static const int connectionTimeout = 30000;
  static const int receiveTimeout = 30000;
}
