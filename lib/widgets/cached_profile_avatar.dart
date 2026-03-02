import 'dart:collection';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../screens/profile_screen.dart' show ProfilePhotoCache;

class CachedProfileAvatar extends StatefulWidget {
  final String? photoUrl;
  final double radius;
  final String? fallbackText;
  final Color? backgroundColor;
  final Color? textColor;

  const CachedProfileAvatar({
    super.key,
    this.photoUrl,
    this.radius = 20,
    this.fallbackText,
    this.backgroundColor,
    this.textColor,
  });

  factory CachedProfileAvatar.fromInitial({
    Key? key,
    String? photoUrl,
    double radius = 20,
    String? displayName,
    String? username,
    Color? backgroundColor,
    Color? textColor,
  }) {
    String? fallback;
    if (displayName != null && displayName.isNotEmpty) {
      fallback = displayName[0].toUpperCase();
    } else if (username != null && username.isNotEmpty) {
      fallback = username[0].toUpperCase();
    }
    return CachedProfileAvatar(
      key: key,
      photoUrl: photoUrl,
      radius: radius,
      fallbackText: fallback,
      backgroundColor: backgroundColor,
      textColor: textColor,
    );
  }

  static ui.Image? getCachedImage(String url) {
    return _CachedProfileAvatarState._getFromAnyCache(url);
  }

  @override
  State<CachedProfileAvatar> createState() => _CachedProfileAvatarState();
}

class _CachedProfileAvatarState extends State<CachedProfileAvatar> {
  static const int _maxCacheSize = 100;
  static final LinkedHashMap<String, ui.Image> _memCache =
      LinkedHashMap<String, ui.Image>();

  ui.Image? _decoded;
  String? _resolvedUrl;

  static ui.Image? _getFromAnyCache(String url) {
    final mem = _memCache[url];
    if (mem != null) {
      _memCache.remove(url);
      _memCache[url] = mem;
      return mem;
    }
    return ProfilePhotoCache.imageFor(url);
  }

  static void _putInCache(String url, ui.Image image) {
    if (_memCache.length >= _maxCacheSize) {
      _memCache.remove(_memCache.keys.first);
    }
    _memCache[url] = image;
  }

  bool get _hasValidUrl =>
      widget.photoUrl != null && widget.photoUrl!.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _resolveImage();
  }

  @override
  void didUpdateWidget(CachedProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photoUrl != widget.photoUrl) {
      _decoded = null;
      _resolvedUrl = null;
      _resolveImage();
    }
  }

  void _resolveImage() {
    if (!_hasValidUrl) return;
    final url = widget.photoUrl!.trim();

    final cached = _getFromAnyCache(url);
    if (cached != null) {
      _decoded = cached;
      _resolvedUrl = url;
      return;
    }

    _loadFromDiskCache(url);
  }

  Future<void> _loadFromDiskCache(String url) async {
    try {
      final info = await DefaultCacheManager().getFileFromCache(url);
      if (info != null) {
        final bytes = await info.file.readAsBytes();
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        _putInCache(url, frame.image);
        if (mounted && widget.photoUrl?.trim() == url) {
          setState(() {
            _decoded = frame.image;
            _resolvedUrl = url;
          });
        }
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.backgroundColor ?? Colors.grey[300];
    final fgColor = widget.textColor ?? Colors.black87;
    final size = widget.radius * 2;

    if (!_hasValidUrl) {
      return _buildFallbackAvatar(bgColor, fgColor);
    }

    final url = widget.photoUrl!.trim();

    if (_decoded != null && _resolvedUrl == url) {
      return ClipOval(
        child: SizedBox(
          width: size,
          height: size,
          child: FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: RawImage(image: _decoded),
          ),
        ),
      );
    }

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (context, url) => _buildPlaceholder(bgColor),
        errorWidget: (context, url, error) =>
            _buildFallbackAvatar(bgColor, fgColor),
      ),
    );
  }

  Widget _buildPlaceholder(Color? bgColor) {
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: bgColor,
      child: const SizedBox.shrink(),
    );
  }

  Widget _buildFallbackAvatar(Color? bgColor, Color fgColor) {
    return CircleAvatar(
      radius: widget.radius,
      backgroundColor: bgColor,
      child: widget.fallbackText != null
          ? Text(
              widget.fallbackText!,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: fgColor,
                fontSize: widget.radius * 0.8,
              ),
            )
          : Icon(
              Icons.person,
              size: widget.radius,
              color: fgColor,
            ),
    );
  }
}
