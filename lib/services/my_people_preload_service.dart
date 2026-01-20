import '../models/user_profile.dart';
import 'user_service.dart';

/// Service to preload My People screen data in the background.
/// This is a singleton that caches friend/follower/following data
/// so it's available immediately when the My People screen opens.
class MyPeoplePreloadService {
  static final MyPeoplePreloadService _instance = MyPeoplePreloadService._internal();
  factory MyPeoplePreloadService() => _instance;
  MyPeoplePreloadService._internal();

  final UserService _userService = UserService();

  // Cached data
  String? _cachedUserId;
  List<String> _friendIds = [];
  List<String> _followerIds = [];
  List<String> _followingIds = [];
  
  // Cached user profiles for each list
  Map<String, UserProfile> _cachedProfiles = {};
  
  bool _isLoading = false;
  bool _hasLoaded = false;
  DateTime? _lastLoadTime;
  
  // Cache expires after 5 minutes
  static const Duration _cacheExpiry = Duration(minutes: 5);

  // Getters
  List<String> get friendIds => _friendIds;
  List<String> get followerIds => _followerIds;
  List<String> get followingIds => _followingIds;
  Map<String, UserProfile> get cachedProfiles => _cachedProfiles;
  bool get hasLoaded => _hasLoaded;
  bool get isLoading => _isLoading;

  /// Check if cache is still valid for the given user
  bool isCacheValid(String userId) {
    if (_cachedUserId != userId) return false;
    if (!_hasLoaded) return false;
    if (_lastLoadTime == null) return false;
    return DateTime.now().difference(_lastLoadTime!) < _cacheExpiry;
  }

  /// Preload all My People data for the given user
  Future<void> preload(String userId) async {
    // Skip if already loading or cache is still valid
    if (_isLoading) return;
    if (isCacheValid(userId)) return;

    _isLoading = true;
    _cachedUserId = userId;

    try {
      // Load all IDs in parallel
      final results = await Future.wait([
        _userService.getFriendIds(userId),
        _userService.getFollowerIds(userId),
        _userService.getFollowingIds(userId),
      ]);

      _friendIds = results[0];
      _followerIds = results[1];
      _followingIds = results[2];

      // Collect all unique user IDs to preload profiles
      final allUserIds = <String>{
        ..._friendIds,
        ..._followerIds,
        ..._followingIds,
      };

      // Load all profiles in parallel
      if (allUserIds.isNotEmpty) {
        final profileFutures = allUserIds.map((id) => _userService.getUserProfile(id));
        final profiles = await Future.wait(profileFutures);
        
        _cachedProfiles = {};
        for (int i = 0; i < profiles.length; i++) {
          final profile = profiles.elementAt(i);
          if (profile != null) {
            _cachedProfiles[allUserIds.elementAt(i)] = profile;
          }
        }
      }

      _hasLoaded = true;
      _lastLoadTime = DateTime.now();
    } catch (e) {
      print('MyPeoplePreloadService: Error preloading data: $e');
    } finally {
      _isLoading = false;
    }
  }

  /// Invalidate the cache (call when data changes)
  void invalidateCache() {
    _hasLoaded = false;
    _lastLoadTime = null;
  }

  /// Clear all cached data
  void clear() {
    _cachedUserId = null;
    _friendIds = [];
    _followerIds = [];
    _followingIds = [];
    _cachedProfiles = {};
    _hasLoaded = false;
    _lastLoadTime = null;
    _isLoading = false;
  }
}
