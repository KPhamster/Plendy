import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_constants.dart';

typedef ShareBottomSheetCreateLinkCallback = Future<void> Function({
  required String shareMode,
  required bool giveEditAccess,
});

Future<T?> showShareExperienceBottomSheet<T>({
  required BuildContext context,
  required VoidCallback onDirectShare,
  required ShareBottomSheetCreateLinkCallback onCreateLink,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) {
      return ShareExperienceBottomSheetContent(
        onDirectShare: onDirectShare,
        onCreateLink: onCreateLink,
      );
    },
  );
}

class ShareExperienceBottomSheetContent extends StatefulWidget {
  const ShareExperienceBottomSheetContent({
    super.key,
    required this.onDirectShare,
    required this.onCreateLink,
  });

  final VoidCallback onDirectShare;
  final ShareBottomSheetCreateLinkCallback onCreateLink;

  @override
  State<ShareExperienceBottomSheetContent> createState() =>
      _ShareExperienceBottomSheetContentState();
}

class _ShareExperienceBottomSheetContentState
    extends State<ShareExperienceBottomSheetContent> {
  String _shareMode = 'separate_copy'; // 'my_copy' | 'separate_copy'
  bool _giveEditAccess = false;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _loadLastChoice();
  }

  Future<void> _loadLastChoice() async {
    final prefs = await SharedPreferences.getInstance();
    final lastMode = prefs.getString(AppConstants.lastShareModeKey);
    final lastEdit = prefs.getBool(AppConstants.lastShareGiveEditAccessKey);
    if (!mounted) return;
    setState(() {
      _shareMode = lastMode ?? 'separate_copy';
      _giveEditAccess = lastEdit ?? false;
    });
  }

  Future<void> _persistChoice() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.lastShareModeKey, _shareMode);
    await prefs.setBool(
        AppConstants.lastShareGiveEditAccessKey, _giveEditAccess);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Share Experience',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.send_outlined),
              title: const Text('Share to Plendy friends'),
              onTap: () async {
                await _persistChoice();
                if (!mounted) return;
                Navigator.of(context).pop();
                widget.onDirectShare();
              },
            ),
            ListTile(
              leading: _creating
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link_outlined),
              title:
                  Text(_creating ? 'Creating link...' : 'Get shareable link'),
              onTap: _creating
                  ? null
                  : () async {
                      setState(() => _creating = true);
                      try {
                        await _persistChoice();
                        await widget.onCreateLink(
                          shareMode: _shareMode,
                          giveEditAccess:
                              _shareMode == 'my_copy' ? _giveEditAccess : false,
                        );
                      } finally {
                        if (mounted) {
                          setState(() => _creating = false);
                        }
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }
}
