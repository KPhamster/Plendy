import 'package:flutter/material.dart';

/// Small reusable toggle button for switching between public/private states.
class PrivacyToggleButton extends StatelessWidget {
  final bool isPrivate;
  final VoidCallback onPressed;

  const PrivacyToggleButton({
    super.key,
    required this.isPrivate,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Color baseColor = theme.colorScheme.primary;
    final Color labelColor = isPrivate ? baseColor : Colors.white;
    final Color backgroundColor = isPrivate ? Colors.white : baseColor;
    final String label = isPrivate ? 'Private' : 'Public';
    final IconData iconData = isPrivate ? Icons.lock : Icons.public;

    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        foregroundColor: labelColor,
        backgroundColor: backgroundColor,
        side: BorderSide(color: baseColor),
        visualDensity: VisualDensity.compact,
      ),
      child: Row(
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
