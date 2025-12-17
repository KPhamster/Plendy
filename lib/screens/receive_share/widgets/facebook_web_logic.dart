// facebook_web_logic.dart
import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'package:flutter/widgets.dart'; // For HtmlElementView

/// Register a view factory for Facebook oEmbed content on web
/// 
/// [viewType] - Unique identifier for this view factory
/// [htmlSrcDoc] - The full HTML document to render in the iframe
void registerFacebookViewFactory(String viewType, String htmlSrcDoc) {
  ui_web.platformViewRegistry.registerViewFactory(
    viewType,
    (int viewId) => html.IFrameElement()
      ..srcdoc = htmlSrcDoc
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.border = 'none'
      ..allow = 'autoplay; clipboard-write; encrypted-media; picture-in-picture; web-share'
      // Sandbox with permissions needed for Facebook SDK to work
      ..setAttribute('sandbox', 'allow-scripts allow-same-origin allow-popups allow-forms allow-presentation')
      ..setAttribute('allowfullscreen', 'false'),
  );
}

/// Build the web-specific widget for Facebook oEmbed content
/// 
/// [viewType] - The view type registered with registerFacebookViewFactory
Widget buildFacebookWebViewForWeb(String viewType) {
  return HtmlElementView(viewType: viewType);
}
