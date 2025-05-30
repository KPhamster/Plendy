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

  ValueListenable<List<SharedMediaFile>?> get sharedFiles =>
      _sharedFilesController;

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
        _sharedFilesController.value = List.from(value);

        if (_navigatingAwayFromShare) { // ADDED CHECK
          print("SHARE SERVICE: Currently navigating away from share, ignoring new stream event.");
          return;
        }
        if (isShareFlowActive) {
          print("SHARE SERVICE: Share flow is currently active. New intent data stored. Existing screen should handle or ignore.");
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
    if (isShareFlowActive && _isReceiveShareScreenOpen) { // Check if already active and screen is open
      // print("SHARE SERVICE: showReceiveShareScreen called, but flow is active and screen is open. Updating files."); // COMMENTED OUT - Too noisy
      _sharedFilesController.value = List.from(files); // Update files for existing screen
      return;
    }
    if (_isNavigatingToReceiveScreen) { // Prevent re-entry if already navigating
        print("SHARE SERVICE: showReceiveShareScreen called, but already navigating. Ignoring.");
        return;
    }
    
    print("SHARE SERVICE: showReceiveShareScreen called with ${files.length} files. isShareFlowActive: $isShareFlowActive");
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    if (context.mounted) {
      isShareFlowActive = true; // Set lock BEFORE navigating
      _isReceiveShareScreenOpen = true; // Set flag before push
      _isNavigatingToReceiveScreen = true;
      
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

  // ADDED: Method to signal navigation away from share is complete
  void shareNavigationComplete() {
    print("SHARE SERVICE: Navigation away from share flow complete.");
    _navigatingAwayFromShare = false;
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
