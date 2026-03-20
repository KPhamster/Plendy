import '../models/shared_media_item.dart';

/// Labels and detection for Plendy-saved images (Firebase Storage + local copies).
class SharedMediaDisplayLabels {
  SharedMediaDisplayLabels._();

  /// Firebase uploaded share images or app-persisted local image files.
  static bool isPlendySavedUploadedOrLocalImage(String path) {
    if (path.isEmpty) return false;
    final lower = path.toLowerCase();
    if (lower.contains('firebasestorage.googleapis.com') &&
        lower.contains('shared_media')) {
      return true;
    }
    if (!path.startsWith('http://') && !path.startsWith('https://')) {
      return _looksLikeLocalSavedImagePath(path);
    }
    return false;
  }

  static bool _looksLikeLocalSavedImagePath(String path) {
    final l = path.toLowerCase().replaceAll('\\', '/');
    if (l.contains('plendy_shared_media')) return true;
    return l.endsWith('.png') ||
        l.endsWith('.jpg') ||
        l.endsWith('.jpeg') ||
        l.endsWith('.gif') ||
        l.endsWith('.webp') ||
        l.endsWith('.heic') ||
        l.endsWith('.heif');
  }

  /// 1-based index among saved images on [experience], in [sharedMediaItemIds] order.
  static int? savedImageOrdinalForItemInExperience({
    required List<String> sharedMediaItemIdsInOrder,
    required String targetMediaItemId,
    required Map<String, SharedMediaItem> mediaById,
  }) {
    final target = mediaById[targetMediaItemId];
    if (target == null ||
        !isPlendySavedUploadedOrLocalImage(target.path)) {
      return null;
    }
    var n = 0;
    for (final id in sharedMediaItemIdsInOrder) {
      final m = mediaById[id];
      if (m == null) continue;
      if (isPlendySavedUploadedOrLocalImage(m.path)) {
        n++;
        if (id == targetMediaItemId) return n;
      }
    }
    return null;
  }

  /// Header/title for a content card (hides long Firebase URLs).
  static String mediaCardTitle({
    required String path,
    String? caption,
    int? savedImageOrdinal,
  }) {
    if (savedImageOrdinal != null) {
      return 'Saved Image $savedImageOrdinal';
    }
    if (caption != null && caption.isNotEmpty) return caption;
    return path;
  }
}
