@JS()
library google_sign_in_web_helper;

import 'dart:async';
import 'dart:html' as html;
import 'package:js/js.dart';

@JS('google.accounts.oauth2.initTokenClient')
external GoogleTokenClient _initTokenClient(TokenClientConfig config);

@JS()
@anonymous
abstract class TokenClientConfig {
  external factory TokenClientConfig({
    String client_id,
    String scope,
    Function callback,
    Function? error_callback,
  });
}

@JS()
@anonymous
abstract class GoogleTokenClient {
  external void requestAccessToken([OverridableTokenClientConfig? config]);
}

@JS()
@anonymous
abstract class OverridableTokenClientConfig {
  external factory OverridableTokenClientConfig({
    String? prompt,
  });
}

@JS()
@anonymous
abstract class TokenResponse {
  external String? get access_token;
  external String? get error;
  external String? get error_description;
}

void _log(String message) {
  html.window.console.log('[GoogleSignInWebHelper] $message');
}

/// Helper class for Google Sign-In on web using Google Identity Services
class GoogleSignInWebHelper {
  static const String _clientId =
      '868169256843-ke0firpbckajqd06adpdc2a1rgo14ejt.apps.googleusercontent.com';

  static Completer<String?>? _activeCompleter;

  /// Trigger Google Sign-In and return the access token
  static Future<String?> signIn() async {
    _log('signIn() called');

    // Cancel any previous pending sign-in
    if (_activeCompleter != null && !_activeCompleter!.isCompleted) {
      _log('Cancelling previous sign-in');
      _activeCompleter!.complete(null);
    }

    final completer = Completer<String?>();
    _activeCompleter = completer;

    try {
      _log('Creating token client');

      final client = _initTokenClient(TokenClientConfig(
        client_id: _clientId,
        scope: 'email profile',
        callback: allowInterop((TokenResponse response) {
          _log('Token callback received');

          if (response.error != null) {
            _log('Error in callback: ${response.error} - ${response.error_description}');
            if (!completer.isCompleted) {
              completer.complete(null);
            }
            return;
          }

          final accessToken = response.access_token;
          if (accessToken != null) {
            _log('Got access token (length: ${accessToken.length})');
            if (!completer.isCompleted) {
              completer.complete(accessToken);
            }
          } else {
            _log('No access token in response');
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          }
        }),
        error_callback: allowInterop((dynamic error) {
          _log('Error callback triggered: $error');
          // Don't complete on error_callback - it might be called for non-fatal errors
          // Only complete if it's a user cancellation
          final errorType = error['type']?.toString() ?? '';
          if (errorType == 'popup_closed' || errorType == 'popup_failed_to_open') {
            _log('Popup closed or failed to open');
            if (!completer.isCompleted) {
              completer.complete(null);
            }
          }
        }),
      ));

      _log('Requesting access token (opening popup)');
      client.requestAccessToken(OverridableTokenClientConfig(prompt: 'select_account'));
      _log('requestAccessToken() called - waiting for callback');

    } catch (e) {
      _log('Exception in signIn: $e');
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }

    return completer.future;
  }
}
