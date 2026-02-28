import 'package:flutter/material.dart';
import '../models/collections_help_target.dart';
import '../config/collections_help_content.dart';
import 'help_bubble.dart';

class CollectionsHelpBubble extends StatefulWidget {
  final CollectionsHelpTargetId targetId;
  final int stepIndex;
  final Rect targetRect;
  final VoidCallback onAdvance;
  final VoidCallback onDismiss;
  final VoidCallback onTypingStarted;
  final VoidCallback onTypingFinished;
  final String Function(
      CollectionsHelpTargetId targetId, int stepIndex, String staticText)?
      textResolver;

  const CollectionsHelpBubble({
    super.key,
    required this.targetId,
    required this.stepIndex,
    required this.targetRect,
    required this.onAdvance,
    required this.onDismiss,
    required this.onTypingStarted,
    required this.onTypingFinished,
    this.textResolver,
  });

  @override
  State<CollectionsHelpBubble> createState() => CollectionsHelpBubbleState();
}

class CollectionsHelpBubbleState extends State<CollectionsHelpBubble> {
  final GlobalKey<HelpBubbleState> _bubbleKey = GlobalKey();

  void skipTypewriter() {
    _bubbleKey.currentState?.skipTypewriter();
  }

  @override
  Widget build(BuildContext context) {
    final spec = collectionsHelpContent[widget.targetId];
    if (spec == null) return const SizedBox.shrink();
    if (widget.stepIndex >= spec.steps.length) return const SizedBox.shrink();
    final step = spec.steps[widget.stepIndex];
    final isLastStep = widget.stepIndex >= spec.steps.length - 1;

    return HelpBubble(
      key: _bubbleKey,
      text: widget.textResolver
              ?.call(widget.targetId, widget.stepIndex, step.text) ??
          step.text,
      instruction: step.instruction,
      isLastStep: isLastStep,
      targetRect: widget.targetRect,
      onAdvance: widget.onAdvance,
      onDismiss: widget.onDismiss,
      onTypingStarted: widget.onTypingStarted,
      onTypingFinished: widget.onTypingFinished,
    );
  }
}
