import 'dart:typed_data';

/// Compatibility model replacing receive_sharing_intent's SharedMediaFile.
///
/// This mirrors the shape used throughout the app so we can migrate to
/// share_handler under the hood without invasive UI changes.
enum SharedMediaType { image, video, text, file, url }

class SharedMediaFile {
  final String path;
  final Uint8List? thumbnail;
  final int? duration;
  final SharedMediaType type;

  const SharedMediaFile({
    required this.path,
    this.thumbnail,
    this.duration,
    required this.type,
  });
}


