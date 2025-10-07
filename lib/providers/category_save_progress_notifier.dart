import 'package:flutter/foundation.dart';

class CategorySaveTask {
  CategorySaveTask({
    required this.id,
    required this.categoryName,
    required this.totalUnits,
    required this.categoryId,
    required this.ownerUserId,
    required this.isColorCategory,
    required this.accessMode,
    required List<String> experienceIds,
  }) : experienceIds = List<String>.unmodifiable(experienceIds);

  final int id;
  final String categoryName;
  int completedUnits = 0;
  int totalUnits;
  final String categoryId;
  final String ownerUserId;
  final bool isColorCategory;
  final String accessMode;
  final List<String> experienceIds;

  double? get progress {
    if (totalUnits <= 0) {
      return null;
    }
    final double ratio = completedUnits / totalUnits;
    if (ratio.isNaN) {
      return null;
    }
    if (ratio < 0) {
      return 0;
    }
    if (ratio > 1) {
      return 1;
    }
    return ratio;
  }

  CategorySaveTaskSnapshot toSnapshot() => CategorySaveTaskSnapshot(
        categoryId: categoryId,
        ownerUserId: ownerUserId,
        isColorCategory: isColorCategory,
        experienceIds: experienceIds,
        accessMode: accessMode,
        categoryName: categoryName,
      );
}

class CategorySaveMessage {
  const CategorySaveMessage({
    required this.text,
    required this.isError,
    this.snapshot,
  });

  final String text;
  final bool isError;
  final CategorySaveTaskSnapshot? snapshot;
}

class CategorySaveTaskSnapshot {
  CategorySaveTaskSnapshot({
    required this.categoryId,
    required this.ownerUserId,
    required this.isColorCategory,
    required List<String> experienceIds,
    required this.accessMode,
    required this.categoryName,
  }) : experienceIds = List<String>.unmodifiable(experienceIds);

  final String categoryId;
  final String ownerUserId;
  final bool isColorCategory;
  final List<String> experienceIds;
  final String accessMode;
  final String categoryName;
}

class CategorySaveProgressController {
  CategorySaveProgressController._(this._notifier, this._taskId);

  final CategorySaveProgressNotifier _notifier;
  final int _taskId;

  void update({int? completedUnits, int? totalUnits}) {
    _notifier._updateTaskProgress(
      _taskId,
      completedUnits: completedUnits,
      totalUnits: totalUnits,
    );
  }
}

/// Exposes background category save progress so the Collections screen can
/// surface per-category activity while work continues off the preview flows.
class CategorySaveProgressNotifier extends ChangeNotifier {
  final List<CategorySaveTask> _activeTasks = <CategorySaveTask>[];
  final List<CategorySaveMessage> _messageQueue = <CategorySaveMessage>[];
  int _taskCounter = 0;

  List<CategorySaveTask> get activeTasks =>
      List<CategorySaveTask>.unmodifiable(_activeTasks);

  bool get hasActiveTasks => _activeTasks.isNotEmpty;

  CategorySaveMessage? takeNextMessage() {
    if (_messageQueue.isEmpty) {
      return null;
    }
    return _messageQueue.removeAt(0);
  }

  Future<void> startCategorySave({
    required String categoryName,
    required int totalUnits,
    required String categoryId,
    required String ownerUserId,
    required bool isColorCategory,
    required String accessMode,
    required List<String> experienceIds,
    required Future<void> Function(CategorySaveProgressController controller)
        saveOperation,
  }) async {
    final CategorySaveTask task = CategorySaveTask(
      id: _taskCounter++,
      categoryName: categoryName,
      totalUnits: totalUnits,
      categoryId: categoryId,
      ownerUserId: ownerUserId,
      isColorCategory: isColorCategory,
      accessMode: accessMode,
      experienceIds: experienceIds,
    );
    _activeTasks.add(task);
    notifyListeners();

    final controller = CategorySaveProgressController._(this, task.id);

    Future<void> operation;
    try {
      operation = saveOperation(controller);
    } catch (error, stackTrace) {
      debugPrint(
          'CategorySaveProgressNotifier: failed to start save for $categoryName: $error');
      _enqueueMessage(
        CategorySaveMessage(
          text: 'Failed to save $categoryName Category',
          isError: true,
        ),
      );
      _completeTask(task);
      return Future.error(error, stackTrace);
    }

    operation.then((_) {
      _enqueueMessage(
        CategorySaveMessage(
          text: 'Saved $categoryName Category',
          isError: false,
          snapshot: task.toSnapshot(),
        ),
      );
    }).catchError((Object error, StackTrace stackTrace) {
      debugPrint(
          'CategorySaveProgressNotifier: save failed for $categoryName: $error');
      _enqueueMessage(
        CategorySaveMessage(
          text: 'Failed to save $categoryName Category',
          isError: true,
          snapshot: task.toSnapshot(),
        ),
      );
    }).whenComplete(() {
      _completeTask(task);
    });

    return operation;
  }

  void _enqueueMessage(CategorySaveMessage message) {
    _messageQueue.add(message);
    notifyListeners();
  }

  void _updateTaskProgress(
    int taskId, {
    int? completedUnits,
    int? totalUnits,
  }) {
    for (final task in _activeTasks) {
      if (task.id == taskId) {
        if (totalUnits != null && totalUnits >= 0) {
          task.totalUnits = totalUnits;
        }
        if (completedUnits != null) {
          final int upperBound =
              task.totalUnits > 0 ? task.totalUnits : completedUnits;
          int nextValue = completedUnits;
          if (nextValue < 0) {
            nextValue = 0;
          } else if (nextValue > upperBound) {
            nextValue = upperBound;
          }
          task.completedUnits = nextValue;
        }
        notifyListeners();
        break;
      }
    }
  }

  void _completeTask(CategorySaveTask task) {
    if (task.totalUnits > 0) {
      task.completedUnits = task.totalUnits;
    }
    _activeTasks.removeWhere((t) => t.id == task.id);
    notifyListeners();
  }
}
