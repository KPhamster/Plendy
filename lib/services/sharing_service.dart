import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'dart:io' show Platform;
import '../screens/receive_share_screen.dart';
import 'package:provider/provider.dart';
import '../providers/receive_share_provider.dart';

class SharingService {
  static final SharingService _instance = SharingService._internal();

  factory SharingService() {
    return _instance;
  }

  SharingService._internal();

  final _sharedFilesController = ValueNotifier<List<SharedMediaFile>?>(null);
  StreamSubscription? _intentSub;
  BuildContext?
      _lastKnownContext; // Store the last known context for navigation
  bool _isInitialized = false;

  ValueListenable<List<SharedMediaFile>?> get sharedFiles =>
      _sharedFilesController;

  void init() {
    if (_isInitialized) {
      print("SHARE SERVICE: Already initialized, skipping");
      return;
    }

    print("SHARE SERVICE: Initializing sharing service");
    _isInitialized = true;

    // Listen to media sharing coming from outside the app while the app is in the memory
    _setupIntentListener();

    // Check for initial intent immediately
    _checkInitialIntent();
  }

  void _setupIntentListener() {
    // Cancel any existing subscription first
    _intentSub?.cancel();

    print("SHARE SERVICE: Setting up intent stream listener");

    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
        (List<SharedMediaFile> value) {
      print("SHARE SERVICE: Received shared files in stream: ${value.length}");
      if (value.isNotEmpty) {
        print("SHARE SERVICE: First file path: ${value.first.path}");
        _sharedFilesController.value = List.from(value);

        // If we have a context, navigate directly to the receive screen
        if (_lastKnownContext != null) {
          // Use a short delay to ensure we're not in the middle of a build cycle
          Future.delayed(Duration(milliseconds: 100), () {
            print(
                "SHARE SERVICE: Navigating to ReceiveShareScreen with ${value.length} files");
            showReceiveShareScreen(_lastKnownContext!, value);
          });
        } else {
          print("SHARE SERVICE: No context available for navigation");
        }
      }
    }, onError: (err) {
      print("SHARE SERVICE: getIntentDataStream error: $err");
    });
  }

  Future<void> _checkInitialIntent() async {
    print("SHARE SERVICE: Checking for initial intent");
    try {
      final initialMedia =
          await ReceiveSharingIntent.instance.getInitialMedia();

      if (initialMedia != null && initialMedia.isNotEmpty) {
        print(
            "SHARE SERVICE: Found initial intent with ${initialMedia.length} files");
        print("SHARE SERVICE: First file path: ${initialMedia.first.path}");
        _sharedFilesController.value = List.from(initialMedia);

        // We'll let the app handle navigation based on this data
      } else {
        print("SHARE SERVICE: No initial intent found");
      }
    } catch (e) {
      print("SHARE SERVICE: Error checking initial intent: $e");
    }
  }

  void dispose() {
    print("SHARE SERVICE: Disposing sharing service");
    _intentSub?.cancel();
    _isInitialized = false;
  }

  // Reset after handling
  void resetSharedItems() {
    print("SHARE SERVICE: Resetting shared items");
    _sharedFilesController.value = null;

    // Only reset for Android - iOS needs the intent to persist
    if (!Platform.isIOS) {
      ReceiveSharingIntent.instance.reset();

      // Force a short delay and then reset again to ensure complete cleanup
      Future.delayed(Duration(milliseconds: 200), () {
        ReceiveSharingIntent.instance.reset();
        print("SHARE SERVICE: Secondary share intent reset completed");
      });

      print("SHARE SERVICE: Share intent reset completed");
    } else {
      print(
          "SHARE SERVICE: On iOS - not resetting intent to ensure it persists");
    }
  }

  // Recreate listeners after app resume
  void recreateListeners() {
    print("SHARE SERVICE: Recreating intent listeners");
    _setupIntentListener();
    _checkInitialIntent();
  }

  // Store context for later use
  void setContext(BuildContext context) {
    _lastKnownContext = context;
    print("SHARE SERVICE: Context updated");
  }

  // Show the receive share screen
  void showReceiveShareScreen(
      BuildContext context, List<SharedMediaFile> sharedFiles) {
    print('SHARING SERVICE: Showing ReceiveShareScreen');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChangeNotifierProvider(
          create: (_) => ReceiveShareProvider(),
          child: ReceiveShareScreen(
            sharedFiles: sharedFiles,
            onCancel: () {
              print(
                  'SHARING SERVICE: ReceiveShareScreen cancelled, resetting intent.');
              resetSharedItems();
              Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }
}
