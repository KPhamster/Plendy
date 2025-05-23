import 'package:flutter/material.dart';

class NotificationDot extends StatelessWidget {
  final Widget child;
  final bool showDot;
  final double? dotSize;
  final Color? dotColor;
  final double? top;
  final double? right;
  final double? left;
  final double? bottom;

  const NotificationDot({
    super.key,
    required this.child,
    required this.showDot,
    this.dotSize = 8.0,
    this.dotColor = Colors.red,
    this.top,
    this.right,
    this.left,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (showDot)
          Positioned(
            top: top,
            right: right,
            left: left,
            bottom: bottom,
            child: Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 1.0,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Specific widget for tab indicators
class TabNotificationDot extends StatelessWidget {
  final String text;
  final bool showDot;
  
  const TabNotificationDot({
    super.key,
    required this.text,
    required this.showDot,
  });

  @override
  Widget build(BuildContext context) {
    return NotificationDot(
      showDot: showDot,
      top: 0,
      right: -2,
      child: Text(text),
    );
  }
}

/// Specific widget for icon indicators (like navbar and list items)
class IconNotificationDot extends StatelessWidget {
  final Widget icon;
  final bool showDot;
  
  const IconNotificationDot({
    super.key,
    required this.icon,
    required this.showDot,
  });

  @override
  Widget build(BuildContext context) {
    return NotificationDot(
      showDot: showDot,
      top: 0,
      right: 0,
      child: icon,
    );
  }
}

/// Specific widget for profile picture indicators
class ProfilePictureNotificationDot extends StatelessWidget {
  final Widget profilePicture;
  final bool showDot;
  
  const ProfilePictureNotificationDot({
    super.key,
    required this.profilePicture,
    required this.showDot,
  });

  @override
  Widget build(BuildContext context) {
    return NotificationDot(
      showDot: showDot,
      top: 2,
      left: -2,
      dotSize: 10.0,
      child: profilePicture,
    );
  }
} 