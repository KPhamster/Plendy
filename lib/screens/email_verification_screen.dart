import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import 'package:plendy/utils/haptic_feedback.dart';

/// Screen shown to new users who need to verify their email address
/// before proceeding to the main app.
class EmailVerificationScreen extends StatefulWidget {
  final String email;
  final VoidCallback? onVerified;

  const EmailVerificationScreen({
    super.key,
    required this.email,
    this.onVerified,
  });

  @override
  State<EmailVerificationScreen> createState() => _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  bool _isCheckingVerification = false;
  bool _isResendingEmail = false;
  bool _canResend = true;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;
  Timer? _autoCheckTimer;

  @override
  void initState() {
    super.initState();
    // Start auto-checking for verification every 3 seconds
    _startAutoCheck();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _autoCheckTimer?.cancel();
    super.dispose();
  }

  void _startAutoCheck() {
    _autoCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkVerification(silent: true);
    });
  }

  Future<void> _checkVerification({bool silent = false}) async {
    if (_isCheckingVerification) return;

    if (!silent) {
      setState(() {
        _isCheckingVerification = true;
      });
    }

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final isVerified = await authService.checkEmailVerified();

      if (!mounted) return;

      if (isVerified) {
        // Mark verification in Firestore
        await authService.markEmailVerified();
        
        if (!mounted) return;

        // Show success message
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email verified successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );

        // Notify parent or navigate
        if (widget.onVerified != null) {
          widget.onVerified!();
        } else {
          // Pop back to trigger auth state refresh
          Navigator.of(context).pop(true);
        }
      } else if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email not verified yet. Please check your inbox.'),
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      if (!silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error checking verification: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted && !silent) {
        setState(() {
          _isCheckingVerification = false;
        });
      }
    }
  }

  Future<void> _resendVerificationEmail() async {
    if (!_canResend || _isResendingEmail) return;

    setState(() {
      _isResendingEmail = true;
    });

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.resendVerificationEmail();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Verification email sent to ${widget.email}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

      // Start cooldown (60 seconds)
      _startResendCooldown();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error sending email: ${e.toString().replaceFirst('Exception: ', '')}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isResendingEmail = false;
        });
      }
    }
  }

  void _startResendCooldown() {
    setState(() {
      _canResend = false;
      _resendCooldown = 60;
    });

    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        _resendCooldown--;
        if (_resendCooldown <= 0) {
          _canResend = true;
          timer.cancel();
        }
      });
    });
  }

  Future<void> _signOut() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.signOut();
    if (mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 60),
              
              // Email icon
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.mark_email_unread_outlined,
                  size: 50,
                  color: Colors.blue.shade600,
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Title
              const Text(
                'Verify Your Email',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Description
              Text(
                'We\'ve sent a verification email to:',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              
              const SizedBox(height: 8),
              
              // Email address
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  widget.email,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
              
              const SizedBox(height: 24),
              
              // Instructions
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Please check your inbox and spam folder',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Click the verification link in the email, then tap "I\'ve Verified" below.',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.amber.shade800,
                      ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 40),
              
              // Verify button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isCheckingVerification ? null : () => _checkVerification(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor: Colors.black54,
                  ),
                  child: _isCheckingVerification
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          'I\'ve Verified My Email',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              
              const SizedBox(height: 16),
              
              // Resend button
              TextButton(
                onPressed: _canResend && !_isResendingEmail ? _resendVerificationEmail : null,
                child: _isResendingEmail
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.black54),
                        ),
                      )
                    : Text(
                        _canResend
                            ? 'Resend Verification Email'
                            : 'Resend in $_resendCooldown seconds',
                        style: TextStyle(
                          color: _canResend ? Colors.blue : Colors.grey,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
              ),
              
              const SizedBox(height: 40),
              
              // Sign out option
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Wrong email? ',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  GestureDetector(
                    onTap: withHeavyTap(_signOut),
                    child: const Text(
                      'Sign out',
                      style: TextStyle(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Auto-check indicator
              Text(
                'Checking verification status automatically...',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[400],
                  fontStyle: FontStyle.italic,
                ),
              ),

              const SizedBox(height: 32),

              // Support contact
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.help_outline, color: Colors.blue.shade600, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Having trouble?',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Colors.blue.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    RichText(
                      text: TextSpan(
                        style: TextStyle(
                          color: Colors.grey[700],
                          fontSize: 14,
                          height: 1.4,
                        ),
                        children: [
                          const TextSpan(
                            text: 'If you are having trouble validating your email address, send an email to ',
                          ),
                          WidgetSpan(
                            child: GestureDetector(
                              onTap: withHeavyTap(() async {
                                final Uri emailUri = Uri(
                                  scheme: 'mailto',
                                  path: 'admin@plendy.app',
                                  queryParameters: {
                                    'subject': 'Email Verification Help - ${widget.email}',
                                    'body': 'Hi Plendy Support,\n\nI\'m having trouble verifying my email address: ${widget.email}\n\nPlease help me verify my account.\n\nThank you!',
                                  },
                                );
                                if (await canLaunchUrl(emailUri)) {
                                  await launchUrl(emailUri);
                                }
                              }),
                              child: Text(
                                'admin@plendy.app',
                                style: TextStyle(
                                  color: Colors.blue.shade600,
                                  fontWeight: FontWeight.w600,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ),
                          const TextSpan(
                            text: ' with this email address and we will get back to you.',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
