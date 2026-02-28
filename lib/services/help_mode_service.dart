import 'package:flutter/foundation.dart';

/// Global help-mode state shared across main tab screens.
class HelpModeService {
  HelpModeService._();

  static final ValueNotifier<bool> _isActive = ValueNotifier<bool>(false);

  static ValueListenable<bool> get listenable => _isActive;
  static bool get isActive => _isActive.value;

  static void setActive(bool active) {
    if (_isActive.value == active) return;
    _isActive.value = active;
  }
}
