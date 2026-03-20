import 'dart:io';

import 'package:flutter/material.dart';

bool _looksLikeImagePath(String p) {
  final l = p.toLowerCase();
  return l.endsWith('.png') ||
      l.endsWith('.jpg') ||
      l.endsWith('.jpeg') ||
      l.endsWith('.gif') ||
      l.endsWith('.webp') ||
      l.endsWith('.heic') ||
      l.endsWith('.heif');
}

/// Renders [Image.file] when [path] is a readable local image file.
Widget? tryBuildLocalSharedMediaImage(String path, {BoxFit fit = BoxFit.cover}) {
  if (path.isEmpty) return null;
  if (path.startsWith('http://') || path.startsWith('https://')) return null;
  if (!_looksLikeImagePath(path)) return null;
  final file = File(path);
  if (!file.existsSync()) return null;
  return Image.file(
    file,
    fit: fit,
    errorBuilder: (context, error, stackTrace) {
      return Center(
        child: Icon(Icons.broken_image_outlined, color: Colors.grey.shade600),
      );
    },
  );
}
