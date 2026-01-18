import 'dart:async';

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
  Completer<bool>? _refreshCompleter;

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
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        final tokenPreview = _accessToken != null ? _accessToken!.substring(0, 20) : 'null';
        print('[API] ${options.method} ${options.path} hasToken=${_accessToken != null} tokenPreview=$tokenPreview clientId=${identityHashCode(this)}');
        if (_accessToken != null) {
          options.headers['Authorization'] = 'Bearer $_accessToken';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        // Don't retry refresh requests to avoid infinite loop
        final path = error.requestOptions.path;

        // Check retry count to prevent infinite loops
        final retryCount = error.requestOptions.extra['retryCount'] ?? 0;
        if (retryCount >= 2) {
          print('[API] Max retries reached for ${error.requestOptions.path}');
          return handler.next(error);
        }

        if (error.response?.statusCode == 401 && !path.contains('/auth/refresh')) {
          // Try to refresh token
          final refreshed = await _refreshAccessToken();
          if (refreshed) {
            // Retry request with incremented retry count
            final options = error.requestOptions;
            options.headers['Authorization'] = 'Bearer $_accessToken';
            options.extra['retryCount'] = retryCount + 1;
            try {
              final response = await dio.fetch(options);
              handler.resolve(response);
              return;
            } catch (e) {
              // Retry failed
              print('[API] Retry failed for ${options.path}: $e');
            }
          }
          // Don't auto-logout here - let the UI layer handle auth state
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
    if (_accessToken != null) {
      print('[ApiClient] init() loaded token from storage, preview: ${_accessToken!.substring(0, 50)}...');
    } else {
      print('[ApiClient] init() no stored token found');
    }
  }

  /// Set tokens after login
  Future<void> setTokens(String accessToken, String refreshToken) async {
    print('[ApiClient] setTokens called on clientId=${identityHashCode(this)}');
    print('[ApiClient] NEW token preview: ${accessToken.substring(0, 50)}...');
    _accessToken = accessToken;
    _refreshToken = refreshToken;
    print('[ApiClient] In-memory token set, preview: ${_accessToken!.substring(0, 50)}...');
    await _storage.write(key: 'access_token', value: accessToken);
    await _storage.write(key: 'refresh_token', value: refreshToken);
    print('[ApiClient] Tokens persisted to storage');
  }

  /// Refresh access token (with lock to prevent concurrent calls)
  Future<bool> _refreshAccessToken() async {
    // If already refreshing, wait for the result
    if (_refreshCompleter != null) {
      print('[API] Waiting for existing refresh to complete');
      return _refreshCompleter!.future;
    }

    if (_refreshToken == null) return false;

    _refreshCompleter = Completer<bool>();
    print('[API] Starting token refresh');

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
        print('[API] Token refresh successful');
        _refreshCompleter!.complete(true);
        return true;
      }
      print('[API] Token refresh failed: response not successful');
      _refreshCompleter!.complete(false);
      return false;
    } catch (e) {
      print('[API] Token refresh failed: $e');
      _refreshCompleter!.complete(false);
      return false;
    } finally {
      _refreshCompleter = null;
    }
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
