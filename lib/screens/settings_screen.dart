import 'package:flutter/material.dart';
import '../config/colors.dart';
import '../services/ai_settings_service.dart';
import '../services/instagram_settings_service.dart';

enum InstagramDisplayOption { defaultView, webView }

// Re-export AutoScanMode from ai_settings_service for use in this file
// Using the enum directly from the service

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  InstagramDisplayOption _instagramDisplay =
      InstagramDisplayOption.defaultView;
  bool _autoExtractLocations = true;
  bool _autoSetCategories = true;
  AutoScanMode _autoScanMode = AutoScanMode.quickScan;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
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

  Future<void> _saveInstagramDisplayOption(InstagramDisplayOption option) async {
    final settingsService = InstagramSettingsService.instance;
    final optionString = option == InstagramDisplayOption.webView ? 'webview' : 'default';
    await settingsService.setDisplayOption(optionString);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        backgroundColor: AppColors.backgroundColor,
        foregroundColor: Colors.black,
        title: const Text('Settings'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  'Instagram Display',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                  subtitle: const Text(
                    'All Instagram content will ask for Instagram login in the in-app browser so logging in is highly recommended. Consistently provides a '
                    'larger video.',
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                  title: const Text('Automatically extract locations and events'),
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
                    AiSettingsService.instance.setAutoExtractLocations(value);
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
                          'Scan Mode',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[700],
                          ),
                        ),
                        RadioListTile<AutoScanMode>(
                          title: const Text('Quick Scan'),
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
                            AiSettingsService.instance.setAutoScanMode(value);
                          },
                        ),
                        RadioListTile<AutoScanMode>(
                          title: const Text('Deep Scan'),
                          subtitle: const Text(
                            'More thorough analysis. Slower but may find more locations.',
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
                            AiSettingsService.instance.setAutoScanMode(value);
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
                    AiSettingsService.instance.setAutoSetCategories(value);
                  },
                ),
              ],
            ),
    );
  }
}
