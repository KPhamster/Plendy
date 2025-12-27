import 'package:flutter/material.dart';
import '../config/colors.dart';
import '../services/instagram_settings_service.dart';

enum InstagramDisplayOption { defaultView, webView }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  InstagramDisplayOption _instagramDisplay =
      InstagramDisplayOption.defaultView;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settingsService = InstagramSettingsService.instance;
    final option = await settingsService.getDisplayOption();
    if (mounted) {
      setState(() {
        _instagramDisplay = option == 'webview'
            ? InstagramDisplayOption.webView
            : InstagramDisplayOption.defaultView;
        _isLoading = false;
      });
    }
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
                    'No login required. Some content cannot be played in-app and will '
                    'open in Instagram.',
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
                    'Requires Instagram login in the in-app browser. Provides a '
                    'better view and plays all content in-app.',
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
              ],
            ),
    );
  }
}
