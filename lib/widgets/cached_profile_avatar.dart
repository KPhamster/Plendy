import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// A cached profile avatar widget that uses CachedNetworkImage for fast loading.
/// Images are cached locally so they don't need to be re-downloaded.
class CachedProfileAvatar extends StatelessWidget {
  /// The URL of the profile photo. Can be null or empty.
  final String? photoUrl;

  /// The radius of the avatar. Defaults to 20 (40px diameter).
  final double radius;

  /// Optional fallback text to show when there's no photo (usually initials).
  /// If null and no photo, shows a person icon.
  final String? fallbackText;

  /// Background color for the fallback avatar.
  final Color? backgroundColor;

  /// Text color for the fallback text.
  final Color? textColor;

  const CachedProfileAvatar({
    super.key,
    this.photoUrl,
    this.radius = 20,
    this.fallbackText,
    this.backgroundColor,
    this.textColor,
  });

  /// Creates a CachedProfileAvatar from a UserProfile-like object.
  /// Extracts the first letter of displayName or username for fallback.
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

  bool get _hasValidUrl => photoUrl != null && photoUrl!.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final bgColor = backgroundColor ?? Colors.grey[300];
    final fgColor = textColor ?? Colors.black87;
    final size = radius * 2;

    if (!_hasValidUrl) {
      return _buildFallbackAvatar(bgColor, fgColor);
    }

    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: photoUrl!.trim(),
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
      radius: radius,
      backgroundColor: bgColor,
      child: const SizedBox.shrink(),
    );
  }

  Widget _buildFallbackAvatar(Color? bgColor, Color fgColor) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: bgColor,
      child: fallbackText != null
          ? Text(
              fallbackText!,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: fgColor,
                fontSize: radius * 0.8,
              ),
            )
          : Icon(
              Icons.person,
              size: radius,
              color: fgColor,
            ),
    );
  }
}







