import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../screens/receive_share_screen.dart';

class SharingService {
  static final SharingService _instance = SharingService._internal();
  
  factory SharingService() {
    return _instance;
  }
  
  SharingService._internal();
  
  final _sharedFilesController = ValueNotifier<List<SharedMediaFile>?>(null);
  late StreamSubscription _intentSub;
  BuildContext? _lastKnownContext; // Store the last known context for navigation
  
  ValueListenable<List<SharedMediaFile>?> get sharedFiles => _sharedFilesController;
  
  void init() {
    // Listen to media sharing coming from outside the app while the app is in the memory
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        _sharedFilesController.value = List.from(value);
        print("Received shared files: ${value.map((f) => f.toMap())}");
        
        // If we have a context, navigate directly to the receive screen
        if (_lastKnownContext != null) {
          // Use a short delay to ensure we're not in the middle of a build cycle
          Future.delayed(Duration(milliseconds: 100), () {
            showReceiveShareScreen(_lastKnownContext!, value);
          });
        }
      }
    }, onError: (err) {
      print("getIntentDataStream error: $err");
    });
    
    // Note: Initial media is now handled in the MyApp widget for a better flow
    // when the app is launched from a share
  }
  
  void dispose() {
    _intentSub.cancel();
  }
  
  // Reset after handling
  void resetSharedItems() {
    _sharedFilesController.value = null;
    ReceiveSharingIntent.instance.reset();
  }
  
  // Store context for later use
  void setContext(BuildContext context) {
    _lastKnownContext = context;
  }
  
  // Show the receive share screen
  void showReceiveShareScreen(BuildContext context, List<SharedMediaFile> files) {
    _lastKnownContext = context; // Store context for future use
    
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ReceiveShareScreen(
          sharedFiles: files,
          onCancel: () {
            resetSharedItems();
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }
}
