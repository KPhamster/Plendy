import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../config/colors.dart';
import 'browser_signin_screen.dart';
import '../services/auth_service.dart';
import '../services/ai_settings_service.dart';
import '../services/instagram_settings_service.dart';
import '../config/settings_help_content.dart';
import '../models/settings_help_target.dart';
import '../widgets/screen_help_controller.dart';

enum InstagramDisplayOption { defaultView, webView }

// Re-export AutoScanMode from ai_settings_service for use in this file
// Using the enum directly from the service

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with TickerProviderStateMixin {
  final _authService = AuthService();
  InstagramDisplayOption _instagramDisplay = InstagramDisplayOption.defaultView;
  bool _autoExtractLocations = true;
  bool _autoSetCategories = true;
  AutoScanMode _autoScanMode = AutoScanMode.quickScan;
  bool _isLoading = true;
  late final ScreenHelpController<SettingsHelpTargetId> _help;
  final GlobalKey _settingsListKey = GlobalKey();
  final GlobalKey _deleteButtonKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _help = ScreenHelpController<SettingsHelpTargetId>(
      vsync: this,
      content: settingsHelpContent,
      setState: setState,
      isMounted: () => mounted,
      defaultFirstTarget: SettingsHelpTargetId.helpButton,
    );
    _loadSettings();
  }

  @override
  void dispose() {
    _help.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final instagramSettingsService = InstagramSettingsService.instance;
    final aiSettingsService = AiSettingsService.instance;

    final results = await Future.wait([
      instagramSettingsService.getDisplayOption(),
      aiSettingsService.getAutoExtractLocations(),
      aiSettingsService.getAutoSetCategories(),
      aiSettingsService.getAutoScanMode(),
    ]);

    final instagramOption = results[0] as String;
    final autoExtractLocations = results[1] as bool;
    final autoSetCategories = results[2] as bool;
    final autoScanMode = results[3] as AutoScanMode;

    if (!mounted) return;
    setState(() {
      _instagramDisplay = instagramOption == 'webview'
          ? InstagramDisplayOption.webView
          : InstagramDisplayOption.defaultView;
      _autoExtractLocations = autoExtractLocations;
      _autoSetCategories = autoSetCategories;
      _autoScanMode = autoScanMode;
      _isLoading = false;
    });
  }

  Future<void> _saveInstagramDisplayOption(
      InstagramDisplayOption option) async {
    final settingsService = InstagramSettingsService.instance;
    final optionString =
        option == InstagramDisplayOption.webView ? 'webview' : 'default';
    await settingsService.setDisplayOption(optionString);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.backgroundColor,
          appBar: AppBar(
            backgroundColor: AppColors.backgroundColor,
            foregroundColor: Colors.black,
            title: const Text('Settings'),
            bottom: _help.isActive
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(24),
                    child: _help.buildExitBanner(),
                  )
                : null,
          ),
          body: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Builder(
                  builder: (viewCtx) => GestureDetector(
                    behavior: _help.isActive
                        ? HitTestBehavior.opaque
                        : HitTestBehavior.deferToChild,
                    onTap: _help.isActive
                        ? () => _help.tryTap(
                              SettingsHelpTargetId.settingsList,
                              viewCtx,
                            )
                        : null,
                    child: IgnorePointer(
                      ignoring: _help.isActive,
                      child: ListView(
                        key: _settingsListKey,
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                        children: [
                          const Text(
                            'Instagram Display',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Choose how Instagram posts are shown in the app.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 12),
                          RadioListTile<InstagramDisplayOption>(
                            title: const Text('Default'),
                            subtitle: const Text(
                              'Some Instagram content will ask to log into Instagram so logging in is recommended. If you choose not to log in, simply tap anywhere outside the login prompt to watch the content.',
                            ),
                            value: InstagramDisplayOption.defaultView,
                            groupValue: _instagramDisplay,
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _instagramDisplay = value;
                              });
                              _saveInstagramDisplayOption(value);
                            },
                          ),
                          RadioListTile<InstagramDisplayOption>(
                            title: const Text('Web View'),
                            subtitle: Builder(
                              builder: (context) {
                                final subtitleStyle =
                                    DefaultTextStyle.of(context).style;
                                return Wrap(
                                  children: [
                                    Text(
                                      'All Instagram content will ask for Instagram login in the in-app browser so ',
                                      style: subtitleStyle,
                                    ),
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                const BrowserSignInScreen(),
                                          ),
                                        );
                                      },
                                      child: Text(
                                        'logging in is highly recommended.',
                                        style: subtitleStyle.copyWith(
                                          color: Colors.blue,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      'Consistently provides a larger video.',
                                      style: subtitleStyle,
                                    ),
                                  ],
                                );
                              },
                            ),
                            value: InstagramDisplayOption.webView,
                            groupValue: _instagramDisplay,
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _instagramDisplay = value;
                              });
                              _saveInstagramDisplayOption(value);
                            },
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'AI Use',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Control automatic AI-powered features.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 12),
                          CheckboxListTile(
                            title: const Text(
                                'Automatically extract locations and events'),
                            subtitle: const Text(
                              'Use AI to automatically detect and suggest locations from shared content.',
                            ),
                            value: _autoExtractLocations,
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _autoExtractLocations = value;
                              });
                              AiSettingsService.instance
                                  .setAutoExtractLocations(value);
                            },
                          ),
                          // Show scan mode options when auto-extract is enabled
                          if (_autoExtractLocations) ...[
                            Padding(
                              padding: const EdgeInsets.only(left: 32.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 8),
                                  Text(
                                    'Auto-Scan with...',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: Colors.grey[700],
                                    ),
                                  ),
                                  RadioListTile<AutoScanMode>(
                                    title:
                                        const Text('Quick Scan (Recommended)'),
                                    subtitle: const Text(
                                      'Fast extraction using AI. Use Deep Scan manually if locations are missed.',
                                    ),
                                    value: AutoScanMode.quickScan,
                                    groupValue: _autoScanMode,
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setState(() {
                                        _autoScanMode = value;
                                      });
                                      AiSettingsService.instance
                                          .setAutoScanMode(value);
                                    },
                                  ),
                                  RadioListTile<AutoScanMode>(
                                    title: const Text('Deep Scan'),
                                    subtitle: const Text(
                                      'More thorough analysis. Slower but more accurate and may find more locations.',
                                    ),
                                    value: AutoScanMode.deepScan,
                                    groupValue: _autoScanMode,
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setState(() {
                                        _autoScanMode = value;
                                      });
                                      AiSettingsService.instance
                                          .setAutoScanMode(value);
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                          CheckboxListTile(
                            title: const Text('Automatically set categories'),
                            subtitle: const Text(
                              'Automatically assign a category after selecting a location.',
                            ),
                            value: _autoSetCategories,
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _autoSetCategories = value;
                              });
                              AiSettingsService.instance
                                  .setAutoSetCategories(value);
                            },
                          ),
                          const SizedBox(height: 32),
                          Builder(
                            builder: (deleteCtx) => TextButton(
                              key: _deleteButtonKey,
                              onPressed: _help.isActive
                                  ? () => _help.tryTap(
                                        SettingsHelpTargetId
                                            .deleteAccountButton,
                                        deleteCtx,
                                      )
                                  : _confirmDeleteAccount,
                              child: const Text(
                                'Delete Account',
                                style:
                                    TextStyle(color: Colors.red, fontSize: 16),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
        if (_help.isActive && _help.hasActiveTarget) _help.buildOverlay(),
      ],
    );
  }

  void _confirmDeleteAccount() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text('Delete Account'),
          content: const Text(
            'Are you sure you want to delete your account? This action is permanent and cannot be undone. All of your data, including experiences and reviews, will be removed.',
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(context).pop();
                _deleteAccount();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _deleteAccount() async {
    setState(() => _isLoading = true);
    try {
      final user = _authService.currentUser;
      if (user == null) {
        throw Exception('No user is currently signed in.');
      }

      await user.delete();

      if (mounted) {
        Navigator.of(context, rootNavigator: true)
            .popUntil((route) => route.isFirst);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account successfully deleted.')),
        );
      }
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'requires-recent-login') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'This action requires you to have recently signed in. Please sign out and sign back in to continue.',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting account: ${e.message}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('An unexpected error occurred: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
