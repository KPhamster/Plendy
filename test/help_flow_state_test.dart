import 'dart:ui';
import 'package:flutter_test/flutter_test.dart';
import 'package:plendy/models/help_flow_state.dart';
import 'package:plendy/models/help_target.dart';

enum _T { a, b, c }

final _content = <_T, HelpSpec<_T>>{
  _T.a: const HelpSpec(id: _T.a, steps: [
    HelpStep(text: 'Step A1', instruction: 'Tap'),
    HelpStep(text: 'Step A2'),
  ]),
  _T.b: const HelpSpec(id: _T.b, steps: [
    HelpStep(text: 'Step B1'),
  ]),
};

HelpFlowState<_T> _make() => HelpFlowState<_T>(content: _content);
const _rect = Rect.fromLTWH(10, 20, 100, 50);

void main() {
  group('HelpFlowState', () {
    group('mode entry / exit', () {
      test('starts inactive', () {
        final s = _make();
        expect(s.isActive, isFalse);
        expect(s.hasActiveTarget, isFalse);
      });

      test('activate turns on help mode', () {
        final s = _make()..activate();
        expect(s.isActive, isTrue);
      });

      test('deactivate resets all state', () {
        final s = _make()
          ..activate(firstTarget: _T.a, firstRect: _rect);
        expect(s.isActive, isTrue);
        expect(s.hasActiveTarget, isTrue);

        s.deactivate();
        expect(s.isActive, isFalse);
        expect(s.activeTarget, isNull);
        expect(s.activeStep, 0);
        expect(s.activeTargetRect, isNull);
        expect(s.isTyping, isFalse);
      });

      test('toggle flips and returns new state', () {
        final s = _make();
        expect(s.toggle(), isTrue);
        expect(s.toggle(), isFalse);
      });
    });

    group('target activation', () {
      test('showTarget sets target and resets step', () {
        final s = _make()..activate();
        s.showTarget(_T.a, _rect);
        expect(s.activeTarget, _T.a);
        expect(s.activeStep, 0);
        expect(s.activeTargetRect, _rect);
        expect(s.isTyping, isTrue);
      });

      test('activeSpec returns correct spec', () {
        final s = _make()
          ..activate()
          ..showTarget(_T.a);
        expect(s.activeSpec?.id, _T.a);
        expect(s.activeSpec?.steps.length, 2);
      });

      test('activeHelpStep returns the current step', () {
        final s = _make()
          ..activate()
          ..showTarget(_T.a);
        expect(s.activeHelpStep?.text, 'Step A1');
      });

      test('isLastStep is false on first of two steps', () {
        final s = _make()
          ..activate()
          ..showTarget(_T.a);
        expect(s.isLastStep, isFalse);
      });

      test('isLastStep is true on single-step target', () {
        final s = _make()
          ..activate()
          ..showTarget(_T.b);
        expect(s.isLastStep, isTrue);
      });
    });

    group('step progression', () {
      test('advance moves to next step', () {
        final s = _make()
          ..activate()
          ..showTarget(_T.a);

        s.advance();
        expect(s.activeStep, 1);
        expect(s.activeHelpStep?.text, 'Step A2');
        expect(s.isTyping, isTrue);
      });

      test('advance on last step dismisses bubble but stays active', () {
        final s = _make()
          ..activate()
          ..showTarget(_T.a);

        s.advance(); // step 0 -> 1
        s.advance(); // step 1 -> dismiss

        expect(s.isActive, isTrue);
        expect(s.hasActiveTarget, isFalse);
        expect(s.activeStep, 0);
      });

      test('advance on single-step target dismisses immediately', () {
        final s = _make()
          ..activate()
          ..showTarget(_T.b);

        s.advance();
        expect(s.hasActiveTarget, isFalse);
      });
    });

    group('dismiss', () {
      test('dismiss clears target but keeps mode active', () {
        final s = _make()
          ..activate()
          ..showTarget(_T.a);
        s.dismiss();

        expect(s.isActive, isTrue);
        expect(s.hasActiveTarget, isFalse);
        expect(s.activeStep, 0);
        expect(s.isTyping, isFalse);
      });
    });

    group('tryConsumeTap', () {
      test('returns false when inactive', () {
        final s = _make();
        expect(s.tryConsumeTap(_T.a, _rect), isFalse);
      });

      test('returns true and shows target when active', () {
        final s = _make()..activate();
        expect(s.tryConsumeTap(_T.a, _rect), isTrue);
        expect(s.activeTarget, _T.a);
      });
    });

    group('pause / resume', () {
      test('pause deactivates and resume restores state', () {
        final s = _make()
          ..activate()
          ..showTarget(_T.a, _rect);
        s.advance(); // step 1
        s.isTyping = false;

        s.pause();
        expect(s.isActive, isFalse);
        expect(s.hasActiveTarget, isFalse);

        s.resume();
        expect(s.isActive, isTrue);
        expect(s.activeTarget, _T.a);
        expect(s.activeStep, 1);
        expect(s.activeTargetRect, _rect);
      });

      test('pause while inactive resumes to inactive', () {
        final s = _make();
        s.pause();
        s.resume();
        expect(s.isActive, isFalse);
      });
    });

    group('content lookup edge cases', () {
      test('target not in content returns null spec', () {
        final s = _make()
          ..activate()
          ..showTarget(_T.c);
        expect(s.activeSpec, isNull);
        expect(s.activeHelpStep, isNull);
        expect(s.isLastStep, isTrue);
      });

      test('advance with unknown target dismisses gracefully', () {
        final s = _make()
          ..activate()
          ..showTarget(_T.c);
        s.advance();
        expect(s.hasActiveTarget, isFalse);
      });
    });
  });
}
