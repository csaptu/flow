import 'package:dio/dio.dart';
import 'package:flow_models/flow_models.dart';
import 'api_client.dart';

/// Authentication service
class AuthService {
  final FlowApiClient _client;

  AuthService(this._client);

  Dio get _dio => _client.sharedClient;

  /// Register a new user
  Future<AuthResponse> register({
    required String email,
    required String password,
    required String name,
  }) async {
    final response = await _dio.post('/auth/register', data: {
      'email': email,
      'password': password,
      'name': name,
    });

    if (response.data['success'] == true) {
      final authResponse = AuthResponse.fromJson(response.data['data']);
      await _client.setTokens(
        authResponse.accessToken,
        authResponse.refreshToken,
      );
      return authResponse;
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Login with email and password
  Future<AuthResponse> login({
    required String email,
    required String password,
  }) async {
    final response = await _dio.post('/auth/login', data: {
      'email': email,
      'password': password,
    });

    print('[AuthService] Login response: ${response.data}');

    if (response.data['success'] == true) {
      final authResponse = AuthResponse.fromJson(response.data['data']);
      print('[AuthService] Parsed tokens - access: ${authResponse.accessToken.substring(0, 20)}...');
      await _client.setTokens(
        authResponse.accessToken,
        authResponse.refreshToken,
      );
      print('[AuthService] Tokens stored');
      return authResponse;
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Dev login (no password required for whitelisted accounts)
  Future<AuthResponse> devLogin({required String email}) async {
    final response = await _dio.post('/auth/dev-login', data: {
      'email': email,
    });

    if (response.data['success'] == true) {
      final authResponse = AuthResponse.fromJson(response.data['data']);
      await _client.setTokens(
        authResponse.accessToken,
        authResponse.refreshToken,
      );
      return authResponse;
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Get current user
  Future<User> getCurrentUser() async {
    final response = await _dio.get('/auth/me');

    if (response.data['success'] == true) {
      return User.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Update current user's profile
  Future<User> updateProfile({
    String? name,
    String? avatarUrl,
  }) async {
    final data = <String, dynamic>{};
    if (name != null) data['name'] = name;
    if (avatarUrl != null) data['avatar_url'] = avatarUrl;

    final response = await _dio.put('/auth/me', data: data);

    if (response.data['success'] == true) {
      return User.fromJson(response.data['data']);
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Logout
  Future<void> logout() async {
    try {
      await _dio.post('/auth/logout');
    } catch (_) {
      // Ignore logout errors
    }
    await _client.logout();
  }

  /// Login with Google
  Future<AuthResponse> loginWithGoogle(String idToken) async {
    final response = await _dio.post('/auth/google', data: {
      'id_token': idToken,
    });

    if (response.data['success'] == true) {
      final authResponse = AuthResponse.fromJson(response.data['data']);
      await _client.setTokens(
        authResponse.accessToken,
        authResponse.refreshToken,
      );
      return authResponse;
    }

    throw ApiException.fromResponse(response.data);
  }

  /// Login with Apple
  Future<AuthResponse> loginWithApple(String idToken) async {
    final response = await _dio.post('/auth/apple', data: {
      'id_token': idToken,
    });

    if (response.data['success'] == true) {
      final authResponse = AuthResponse.fromJson(response.data['data']);
      await _client.setTokens(
        authResponse.accessToken,
        authResponse.refreshToken,
      );
      return authResponse;
    }

    throw ApiException.fromResponse(response.data);
  }
}

/// API exception
class ApiException implements Exception {
  final String code;
  final String message;
  final Map<String, dynamic>? details;

  ApiException({
    required this.code,
    required this.message,
    this.details,
  });

  factory ApiException.fromResponse(Map<String, dynamic> response) {
    final error = response['error'] as Map<String, dynamic>?;
    return ApiException(
      code: error?['code'] ?? 'UNKNOWN_ERROR',
      message: error?['message'] ?? 'An unknown error occurred',
      details: error?['details'] as Map<String, dynamic>?,
    );
  }

  @override
  String toString() => 'ApiException: $code - $message';
}
