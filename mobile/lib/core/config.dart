class AppConfig {
  // Development value. Before release, point this at your Render HTTPS API.
  // Example: https://your-service.onrender.com/api
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:5000/api',
  );
}
