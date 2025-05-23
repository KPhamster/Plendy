import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';

class NotificationStateService extends ChangeNotifier {
  static final NotificationStateService _instance = NotificationStateService._internal();
  factory NotificationStateService() => _instance;
  NotificationStateService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Last seen timestamps
  DateTime? _lastSeenFollowers;
  DateTime? _lastSeenFollowRequests;
  
  // Current user ID
  String? _currentUserId;
  
  // Streams for real-time data
  StreamSubscription? _followersSubscription;
  StreamSubscription? _followRequestsSubscription;
  
  // Counts of unseen items
  int _unseenFollowersCount = 0;
  int _unseenFollowRequestsCount = 0;
  
  // Lists of unseen item IDs
  Set<String> _unseenFollowerIds = {};
  Set<String> _unseenFollowRequestIds = {};
  
  // Cached sets of previously seen followers
  Set<String> _seenFollowerIds = {};

  // Getters
  bool get hasUnseenFollowers => _unseenFollowersCount > 0;
  bool get hasUnseenFollowRequests => _unseenFollowRequestsCount > 0;
  bool get hasAnyUnseen => hasUnseenFollowers || hasUnseenFollowRequests;
  
  int get unseenFollowersCount => _unseenFollowersCount;
  int get unseenFollowRequestsCount => _unseenFollowRequestsCount;
  
  Set<String> get unseenFollowerIds => Set.from(_unseenFollowerIds);
  Set<String> get unseenFollowRequestIds => Set.from(_unseenFollowRequestIds);

  /// Initialize for a specific user
  Future<void> initializeForUser(String userId) async {
    if (_currentUserId == userId) return; // Already initialized for this user
    
    _currentUserId = userId;
    await _loadLastSeenTimestamps();
    _startListening();
  }

  /// Load last seen timestamps from SharedPreferences
  Future<void> _loadLastSeenTimestamps() async {
    if (_currentUserId == null) return;
    
    final prefs = await SharedPreferences.getInstance();
    final followersTimestamp = prefs.getInt('last_seen_followers_$_currentUserId');
    final requestsTimestamp = prefs.getInt('last_seen_requests_$_currentUserId');
    
    _lastSeenFollowers = followersTimestamp != null 
        ? DateTime.fromMillisecondsSinceEpoch(followersTimestamp)
        : null;
    _lastSeenFollowRequests = requestsTimestamp != null
        ? DateTime.fromMillisecondsSinceEpoch(requestsTimestamp)
        : null;
    
    // Load seen follower IDs
    final seenFollowersList = prefs.getStringList('seen_followers_$_currentUserId') ?? [];
    _seenFollowerIds = Set.from(seenFollowersList);
  }

  /// Start listening to real-time changes
  void _startListening() {
    if (_currentUserId == null) return;
    
    _stopListening(); // Stop any existing subscriptions
    
    // Listen to followers changes
    _followersSubscription = _firestore
        .collection('users')
        .doc(_currentUserId)
        .collection('followers')
        .snapshots()
        .listen(_handleFollowersChange);
    
    // Listen to follow requests changes
    _followRequestsSubscription = _firestore
        .collection('users')
        .doc(_currentUserId)
        .collection('followRequests')
        .snapshots()
        .listen(_handleFollowRequestsChange);
  }

  /// Stop listening to changes
  void _stopListening() {
    _followersSubscription?.cancel();
    _followRequestsSubscription?.cancel();
    _followersSubscription = null;
    _followRequestsSubscription = null;
  }

  /// Handle followers collection changes
  void _handleFollowersChange(QuerySnapshot snapshot) {
    Set<String> currentFollowerIds = snapshot.docs.map((doc) => doc.id).toSet();
    
    if (_seenFollowerIds.isEmpty) {
      // First time initialization - mark all current followers as seen
      _seenFollowerIds = Set.from(currentFollowerIds);
      _unseenFollowerIds.clear();
      _unseenFollowersCount = 0;
    } else {
      // Find new followers (those not in the seen set)
      _unseenFollowerIds = currentFollowerIds.difference(_seenFollowerIds);
      _unseenFollowersCount = _unseenFollowerIds.length;
    }
    
    notifyListeners();
  }

  /// Handle follow requests collection changes
  void _handleFollowRequestsChange(QuerySnapshot snapshot) {
    if (_lastSeenFollowRequests == null) {
      // First time - mark everything as seen
      _unseenFollowRequestIds.clear();
      _unseenFollowRequestsCount = 0;
    } else {
      Set<String> newUnseenIds = {};
      
      for (var doc in snapshot.docs) {
        // Safely cast the data to Map<String, dynamic> to avoid type casting errors
        final rawData = doc.data();
        final data = rawData != null ? Map<String, dynamic>.from(rawData as Map<dynamic, dynamic>) : null;
        final requestedAt = data?['requestedAt'] as Timestamp?;
        
        if (requestedAt != null) {
          final requestTime = requestedAt.toDate();
          if (requestTime.isAfter(_lastSeenFollowRequests!)) {
            newUnseenIds.add(doc.id);
          }
        }
      }
      
      _unseenFollowRequestIds = newUnseenIds;
      _unseenFollowRequestsCount = _unseenFollowRequestIds.length;
    }
    
    notifyListeners();
  }

  /// Mark followers as seen (when user visits followers tab)
  Future<void> markFollowersAsSeen() async {
    if (_currentUserId == null) return;
    
    // Get current followers and mark them all as seen
    final snapshot = await _firestore
        .collection('users')
        .doc(_currentUserId)
        .collection('followers')
        .get();
    
    _seenFollowerIds = snapshot.docs.map((doc) => doc.id).toSet();
    _lastSeenFollowers = DateTime.now();
    _unseenFollowerIds.clear();
    _unseenFollowersCount = 0;
    
    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_seen_followers_$_currentUserId', _lastSeenFollowers!.millisecondsSinceEpoch);
    await prefs.setStringList('seen_followers_$_currentUserId', _seenFollowerIds.toList());
    
    notifyListeners();
  }

  /// Mark follow requests as seen (when user visits follow requests screen)
  Future<void> markFollowRequestsAsSeen() async {
    if (_currentUserId == null) return;
    
    _lastSeenFollowRequests = DateTime.now();
    _unseenFollowRequestIds.clear();
    _unseenFollowRequestsCount = 0;
    
    // Save to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_seen_requests_$_currentUserId', _lastSeenFollowRequests!.millisecondsSinceEpoch);
    
    notifyListeners();
  }

  /// Clean up when user logs out
  void cleanup() {
    _stopListening();
    _currentUserId = null;
    _lastSeenFollowers = null;
    _lastSeenFollowRequests = null;
    _unseenFollowerIds.clear();
    _unseenFollowRequestIds.clear();
    _seenFollowerIds.clear(); // Clear seen follower IDs
    _unseenFollowersCount = 0;
    _unseenFollowRequestsCount = 0;
    notifyListeners();
  }

  @override
  void dispose() {
    cleanup();
    super.dispose();
  }
} 