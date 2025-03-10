import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class SharingService {
  static final SharingService _instance = SharingService._internal();
  
  factory SharingService() {
    return _instance;
  }
  
  SharingService._internal();
  
  final _sharedFilesController = ValueNotifier<List<SharedMediaFile>>([]);
  late StreamSubscription _intentSub;
  
  ValueListenable<List<SharedMediaFile>> get sharedFiles => _sharedFilesController;
  
  void init() {
    // Listen to media sharing coming from outside the app while the app is in the memory
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen((List<SharedMediaFile> value) {
      _sharedFilesController.value = List.from(value);
      print("Received shared files: ${value.map((f) => f.toMap())}");
    }, onError: (err) {
      print("getIntentDataStream error: $err");
    });
    
    // Get the media sharing coming from outside the app while the app is closed
    ReceiveSharingIntent.instance.getInitialMedia().then((List<SharedMediaFile> value) {
      _sharedFilesController.value = List.from(value);
      print("Initial shared files: ${value.map((f) => f.toMap())}");
      // Tell the library that we are done processing the intent
      ReceiveSharingIntent.instance.reset();
    });
  }
  
  void dispose() {
    _intentSub.cancel();
  }
  
  // Reset after handling
  void resetSharedItems() {
    _sharedFilesController.value = [];
    ReceiveSharingIntent.instance.reset();
  }
}
