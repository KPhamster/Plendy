import 'package:flutter/material.dart';

class PrivacyTooltipIcon extends StatelessWidget {
  final String message;

  const PrivacyTooltipIcon({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      waitDuration: const Duration(milliseconds: 300),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: () {
          showDialog(
            context: context,
            builder: (context) {
              return AlertDialog(
                backgroundColor: Colors.white,
                title: const Text('Privacy Info'),
                content: Text(message),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Got it'),
                  ),
                ],
              );
            },
          );
        },
        child: const Padding(
          padding: EdgeInsets.all(4.0),
          child: Icon(
            Icons.info_outline,
            size: 20,
            color: Colors.grey,
          ),
        ),
      ),
    );
  }
}
