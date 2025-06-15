// facebook_web_logic.dart
// This file contains web-specific implementations
import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'package:flutter/widgets.dart';

// This function will encapsulate the web-specific parts of initState
void registerFacebookViewFactory(String viewType, String htmlSrcDoc) {
  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int viewId) => html.IFrameElement()
      ..srcdoc = htmlSrcDoc
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none',
  );
}

// This function will return the web-specific widget
Widget buildFacebookWebViewForWeb(String viewType) {
  return Container(
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFE0E0E0)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: HtmlElementView(viewType: viewType),
    ),
  );
} 