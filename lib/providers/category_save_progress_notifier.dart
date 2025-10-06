import 'package:flutter/foundation.dart';

class CategorySaveTask {
  CategorySaveTask({
    required this.id,
    required this.categoryName,
    required this.totalUnits,
  });

  final int id;
  final String categoryName;
  int completedUnits = 0;
  int totalUnits;

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
}

class CategorySaveMessage {
  const CategorySaveMessage({required this.text, required this.isError});

  final String text;
  final bool isError;
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
    required Future<void> Function(CategorySaveProgressController controller)
        saveOperation,
  }) async {
    final CategorySaveTask task = CategorySaveTask(
      id: _taskCounter++,
      categoryName: categoryName,
      totalUnits: totalUnits,
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
        ),
      );
    }).catchError((Object error, StackTrace stackTrace) {
      debugPrint(
          'CategorySaveProgressNotifier: save failed for $categoryName: $error');
      _enqueueMessage(
        CategorySaveMessage(
          text: 'Failed to save $categoryName Category',
          isError: true,
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
