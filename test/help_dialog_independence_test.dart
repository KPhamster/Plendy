import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:plendy/models/help_flow_state.dart';
import 'package:plendy/models/help_target.dart';

enum _Id { x, y }

final _content = <_Id, HelpSpec<_Id>>{
  _Id.x: const HelpSpec(id: _Id.x, steps: [
    HelpStep(text: 'Main target'),
  ]),
  _Id.y: const HelpSpec(id: _Id.y, steps: [
    HelpStep(text: 'Dialog target'),
  ]),
};

const _rect = Rect.fromLTWH(0, 0, 80, 40);

void main() {
  group('Dialog-mode independence', () {
    test('pause deactivates main and resume restores it', () {
      final main = HelpFlowState<_Id>(content: _content)
        ..activate()
        ..showTarget(_Id.x, _rect);

      expect(main.isActive, isTrue);
      expect(main.activeTarget, _Id.x);

      main.pause();
      expect(main.isActive, isFalse);
      expect(main.hasActiveTarget, isFalse);

      // Simulate dialog-local help
      final dialog = HelpFlowState<_Id>(content: _content)
        ..activate()
        ..showTarget(_Id.y, _rect);
      expect(dialog.isActive, isTrue);
      expect(dialog.activeTarget, _Id.y);

      // Dialog dismissed
      dialog.deactivate();
      expect(dialog.isActive, isFalse);

      // Main resumes prior state
      main.resume();
      expect(main.isActive, isTrue);
      expect(main.activeTarget, _Id.x);
    });

    test('dialog help resets on deactivate without affecting main', () {
      final main = HelpFlowState<_Id>(content: _content)..activate();
      main.pause();

      final dialog = HelpFlowState<_Id>(content: _content)
        ..activate()
        ..showTarget(_Id.y, _rect);

      dialog.deactivate();
      expect(dialog.isActive, isFalse);
      expect(dialog.hasActiveTarget, isFalse);

      main.resume();
      expect(main.isActive, isTrue);
    });

    test('main not in help mode stays inactive after pause+resume', () {
      final main = HelpFlowState<_Id>(content: _content);
      expect(main.isActive, isFalse);

      main.pause();
      main.resume();
      expect(main.isActive, isFalse);
    });

    test('dialog help advance/dismiss works independently', () {
      final main = HelpFlowState<_Id>(content: _content)..activate();
      main.pause();

      final dialog = HelpFlowState<_Id>(content: _content)
        ..activate()
        ..showTarget(_Id.y, _rect);

      dialog.advance(); // single step -> dismiss
      expect(dialog.hasActiveTarget, isFalse);
      expect(dialog.isActive, isTrue);

      dialog.deactivate();
      main.resume();
      expect(main.isActive, isTrue);
    });
  });
}
