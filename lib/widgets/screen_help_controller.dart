import 'package:flutter/material.dart';

import 'package:plendy/utils/haptic_feedback.dart';

import '../config/colors.dart';
import '../models/help_flow_state.dart';
import '../models/help_target.dart';
import 'help_bubble.dart';
import 'help_spotlight_painter.dart';

typedef HelpSetState = void Function(VoidCallback fn);

/// Reusable, screen-local help mode controller.
///
/// This wraps [HelpFlowState] with UI-facing helpers for overlay rendering,
/// target taps, typing progression, and help-button entry/exit behavior.
class ScreenHelpController<T> {
  ScreenHelpController({
    required TickerProvider vsync,
    required Map<T, HelpSpec<T>> content,
    required HelpSetState setState,
    required bool Function() isMounted,
    this.defaultFirstTarget,
    this.enableHaptics = true,
    this.onModeChanged,
    this.textResolver,
  })  : _setState = setState,
        _isMounted = isMounted,
        flow = HelpFlowState<T>(content: content) {
    spotlightController = AnimationController(
      vsync: vsync,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  final HelpFlowState<T> flow;
  final T? defaultFirstTarget;
  final bool enableHaptics;
  final HelpSetState _setState;
  final bool Function() _isMounted;
  final ValueChanged<bool>? onModeChanged;

  /// Optional callback to resolve dynamic text for a help step.
  /// Receives the target id, step index, and the static text from the step.
  /// Return null to fall back to the static text.
  final String Function(T targetId, int stepIndex, String staticText)?
      textResolver;

  late final AnimationController spotlightController;
  final GlobalKey helpButtonKey = GlobalKey();
  final GlobalKey<HelpBubbleState> helpBubbleKey = GlobalKey();
  Rect? _activeBubbleRect;
  Rect? _savedBubbleRect;

  bool isTyping = false;

  bool get isActive => flow.isActive;
  bool get hasActiveTarget => flow.hasActiveTarget;

  void dispose() {
    spotlightController.dispose();
  }

  void toggleHelpMode({
    T? firstTarget,
    bool withHaptic = true,
    bool notify = true,
    bool showInitialTarget = true,
  }) {
    if (withHaptic && enableHaptics) {
      triggerHeavyHaptic();
    }

    bool? nowActive;
    _setState(() {
      final bool toggledActive = flow.toggle();
      nowActive = toggledActive;
      if (!toggledActive) {
        isTyping = false;
        _activeBubbleRect = null;
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_isMounted()) return;

        final target =
            showInitialTarget ? (firstTarget ?? defaultFirstTarget) : null;
        final helpCtx = helpButtonKey.currentContext;
        if (target != null && helpCtx != null) {
          showTarget(target, helpCtx);
        }
      });
    });

    if (notify && nowActive != null) {
      onModeChanged?.call(nowActive!);
    }
  }

  Rect? _rectFromContext(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return null;
    final offset = box.localToGlobal(Offset.zero);
    return offset & box.size;
  }

  void showTarget(
    T target,
    BuildContext targetCtx, {
    bool withHaptic = false,
    BuildContext? bubbleCtx,
  }) {
    final rect = _rectFromContext(targetCtx);
    if (rect == null) return;
    final bubbleRect = bubbleCtx != null ? _rectFromContext(bubbleCtx) : rect;

    if (withHaptic && enableHaptics) {
      triggerHeavyHaptic();
    }

    _setState(() {
      flow.showTarget(target, rect);
      _activeBubbleRect = bubbleRect ?? rect;
      isTyping = true;
    });
  }

  bool tryTap(T target, BuildContext targetCtx) {
    if (!flow.isActive) return false;
    showTarget(target, targetCtx, withHaptic: true);
    return true;
  }

  void advance() {
    _setState(() {
      flow.advance();
      isTyping = flow.hasActiveTarget;
      if (!flow.hasActiveTarget) {
        _activeBubbleRect = null;
      }
    });
  }

  void dismiss() {
    _setState(() {
      flow.dismiss();
      _activeBubbleRect = null;
      isTyping = false;
    });
  }

  void onBarrierTap() {
    if (isTyping) {
      helpBubbleKey.currentState?.skipTypewriter();
    } else {
      advance();
    }
  }

  void pause() {
    _setState(() {
      _savedBubbleRect = _activeBubbleRect;
      flow.pause();
      _activeBubbleRect = null;
      isTyping = false;
    });
  }

  void resume() {
    _setState(() {
      flow.resume();
      _activeBubbleRect = flow.hasActiveTarget
          ? (_savedBubbleRect ?? flow.activeTargetRect)
          : null;
      _savedBubbleRect = null;
    });
  }

  Widget buildOverlay() {
    final step = flow.activeHelpStep;

    if (!flow.isActive ||
        !flow.hasActiveTarget ||
        flow.activeTargetRect == null ||
        step == null) {
      return const SizedBox.shrink();
    }
    final bubbleRect = _activeBubbleRect ?? flow.activeTargetRect!;

    return Positioned.fill(
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: 1,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: onBarrierTap,
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: spotlightController,
                  builder: (context, _) => CustomPaint(
                    painter: HelpSpotlightPainter(
                      targetRect: flow.activeTargetRect!,
                      glowProgress: spotlightController.value,
                    ),
                  ),
                ),
              ),
              HelpBubble(
                key: helpBubbleKey,
                text: textResolver?.call(
                        flow.activeTarget as T, flow.activeStep, step.text) ??
                    step.text,
                instruction: step.instruction,
                isLastStep: flow.isLastStep,
                targetRect: bubbleRect,
                onAdvance: advance,
                onDismiss: dismiss,
                onTypingStarted: () {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_isMounted()) {
                      _setState(() => isTyping = true);
                    }
                  });
                },
                onTypingFinished: () {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_isMounted()) {
                      _setState(() => isTyping = false);
                    }
                  });
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget buildExitBanner({
    String text = 'Help mode is ON  •  Tap here to exit',
    Color? backgroundColor,
  }) {
    if (!flow.isActive) return const SizedBox.shrink();

    return GestureDetector(
      onTap: toggleHelpMode,
      child: AnimatedBuilder(
        animation: spotlightController,
        builder: (context, _) {
          final opacity = 0.6 + 0.4 * spotlightController.value;
          return Opacity(
            opacity: opacity,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 6),
              color: backgroundColor ?? AppColors.teal.withValues(alpha: 0.08),
              child: Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.teal,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget buildIconButton({
    Color activeColor = AppColors.teal,
    Color inactiveColor = Colors.black,
    String activeSemanticLabel = 'Exit help mode',
    String inactiveSemanticLabel = 'Enter help mode',
    String activeTooltip = 'Exit Help Mode',
    String inactiveTooltip = 'Help',
  }) {
    return Semantics(
      label: flow.isActive ? activeSemanticLabel : inactiveSemanticLabel,
      child: flow.isActive
          ? AnimatedBuilder(
              animation: spotlightController,
              builder: (context, child) {
                final scale = 1.0 + 0.15 * spotlightController.value;
                return Transform.scale(scale: scale, child: child);
              },
              child: IconButton(
                key: helpButtonKey,
                icon: Icon(Icons.help, color: activeColor),
                tooltip: activeTooltip,
                onPressed: toggleHelpMode,
              ),
            )
          : IconButton(
              key: helpButtonKey,
              icon: Icon(Icons.help_outline, color: inactiveColor),
              tooltip: inactiveTooltip,
              onPressed: toggleHelpMode,
            ),
    );
  }
}
