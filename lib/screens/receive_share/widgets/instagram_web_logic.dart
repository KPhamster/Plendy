// instagram_web_logic.dart
import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'package:flutter/widgets.dart'; // For HtmlElementView

// This function will encapsulate the web-specific parts of initState
void registerInstagramViewFactory(String viewType, String htmlSrcDoc) {
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
Widget buildInstagramWebViewForWeb(String viewType) {
  return AspectRatio(
    aspectRatio: 9 / 16,
    child: HtmlElementView(viewType: viewType),
  );
} 