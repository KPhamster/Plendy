import 'package:flutter/material.dart';

/// Small reusable toggle button for switching between public/private states.
class PrivacyToggleButton extends StatelessWidget {
  final bool isPrivate;
  final VoidCallback onPressed;
  final bool showLabel;

  const PrivacyToggleButton({
    super.key,
    required this.isPrivate,
    required this.onPressed,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color baseColor = theme.colorScheme.primary;
    final Color labelColor = isPrivate ? baseColor : Colors.white;
    final Color backgroundColor = isPrivate ? Colors.white : baseColor;
    final String label = isPrivate ? 'Private' : 'Public';
    final IconData iconData = isPrivate ? Icons.lock : Icons.public;
    final bool iconOnly = !showLabel;

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: iconOnly
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        foregroundColor: labelColor,
        backgroundColor: backgroundColor,
        side: BorderSide(color: baseColor),
        visualDensity: VisualDensity.compact,
        minimumSize: iconOnly ? const Size(36, 36) : null,
        shape: iconOnly ? const CircleBorder() : null,
      ),
      child: iconOnly
          ? Icon(iconData, size: 18)
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 6),
                Icon(iconData, size: 18),
              ],
            ),
    );
  }
}
