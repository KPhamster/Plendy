import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';

class HelpBubble extends StatefulWidget {
  final String text;
  final String? instruction;
  final bool isLastStep;
  final Rect targetRect;
  final VoidCallback onAdvance;
  final VoidCallback onDismiss;
  final VoidCallback onTypingStarted;
  final VoidCallback onTypingFinished;

  const HelpBubble({
    super.key,
    required this.text,
    this.instruction,
    required this.isLastStep,
    required this.targetRect,
    required this.onAdvance,
    required this.onDismiss,
    required this.onTypingStarted,
    required this.onTypingFinished,
  });

  @override
  State<HelpBubble> createState() => HelpBubbleState();
}

class HelpBubbleState extends State<HelpBubble> {
  final GlobalKey<_HelpTypewriterTextState> _typewriterKey = GlobalKey();
  bool _typewriterComplete = false;

  void skipTypewriter() {
    _typewriterKey.currentState?.skipToEnd();
  }

  void _handleBubbleTap() {
    if (!_typewriterComplete) {
      skipTypewriter();
      return;
    }
    if (widget.isLastStep) {
      widget.onDismiss();
    } else {
      widget.onAdvance();
    }
  }

  @override
  void didUpdateWidget(HelpBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      setState(() => _typewriterComplete = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final safePadding = MediaQuery.of(context).padding;
    const bubbleWidth = 220.0;
    const birdSize = 60.0;
    const spacing = 6.0;
    const totalWidth = bubbleWidth + spacing + birdSize;
    const estimatedBubbleHeight = 120.0;

    final position = _computeBubblePosition(
      targetRect: widget.targetRect,
      totalSize: const Size(totalWidth, estimatedBubbleHeight),
      screenSize: screenSize,
      safePadding: safePadding,
    );

    final bool birdOnRight =
        position.dx + totalWidth <= screenSize.width - safePadding.right - 8;

    return Positioned(
      left: position.dx,
      top: position.dy,
      child: GestureDetector(
        onTap: _handleBubbleTap,
        behavior: HitTestBehavior.opaque,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!birdOnRight) _buildBird(),
            if (!birdOnRight) const SizedBox(width: spacing),
            _buildBubbleContainer(),
            if (birdOnRight) const SizedBox(width: spacing),
            if (birdOnRight) _buildBird(),
          ],
        ),
      ),
    );
  }

  Widget _buildBird() {
    return Semantics(
      label: 'Help mascot',
      child: SizedBox(
        width: 60,
        height: 60,
        child: Lottie.asset(
          'assets/mascot/bird_talking_head.json',
          fit: BoxFit.contain,
          options: LottieOptions(enableMergePaths: true),
        ),
      ),
    );
  }

  Widget _buildBubbleContainer() {
    return Semantics(
      label: widget.text,
      liveRegion: true,
      child: Container(
        width: 220,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HelpTypewriterText(
              key: _typewriterKey,
              text: widget.text,
              style: GoogleFonts.fredoka(
                fontSize: 15,
                color: Colors.black87,
                height: 1.4,
                decoration: TextDecoration.none,
              ),
              speed: const Duration(milliseconds: 30),
              onComplete: () {
                if (mounted) {
                  setState(() => _typewriterComplete = true);
                  widget.onTypingFinished();
                }
              },
              onStart: widget.onTypingStarted,
            ),
            if (_typewriterComplete && widget.instruction != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  widget.instruction!,
                  style: GoogleFonts.fredoka(
                    fontSize: 10,
                    color: Colors.grey[400],
                    fontStyle: FontStyle.italic,
                    decoration: TextDecoration.none,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static Offset _computeBubblePosition({
    required Rect targetRect,
    required Size totalSize,
    required Size screenSize,
    required EdgeInsets safePadding,
  }) {
    const margin = 8.0;
    const gapFromTarget = 8.0;

    final safeLeft = safePadding.left + margin;
    final safeTop = safePadding.top + margin;
    final safeRight = screenSize.width - safePadding.right - margin;
    final safeBottom = screenSize.height - safePadding.bottom - margin;

    final candidates = <Offset>[
      Offset(targetRect.center.dx - totalSize.width / 2,
          targetRect.top - totalSize.height - gapFromTarget),
      Offset(targetRect.center.dx - totalSize.width / 2,
          targetRect.bottom + gapFromTarget),
      Offset(targetRect.right + gapFromTarget,
          targetRect.center.dy - totalSize.height / 2),
      Offset(targetRect.left - totalSize.width - gapFromTarget,
          targetRect.center.dy - totalSize.height / 2),
    ];

    for (final candidate in candidates) {
      final clamped = Offset(
        candidate.dx.clamp(safeLeft, safeRight - totalSize.width),
        candidate.dy.clamp(safeTop, safeBottom - totalSize.height),
      );
      final bubbleRect = Rect.fromLTWH(
          clamped.dx, clamped.dy, totalSize.width, totalSize.height);
      if (!bubbleRect.overlaps(targetRect.inflate(4))) {
        return clamped;
      }
    }

    final fallback = Offset(
      targetRect.center.dx - totalSize.width / 2,
      targetRect.bottom + gapFromTarget,
    );
    return Offset(
      fallback.dx
          .clamp(safeLeft, math.max(safeLeft, safeRight - totalSize.width)),
      fallback.dy
          .clamp(safeTop, math.max(safeTop, safeBottom - totalSize.height)),
    );
  }
}

class _HelpTypewriterText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration speed;
  final VoidCallback? onComplete;
  final VoidCallback? onStart;

  const _HelpTypewriterText({
    super.key,
    required this.text,
    this.style,
    this.speed = const Duration(milliseconds: 30),
    this.onComplete,
    this.onStart,
  });

  @override
  State<_HelpTypewriterText> createState() => _HelpTypewriterTextState();
}

class _HelpTypewriterTextState extends State<_HelpTypewriterText> {
  String _displayText = '';
  int _currentIndex = 0;
  bool _isComplete = false;

  @override
  void initState() {
    super.initState();
    _notifyStart();
    _typeNextChar();
  }

  @override
  void didUpdateWidget(_HelpTypewriterText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _displayText = '';
      _currentIndex = 0;
      _isComplete = false;
      _notifyStart();
      _typeNextChar();
    }
  }

  void _notifyStart() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onStart?.call();
    });
  }

  void skipToEnd() {
    if (!_isComplete && mounted) {
      setState(() {
        _displayText = widget.text;
        _currentIndex = widget.text.length;
        _isComplete = true;
      });
      widget.onComplete?.call();
    }
  }

  void _typeNextChar() {
    if (_currentIndex < widget.text.length) {
      Future.delayed(widget.speed, () {
        if (mounted && !_isComplete) {
          setState(() {
            _displayText = widget.text.substring(0, _currentIndex + 1);
            _currentIndex++;
          });
          _typeNextChar();
        }
      });
    } else if (!_isComplete) {
      _isComplete = true;
      widget.onComplete?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveStyle = (widget.style ?? const TextStyle()).copyWith(
      decoration: TextDecoration.none,
    );
    return Text(_displayText, style: effectiveStyle);
  }
}
