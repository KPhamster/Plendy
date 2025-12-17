// facebook_web_logic_stub.dart
// Stub file for non-web platforms
import 'package:flutter/widgets.dart';

/// No-op on non-web platforms
void registerFacebookViewFactory(String viewType, String htmlSrcDoc) {
  // No-op on mobile/desktop platforms
}

/// Returns a placeholder widget on non-web platforms
Widget buildFacebookWebViewForWeb(String viewType) {
  return const SizedBox.shrink();
}
