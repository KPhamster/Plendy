import 'dart:io';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class ImagePreviewWidget extends StatelessWidget {
  final SharedMediaFile file;

  const ImagePreviewWidget({super.key, required this.file});

  @override
  Widget build(BuildContext context) {
    // Logic moved from _buildImagePreview
    try {
      return SizedBox(
        height: 350,
        width: double.infinity,
        child: Image.file(
          File(file.path),
          fit: BoxFit.cover,
        ),
      );
    } catch (e) {
      print('Error loading image preview: $e');
      return Container(
        height: 350, // Consistent height for error state
        width: double.infinity,
        color: Colors.grey[300],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image_not_supported,
                  size: 50, color: Colors.grey[600]),
              SizedBox(height: 8),
              Text(
                'Could not load image',
                style: TextStyle(color: Colors.grey[700]),
              ),
            ],
          ),
        ),
      );
    }
  }
}
