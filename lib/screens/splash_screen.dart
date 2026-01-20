import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import 'dart:async';
import '../config/colors.dart';

class SplashScreen extends StatefulWidget {
  final VoidCallback? onAnimationComplete;

  const SplashScreen({super.key, this.onAnimationComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  bool _hasCompleted = false;
  Timer? _fallbackTimer;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    print('SplashScreen: initState called');

    // Create animation controller
    _animationController = AnimationController(vsync: this);

    // Listen for animation completion
    _animationController.addStatusListener((status) {
      print('SplashScreen: Animation status changed to $status');
      if (status == AnimationStatus.completed) {
        // Add small delay after animation completes for smooth transition
        Future.delayed(const Duration(milliseconds: 300), () {
          _completeAnimation();
        });
      }
    });

    // Fallback timer in case Lottie fails to load or animation doesn't complete
    // This ensures the splash screen always transitions after max 5 seconds
    _fallbackTimer = Timer(const Duration(seconds: 5), () {
      print('SplashScreen: Fallback timer fired after 5 seconds');
      _completeAnimation();
    });
  }

  @override
  void dispose() {
    print('SplashScreen: dispose called');
    _fallbackTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  void _completeAnimation() {
    print(
        'SplashScreen: _completeAnimation called, hasCompleted=$_hasCompleted, mounted=$mounted');
    if (mounted && !_hasCompleted && widget.onAnimationComplete != null) {
      _hasCompleted = true;
      print('SplashScreen: Calling onAnimationComplete callback');
      widget.onAnimationComplete!();
    }
  }

  @override
  Widget build(BuildContext context) {
    print('SplashScreen: build called');
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      body: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.fitHeight,
          alignment: Alignment.center,
          child: Lottie.asset(
            'assets/animations/splash_logo.json',
            controller: _animationController,
            onLoaded: (composition) {
              print(
                  'SplashScreen: Lottie onLoaded called, duration=${composition.duration}');
              // Cancel fallback timer since animation loaded successfully
              _fallbackTimer?.cancel();

              // Set the duration and start the animation
              _animationController.duration = composition.duration;
              print('SplashScreen: Starting animation');
              _animationController.forward();
            },
            errorBuilder: (context, error, stackTrace) {
              print('SplashScreen: Lottie errorBuilder called - $error');
              // If Lottie fails to load, show static logo and complete after 2 seconds
              _fallbackTimer?.cancel();
              Timer(const Duration(seconds: 2), _completeAnimation);
              return Image.asset(
                'assets/icon/icon.png',
                fit: BoxFit.contain,
              );
            },
          ),
        ),
      ),
    );
  }
}
