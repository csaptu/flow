import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// API Client configuration
class ApiConfig {
  final String sharedServiceUrl;
  final String tasksServiceUrl;
  final String projectsServiceUrl;

  const ApiConfig({
    required this.sharedServiceUrl,
    required this.tasksServiceUrl,
    required this.projectsServiceUrl,
  });

  /// Development configuration
  factory ApiConfig.development() => const ApiConfig(
        sharedServiceUrl: 'http://localhost:8080/api/v1',
        tasksServiceUrl: 'http://localhost:8081/api/v1',
        projectsServiceUrl: 'http://localhost:8082/api/v1',
      );

  /// Production configuration
  factory ApiConfig.production() => const ApiConfig(
        sharedServiceUrl: 'https://api.flowapp.io/shared/v1',
        tasksServiceUrl: 'https://api.flowapp.io/tasks/v1',
        projectsServiceUrl: 'https://api.flowapp.io/projects/v1',
      );
}

/// API Client for Flow services
class FlowApiClient {
  final ApiConfig config;
  final FlutterSecureStorage _storage;

  late final Dio sharedClient;
  late final Dio tasksClient;
  late final Dio projectsClient;

  String? _accessToken;
  String? _refreshToken;

  FlowApiClient({
    required this.config,
    FlutterSecureStorage? storage,
  }) : _storage = storage ?? const FlutterSecureStorage() {
    sharedClient = _createClient(config.sharedServiceUrl);
    tasksClient = _createClient(config.tasksServiceUrl);
    projectsClient = _createClient(config.projectsServiceUrl);
  }

  Dio _createClient(String baseUrl) {
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (_accessToken != null) {
          options.headers['Authorization'] = 'Bearer $_accessToken';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          // Try to refresh token
          final refreshed = await _refreshAccessToken();
          if (refreshed) {
            // Retry request
            final options = error.requestOptions;
            options.headers['Authorization'] = 'Bearer $_accessToken';
            try {
              final response = await dio.fetch(options);
              handler.resolve(response);
              return;
            } catch (e) {
              // Refresh failed, logout
              await logout();
            }
          }
        }
        handler.next(error);
      },
    ));

    return dio;
  }

  /// Initialize from stored tokens
  Future<void> init() async {
    _accessToken = await _storage.read(key: 'access_token');
    _refreshToken = await _storage.read(key: 'refresh_token');
  }

  /// Set tokens after login
  Future<void> setTokens(String accessToken, String refreshToken) async {
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    await _storage.write(key: 'access_token', value: accessToken);
    await _storage.write(key: 'refresh_token', value: refreshToken);
  }

  /// Refresh access token
  Future<bool> _refreshAccessToken() async {
    if (_refreshToken == null) return false;

    try {
      final response = await sharedClient.post(
        '/auth/refresh',
        data: {'refresh_token': _refreshToken},
      );

      if (response.data['success'] == true) {
        await setTokens(
          response.data['data']['access_token'],
          response.data['data']['refresh_token'],
        );
        return true;
      }
    } catch (e) {
      // Refresh failed
    }
    return false;
  }

  /// Check if user is authenticated
  bool get isAuthenticated => _accessToken != null;

  /// Logout and clear tokens
  Future<void> logout() async {
    _accessToken = null;
    _refreshToken = null;
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }
}
