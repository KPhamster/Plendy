import 'dart:ui';
import 'help_target.dart';

/// Pure-logic help-mode state engine with no UI dependencies.
///
/// Generic on [T] so each screen can use its own target-id enum.
/// All state mutations are synchronous; the host widget calls [setState]
/// after mutating through this object.
class HelpFlowState<T> {
  final Map<T, HelpSpec<T>> content;

  bool isActive = false;
  T? activeTarget;
  int activeStep = 0;
  Rect? activeTargetRect;
  bool isTyping = false;

  // Saved snapshot for pause / resume across dialog boundaries.
  bool _savedIsActive = false;
  T? _savedTarget;
  int _savedStep = 0;
  Rect? _savedRect;
  bool _savedIsTyping = false;

  HelpFlowState({required this.content});

  // ─── Queries ────────────────────────────────────────────

  HelpSpec<T>? get activeSpec =>
      activeTarget != null ? content[activeTarget] : null;

  HelpStep? get activeHelpStep {
    final spec = activeSpec;
    if (spec == null || activeStep >= spec.steps.length) return null;
    return spec.steps[activeStep];
  }

  bool get isLastStep {
    final spec = activeSpec;
    if (spec == null) return true;
    return activeStep >= spec.steps.length - 1;
  }

  bool get hasActiveTarget => activeTarget != null;

  // ─── Mutations ──────────────────────────────────────────

  /// Enter help mode, optionally showing a starter target via [firstTarget].
  void activate({T? firstTarget, Rect? firstRect}) {
    isActive = true;
    if (firstTarget != null) {
      showTarget(firstTarget, firstRect);
    }
  }

  /// Exit help mode and reset all transient state.
  void deactivate() {
    isActive = false;
    _resetTarget();
  }

  /// Toggle between active/inactive.  Returns new [isActive].
  bool toggle({T? firstTarget, Rect? firstRect}) {
    if (isActive) {
      deactivate();
    } else {
      activate(firstTarget: firstTarget, firstRect: firstRect);
    }
    return isActive;
  }

  /// Highlight [target] and reset step counter.
  void showTarget(T target, [Rect? rect]) {
    activeTarget = target;
    activeStep = 0;
    activeTargetRect = rect;
    isTyping = true;
  }

  /// Move to the next step within the current target, or dismiss when done.
  void advance() {
    final spec = activeSpec;
    if (spec == null) {
      dismiss();
      return;
    }
    if (activeStep < spec.steps.length - 1) {
      activeStep++;
      isTyping = true;
    } else {
      dismiss();
    }
  }

  /// Clear the active bubble but stay in help mode.
  void dismiss() {
    _resetTarget();
  }

  /// Returns `true` if help mode is active and a target tap was consumed.
  bool tryConsumeTap(T target, Rect targetRect) {
    if (!isActive) return false;
    showTarget(target, targetRect);
    return true;
  }

  // ─── Pause / Resume (dialog boundaries) ─────────────────

  /// Snapshot current state so help can resume after a dialog closes.
  void pause() {
    _savedIsActive = isActive;
    _savedTarget = activeTarget;
    _savedStep = activeStep;
    _savedRect = activeTargetRect;
    _savedIsTyping = isTyping;
    // Visually deactivate while dialog is open.
    isActive = false;
    _resetTarget();
  }

  /// Restore the snapshot taken by [pause].
  void resume() {
    isActive = _savedIsActive;
    activeTarget = _savedTarget;
    activeStep = _savedStep;
    activeTargetRect = _savedRect;
    isTyping = _savedIsTyping;
    _clearSaved();
  }

  // ─── Internal ───────────────────────────────────────────

  void _resetTarget() {
    activeTarget = null;
    activeStep = 0;
    activeTargetRect = null;
    isTyping = false;
  }

  void _clearSaved() {
    _savedIsActive = false;
    _savedTarget = null;
    _savedStep = 0;
    _savedRect = null;
    _savedIsTyping = false;
  }
}
