import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'dart:io' show Platform;
import '../screens/receive_share_screen.dart';
import 'package:provider/provider.dart';
import '../providers/receive_share_provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/share_permission.dart';
import '../models/enums/share_enums.dart';
import '../screens/main_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  bool _isReceiveShareScreenOpen = false; // Flag to track if screen is open
  bool _isNavigatingToReceiveScreen = false; // Flag to prevent navigation conflicts
  bool isShareFlowActive = false; // ADDED: More robust lock for the share flow
  bool _navigatingAwayFromShare = false; // ADDED: Flag for post-save navigation window

  // ADDED: Public getter for _navigatingAwayFromShare
  bool get isNavigatingAwayFromShare => _navigatingAwayFromShare;
  
  // ADDED: Public getter for _isReceiveShareScreenOpen
  bool get isReceiveShareScreenOpen => _isReceiveShareScreenOpen;
  
  // ADDED: Public setter for _navigatingAwayFromShare (for MainScreen)
  void setNavigatingAwayFromShare(bool value) {
    _navigatingAwayFromShare = value;
  }
  
  // Helper method to check if shared files contain a Yelp URL
  bool _isYelpUrl(List<SharedMediaFile> files) {
    for (final file in files) {
      if (file.type == SharedMediaType.text || file.type == SharedMediaType.url) {
        String content = file.path.toLowerCase();
        if (content.contains('yelp.com/biz') || content.contains('yelp.to/')) {
          return true;
        }
      }
    }
    return false;
  }
  
  // Helper method to check if the new shared content is the same as current content
  bool _isSameSharedContent(List<SharedMediaFile> newFiles) {
    final currentFiles = _sharedFilesController.value;
    if (currentFiles == null || currentFiles.length != newFiles.length) {
      return false;
    }
    
    for (int i = 0; i < currentFiles.length; i++) {
      if (currentFiles[i].path != newFiles[i].path || 
          currentFiles[i].type != newFiles[i].type) {
        return false;
      }
    }
    
    return true;
  }

  ValueListenable<List<SharedMediaFile>?> get sharedFiles =>
      _sharedFilesController;
  
  // ADDED: Public access to shared files controller for special cases
  ValueNotifier<List<SharedMediaFile>?> get sharedFilesController => _sharedFilesController;

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Collection reference for share permissions
  CollectionReference get _sharePermissionsCollection =>
      _firestore.collection('share_permissions');

  // Helper to get the current user's ID
  String? get _currentUserId => _auth.currentUser?.uid;

  void init() {
    if (_isInitialized) {
      print("SHARE SERVICE: Already initialized, skipping");
      print("SHARE SERVICE: Current state - isShareFlowActive=$isShareFlowActive, _isReceiveShareScreenOpen=$_isReceiveShareScreenOpen");
      return;
    }

    print("SHARE SERVICE: Initializing sharing service");
    print("SHARE SERVICE: Initial state - isShareFlowActive=$isShareFlowActive, _isReceiveShareScreenOpen=$_isReceiveShareScreenOpen");
    _isInitialized = true;

    // Restore state from persistent storage
    _restoreShareFlowState();

    // Listen to media sharing coming from outside the app while the app is in the memory
    _setupIntentListener();

    // Check for initial intent immediately
    _checkInitialIntent();
    
    // Set up a delayed cleanup to handle any stale state that might remain
    _scheduleStaleStateCleanup();
  }

  // Restore share flow state from persistent storage
  Future<void> _restoreShareFlowState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final wasShareFlowActive = prefs.getBool('shareFlowActive') ?? false;
      final wasReceiveShareScreenOpen = prefs.getBool('receiveShareScreenOpen') ?? false;
      final wasNavigatingAway = prefs.getBool('navigatingAwayFromShare') ?? false;
      
      print("SHARE SERVICE: Restoring state - shareFlowActive=$wasShareFlowActive, receiveShareScreenOpen=$wasReceiveShareScreenOpen, navigatingAway=$wasNavigatingAway");
      
      // Only restore state if we're launching from a fresh share intent
      // Check if there's actually initial shared content to process
      final hasInitialContent = await _hasInitialSharedContent();
      
      if ((wasShareFlowActive || wasReceiveShareScreenOpen) && hasInitialContent) {
        isShareFlowActive = wasShareFlowActive;
        _isReceiveShareScreenOpen = wasReceiveShareScreenOpen;
        _navigatingAwayFromShare = wasNavigatingAway;
        print("SHARE SERVICE: Restored share flow state from persistent storage (has initial content)");
      } else {
        // If no initial content, clear any stale persistent state
        if (wasShareFlowActive || wasReceiveShareScreenOpen) {
          print("SHARE SERVICE: Clearing stale persistent state (no initial content to process)");
          await _clearPersistedShareFlowState();
        }
        print("SHARE SERVICE: No valid state to restore or no initial content");
      }
    } catch (e) {
      print("SHARE SERVICE: Error restoring share flow state: $e");
    }
  }
  
  // Helper method to check if we have initial shared content to process
  Future<bool> _hasInitialSharedContent() async {
    try {
      final initialMedia = await ReceiveSharingIntent.instance.getInitialMedia();
      return initialMedia.isNotEmpty;
    } catch (e) {
      print("SHARE SERVICE: Error checking for initial content: $e");
      return false;
    }
  }
  
  // Schedule a cleanup of stale state after app initialization
  void _scheduleStaleStateCleanup() {
    // Wait a few seconds after initialization to check for stale state
    Timer(Duration(seconds: 3), () async {
      if (isShareFlowActive || _isReceiveShareScreenOpen) {
        // Check if we actually have content to process
        final hasContent = await _hasInitialSharedContent();
        if (!hasContent && _sharedFilesController.value == null) {
          print("SHARE SERVICE: Cleaning up stale share flow state (no content found)");
          markShareFlowAsInactive();
        }
      }
    });
  }

  // Persist share flow state to storage
  Future<void> _persistShareFlowState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('shareFlowActive', isShareFlowActive);
      await prefs.setBool('receiveShareScreenOpen', _isReceiveShareScreenOpen);
      await prefs.setBool('navigatingAwayFromShare', _navigatingAwayFromShare);
      print("SHARE SERVICE: Persisted share flow state");
    } catch (e) {
      print("SHARE SERVICE: Error persisting share flow state: $e");
    }
  }

  // Clear persisted share flow state
  Future<void> _clearPersistedShareFlowState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('shareFlowActive');
      await prefs.remove('receiveShareScreenOpen');
      await prefs.remove('navigatingAwayFromShare');
      await prefs.remove('originalSharedContent');
      print("SHARE SERVICE: Cleared persisted share flow state");
    } catch (e) {
      print("SHARE SERVICE: Error clearing persisted share flow state: $e");
    }
  }

  // Persist original shared content for restore scenarios
  Future<void> _persistOriginalSharedContent() async {
    try {
      if (_sharedFilesController.value != null && _sharedFilesController.value!.isNotEmpty) {
        final prefs = await SharedPreferences.getInstance();
        // Convert shared files to a simple format we can persist
        final contentList = _sharedFilesController.value!.map((file) => {
          'path': file.path,
          'type': file.type.toString(),
        }).toList();
        final contentJson = contentList.map((item) => '${item['type']}|||${item['path']}').join('###');
        await prefs.setString('originalSharedContent', contentJson);
        print("SHARE SERVICE: Persisted original shared content");
      }
    } catch (e) {
      print("SHARE SERVICE: Error persisting original shared content: $e");
    }
  }

  // Get persisted original shared content (async version)
  Future<List<SharedMediaFile>?> getPersistedOriginalContent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final contentJson = prefs.getString('originalSharedContent');
      
      if (contentJson != null && contentJson.isNotEmpty) {
        print("SHARE SERVICE: Found persisted original content");
        final contentList = contentJson.split('###');
        final files = <SharedMediaFile>[];
        
        for (final item in contentList) {
          final parts = item.split('|||');
          if (parts.length == 2) {
            final typeStr = parts[0];
            final path = parts[1];
            
            SharedMediaType type = SharedMediaType.text;
            if (typeStr.contains('url')) {
              type = SharedMediaType.url;
            } else if (typeStr.contains('image')) {
              type = SharedMediaType.image;
            } else if (typeStr.contains('video')) {
              type = SharedMediaType.video;
            }
            
            files.add(SharedMediaFile(
              path: path,
              thumbnail: null,
              duration: null,
              type: type,
            ));
          }
        }
        
        return files.isNotEmpty ? files : null;
      }
      
      return null;
    } catch (e) {
      print("SHARE SERVICE: Error getting persisted original content: $e");
      return null;
    }
  }

  void _setupIntentListener() {
    // Cancel any existing subscription first
    _intentSub?.cancel();

    print("SHARE SERVICE: Setting up intent stream listener");

    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
        (List<SharedMediaFile> value) {
      print("SHARE SERVICE: Received shared files in stream: ${value.length}");
      if (value.isNotEmpty) {
        _sharedFilesController.value = List.from(value);

        if (_navigatingAwayFromShare) { // ADDED CHECK
          print("SHARE SERVICE: Currently navigating away from share, ignoring new stream event.");
          return;
        }
        if (isShareFlowActive) {
          print("SHARE SERVICE: Share flow is currently active. Checking content type and differences...");
          
          bool isSameContent = _isSameSharedContent(value);
          bool isYelpUrl = _isYelpUrl(value);
          
          if (isSameContent) {
            print("SHARE SERVICE: Same content - existing screen should handle.");
            return;
          } else if (isYelpUrl && _isReceiveShareScreenOpen) {
            print("SHARE SERVICE: New Yelp URL while receive share screen is open. Updating existing screen.");
            _sharedFilesController.value = List.from(value);
            return;
          } else if (!isYelpUrl) {
            print("SHARE SERVICE: New non-Yelp content detected in stream. Attempting to show new share screen.");
            if (_lastKnownContext != null) {
              showReceiveShareScreen(_lastKnownContext!, value);
            }
          } else {
            print("SHARE SERVICE: New Yelp URL but receive share screen not confirmed open. Proceeding with normal flow.");
          }
          return;
        }
        if (_lastKnownContext != null && !_isReceiveShareScreenOpen && !_isNavigatingToReceiveScreen) {
          print(
              "SHARE SERVICE: Attempting to navigate to ReceiveShareScreen with ${value.length} files (isShareFlowActive: $isShareFlowActive)");
          showReceiveShareScreen(_lastKnownContext!, value).then((_) {
          }).catchError((e) {
            isShareFlowActive = false;
            print("SHARE SERVICE: Navigation error: $e");
          });
        } else if (_isReceiveShareScreenOpen) {
          // print("SHARE SERVICE: ReceiveShareScreen is already open (_isReceiveShareScreenOpen=true). Updating sharedFiles controller."); // COMMENTED OUT
        } else if (_isNavigatingToReceiveScreen) {
          print("SHARE SERVICE: Already navigating to ReceiveShareScreen (_isNavigatingToReceiveScreen=true). Ignoring new stream event.");
        } else {
          print("SHARE SERVICE: No context available for navigation, or other flags preventing it.");
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

      if (initialMedia.isNotEmpty) {
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
    
    // Reset the flag that tracks if the screen is open
    _isReceiveShareScreenOpen = false;
    print("SHARE SERVICE: Reset _isReceiveShareScreenOpen flag to false");

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

  // Show the receive share screen as a modal bottom sheet or full screen
  Future<void> showReceiveShareScreen(
      BuildContext context, List<SharedMediaFile> files) async {
    print("SHARE SERVICE DEBUG: showReceiveShareScreen called with ${files.length} files");
    print("SHARE SERVICE DEBUG: isShareFlowActive=$isShareFlowActive, _isReceiveShareScreenOpen=$_isReceiveShareScreenOpen");
    
    // If we think a share flow is active but this is a new share intent,
    // we should handle it appropriately based on the content type
    if (isShareFlowActive && _isReceiveShareScreenOpen) {
      print("SHARE SERVICE: Flow marked as active but received new share. Analyzing content...");
      
      bool isSameContent = _isSameSharedContent(files);
      bool isYelpUrl = _isYelpUrl(files);
      
      if (isSameContent) {
        // Same content - just update existing screen
        print("SHARE SERVICE: Same content detected. Flow active and screen open. isYelpUrl=$isYelpUrl. Updating files in existing screen.");
        _sharedFilesController.value = List.from(files);
        return;
      } else if (isYelpUrl) {
        // Different Yelp URL - update existing screen (don't open new one)
        print("SHARE SERVICE: New Yelp URL detected while screen is open. Updating existing screen instead of opening new one.");
        _sharedFilesController.value = List.from(files);
        return;
      } else {
        // Different non-Yelp content - reset and open new screen
        print("SHARE SERVICE: New non-Yelp content detected. Resetting share flow state and proceeding with new share.");
        markShareFlowAsInactive();
        // Allow the method to continue with the new share
      }
    }
    if (_isNavigatingToReceiveScreen) { // Prevent re-entry if already navigating
        print("SHARE SERVICE: showReceiveShareScreen called, but already navigating. Ignoring.");
        return;
    }
    
    print("SHARE SERVICE: showReceiveShareScreen called with ${files.length} files. isShareFlowActive: $isShareFlowActive");
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (context.mounted) {
      print("SHARE SERVICE DEBUG: Setting isShareFlowActive=true and _isReceiveShareScreenOpen=true");
      isShareFlowActive = true; // Set lock BEFORE navigating
      _isReceiveShareScreenOpen = true; // Set flag before push
      _isNavigatingToReceiveScreen = true;
      
      // Persist state so it survives app restarts
      _persistShareFlowState();
      
      try {
        final receiveShareProvider = ReceiveShareProvider();
        
        await Navigator.push(
          context,
          MaterialPageRoute(
            settings: const RouteSettings(name: '/receiveShareScreen'),
            builder: (buildContext) => ChangeNotifierProvider<ReceiveShareProvider>.value(
              value: receiveShareProvider,
              child: ReceiveShareScreen(
                sharedFiles: files,
                onCancel: () {
                  print("SHARE SERVICE: onCancel called from ReceiveShareScreen. Navigating to MainScreen.");
                  markShareFlowAsInactive();
                  Navigator.pushAndRemoveUntil(
                    buildContext, 
                    MaterialPageRoute(builder: (ctx) => const MainScreen()),
                    (Route<dynamic> route) => false,
                  );
                },
              ),
            ),
          ),
        );
        print("SHARE SERVICE: Navigator.push for ReceiveShareScreen finished.");
      } catch (e) {
        print("SHARE SERVICE: Error showing ReceiveShareScreen: $e");
        isShareFlowActive = false; // Release lock on error
      } finally {
        // _isReceiveShareScreenOpen = false; // This should be set by ReceiveShareScreen's dispose or onWillPop
        _isNavigatingToReceiveScreen = false;
        // markShareFlowAsInactive(); // This should be called by ReceiveShareScreen when it's done.
        print("SHARE SERVICE: showReceiveShareScreen finally block. isShareFlowActive: $isShareFlowActive");
      }
    } else {
      print("SHARE SERVICE: Context is no longer mounted in showReceiveShareScreen!");
      isShareFlowActive = false; // Release lock if context is bad
    }
  }

  // MODIFIED: Method to signal share flow completion and reset relevant flags
  void markShareFlowAsInactive() {
    print("SHARE SERVICE: Marking share flow as inactive (e.g. cancel/back).");
    isShareFlowActive = false;
    _isReceiveShareScreenOpen = false;
    _isNavigatingToReceiveScreen = false;
    // _navigatingAwayFromShare should be false here, or reset by shareNavigationComplete
    resetSharedItems();
    
    // Clear persisted state since flow is ending
    _clearPersistedShareFlowState();
  }

  // ADDED: Method to signal navigation away from share is starting
  void prepareToNavigateAwayFromShare() {
    print("SHARE SERVICE: Preparing to navigate away from share flow.");
    _navigatingAwayFromShare = true;
    isShareFlowActive = false; // Flow is ending
    _isReceiveShareScreenOpen = false;
    _isNavigatingToReceiveScreen = false;
    resetSharedItems(); // Reset items as we are leaving the screen
  }
  
  // ADDED: Method specifically for when user taps external button (like Yelp) but we want to preserve the flow
  void temporarilyLeavingForExternalApp() {
    print("SHARE SERVICE: Temporarily leaving for external app (e.g. Yelp button). Preserving flow state.");
    _navigatingAwayFromShare = true;
    // DON'T reset isShareFlowActive or _isReceiveShareScreenOpen - we want to preserve them
    // DON'T reset shared items - we want to keep the existing state
    
    // Persist the current state AND original shared content so it survives app restart
    _persistShareFlowState();
    _persistOriginalSharedContent();
  }

  // ADDED: Method to signal navigation away from share is complete
  void shareNavigationComplete() {
    print("SHARE SERVICE: Navigation away from share flow complete.");
    _navigatingAwayFromShare = false;
    
    // Clear all persistent state now that we're done with the share flow
    _clearPersistedShareFlowState();
    
    // isShareFlowActive should be false already if prepareToNavigateAwayFromShare was called.
    // Try an additional reset here, now that MainScreen is active.
    print("SHARE SERVICE: Attempting final intent reset from shareNavigationComplete.");
    ReceiveSharingIntent.instance.reset(); 
  }

  /// Shares an item (Experience or UserCategory) with another user.
  ///
  /// If a share already exists for this item and user, it updates the access level.
  /// Otherwise, it creates a new share permission.
  Future<void> shareItem({
    required String itemId,
    required ShareableItemType itemType,
    required String ownerUserId, // The ID of the user who owns the item
    required String sharedWithUserId, // The ID of the user to share with
    required ShareAccessLevel accessLevel, // The access level to grant
  }) async {
    final currentUserId = _currentUserId;
    if (currentUserId == null) {
      throw Exception('User not authenticated');
    }
    // Optional: Add check if currentUserId == ownerUserId?

    final now = Timestamp.now();

    // Check if a permission already exists for this specific item and user combination
    final existingQuery = await _sharePermissionsCollection
        .where('itemId', isEqualTo: itemId)
        .where('sharedWithUserId', isEqualTo: sharedWithUserId)
        .limit(1)
        .get();

    if (existingQuery.docs.isNotEmpty) {
      // Update existing permission
      final existingDocId = existingQuery.docs.first.id;
      print(
          'Updating existing share permission $existingDocId for item $itemId with user $sharedWithUserId');
      await _sharePermissionsCollection.doc(existingDocId).update({
        'accessLevel': _accessLevelToString(accessLevel),
        'updatedAt': now, // Use Timestamp.now() for update
      });
    } else {
      // Create new permission
      print(
          'Creating new share permission for item $itemId with user $sharedWithUserId');
      final newPermission = SharePermission(
        id: '', // Firestore generates the ID
        itemId: itemId,
        itemType: itemType,
        ownerUserId: ownerUserId,
        sharedWithUserId: sharedWithUserId,
        accessLevel: accessLevel,
        createdAt: now,
        updatedAt: now,
      );
      final data = newPermission.toMap();
      // Ensure timestamps are set correctly for creation
      data['createdAt'] = FieldValue.serverTimestamp();
      data['updatedAt'] = FieldValue.serverTimestamp();

      await _sharePermissionsCollection.add(data);
    }
  }

  /// Retrieves all items shared *with* the specified user.
  Future<List<SharePermission>> getSharedItemsForUser(String userId) async {
    final snapshot = await _sharePermissionsCollection
        .where('sharedWithUserId', isEqualTo: userId)
        // Optional: Order by createdAt or updatedAt?
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs
        .map((doc) => SharePermission.fromFirestore(doc))
        .toList();
  }

  /// Retrieves all permissions granted *for* a specific item.
  Future<List<SharePermission>> getPermissionsForItem(String itemId) async {
    final snapshot = await _sharePermissionsCollection
        .where('itemId', isEqualTo: itemId)
        .get();

    return snapshot.docs
        .map((doc) => SharePermission.fromFirestore(doc))
        .toList();
  }

  /// Retrieves a specific permission for a user and item combination.
  /// Returns null if no permission exists.
  Future<SharePermission?> getPermissionForUserAndItem({
    required String userId,
    required String itemId,
  }) async {
    final snapshot = await _sharePermissionsCollection
        .where('sharedWithUserId', isEqualTo: userId)
        .where('itemId', isEqualTo: itemId)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      return null;
    }
    return SharePermission.fromFirestore(snapshot.docs.first);
  }

  /// Updates the access level of an existing share permission.
  Future<void> updatePermissionAccessLevel({
    required String permissionId,
    required ShareAccessLevel newAccessLevel,
  }) async {
    // Optional: Add check to ensure current user is the owner of the item?
    await _sharePermissionsCollection.doc(permissionId).update({
      'accessLevel': _accessLevelToString(newAccessLevel),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Removes a share permission (unshares the item).
  Future<void> removeShare(String permissionId) async {
    // Optional: Add check to ensure current user is the owner or the shared user?
    await _sharePermissionsCollection.doc(permissionId).delete();
  }

  // Helper to convert ShareAccessLevel enum to string for Firestore
  String _accessLevelToString(ShareAccessLevel level) {
    return level == ShareAccessLevel.edit ? 'edit' : 'view';
  }

  // Consider adding methods to fetch the actual shared Experience/UserCategory objects
  // based on the SharePermission list, potentially combining data.
}
