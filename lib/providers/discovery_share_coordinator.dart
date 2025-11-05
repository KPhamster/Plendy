import 'package:flutter/foundation.dart';

/// Coordinates deep links that should surface a specific discovery preview.
class DiscoveryShareCoordinator extends ChangeNotifier {
  String? _pendingToken;

  /// The token that should be shown in the discovery feed, if any.
  String? get pendingToken => _pendingToken;

  /// Request that the discovery screen highlight the share identified by [token].
  void openSharedToken(String token) {
    if (token.isEmpty) {
      return;
    }
    _pendingToken = token;
    notifyListeners();
  }

  /// Clears the current pending token after it has been handled.
  void clearToken() {
    _pendingToken = null;
  }
}
