import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For MethodChannel
import 'dart:math' as math;
import 'dart:io';
import 'dart:convert';
// import 'package:path_provider/path_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:share_handler/share_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // FCM Import
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // Local Notifications Import
import 'screens/auth_screen.dart';
import 'screens/main_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/receive_share_screen.dart';
import 'screens/follow_requests_screen.dart'; // Import FollowRequestsScreen
import 'screens/messages_screen.dart'; // Import MessagesScreen
import 'screens/chat_screen.dart'; // Import ChatScreen
import 'services/auth_service.dart';
import 'services/sharing_service.dart';
import 'services/foreground_scan_service.dart'; // Import ForegroundScanService for background AI scans
import 'services/event_service.dart'; // Import EventService
import 'services/experience_service.dart'; // Import ExperienceService
import 'models/shared_media_compat.dart';
import 'models/message_thread.dart'; // Import MessageThread
import 'models/experience.dart'; // Import Experience
import 'models/event.dart'; // Import Event
import 'models/user_category.dart'; // Import UserCategory
import 'models/color_category.dart'; // Import ColorCategory
import 'services/notification_state_service.dart'; // Import NotificationStateService
import 'widgets/event_editor_modal.dart'; // Import EventEditorModal
import 'package:provider/provider.dart';
import 'providers/receive_share_provider.dart';
import 'providers/category_save_progress_notifier.dart';
import 'dart:async'; // Import dart:async for StreamSubscription
import 'services/google_maps_service.dart'; // ADDED: Import GoogleMapsService
import 'services/discovery_cover_service.dart'; // Import DiscoveryCoverService
import 'firebase_options.dart'; // Import Firebase options
import 'package:flutter/foundation.dart'
    show kIsWeb, kReleaseMode; // Import kIsWeb, kReleaseMode
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:app_links/app_links.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:google_fonts/google_fonts.dart';
import 'screens/share_preview_screen.dart';
import 'screens/category_share_preview_screen.dart';
import 'screens/public_profile_screen.dart';
import 'providers/discovery_share_coordinator.dart';
import 'screens/discovery_share_preview_screen.dart';
import 'screens/data_deletion_screen.dart';
import 'screens/email_verification_screen.dart';
// Define a GlobalKey for the Navigator
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Debug logging function for cold start issues
// _writeDebugLog disabled (unused)

// Initialize FlutterLocalNotificationsPlugin (if you want to show foreground notifications)
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// Track recently received message IDs to prevent duplicates (iOS issue)
final Set<String> _recentlyReceivedMessageIds = {};

// FCM: Background message handler (must be a top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions
        .currentPlatform, // Ensure Firebase is initialized here too
  );
  print("Handling a background message: ${message.messageId}");
  print("Background Message data: ${message.data}");
  if (message.notification != null) {
    print(
        'Background message also contained a notification: ${message.notification}');
    // You could potentially show a local notification here if needed for background messages,
    // but often the system tray notification from FCM is sufficient and desired.
  }
}

// DEBUG: Function to periodically check for shared data
void _startShareDebugTimer() {
  print("DEBUG: Starting share debug timer...");

  // Check immediately
  _checkForSharedData();

  // Then check every 2 seconds
  Timer.periodic(Duration(seconds: 2), (timer) {
    _checkForSharedData();
  });
}

// DEBUG: Check for shared data from receive_sharing_intent
Future<void> _checkForSharedData() async {
  try {
    // First, check app group UserDefaults directly (iOS specific)
    if (Platform.isIOS) {
      _debugCheckAppGroup();
    }

    // Check initial media (for when app was closed)
    final initial = await ShareHandlerPlatform.instance.getInitialSharedMedia();
    if (initial != null &&
        ((initial.content?.isNotEmpty ?? false) ||
            (initial.attachments?.isNotEmpty ?? false))) {
      final files = _convertSharedMedia(initial);
      //print("🎯 DEBUG: Found INITIAL shared data: ${files.length} items");
      for (var item in files) {
        //print("🎯 DEBUG: ${item.type}: ${item.path}");
      }
      // Shared content received - no toast needed
    }

    // Note: URL/text are delivered via getInitialMedia as SharedMediaType.text on iOS

    // Also check the stream for live updates
    ShareHandlerPlatform.instance.sharedMediaStream.listen((media) {
      final value = _convertSharedMedia(media);
      if (value.isNotEmpty) {
        //print("🎯 DEBUG: Found STREAM shared data: ${value.length} items");
        for (var item in value) {
          //print("🎯 DEBUG: ${item.type}: ${item.path}");
        }
        // Stream shared content received - no toast needed
      }
    });

    // Note: URL/text stream is delivered via getMediaStream as SharedMediaType.text on iOS
  } catch (e) {
    print("DEBUG: Error checking for shared data: $e");
  }
}

// DEBUG: Check iOS App Group directly
void _debugCheckAppGroup() {
  print("📱 DEBUG: Checking iOS App Group data...");
  // This is just logging - the actual check happens in native code
  // The receive_sharing_intent plugin reads from UserDefaults(suiteName: "group.com.plendy.app")
  // with keys "ShareKey" and "ShareKey#data"
}

/// Open a chat screen from a notification
Future<void> _openChatFromNotification(String threadId) async {
  try {
    final authService = FirebaseAuth.instance;
    final currentUserId = authService.currentUser?.uid;
    
    if (currentUserId == null) {
      print('FCM: Cannot open chat - user not logged in');
      return;
    }
    
    // Fetch the thread
    final threadDoc = await FirebaseFirestore.instance
        .collection('message_threads')
        .doc(threadId)
        .get();
    
    if (!threadDoc.exists) {
      print('FCM: Thread not found: $threadId');
      return;
    }
    
    final thread = MessageThread.fromFirestore(threadDoc);
    
    // Navigate to chat screen
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          thread: thread,
          currentUserId: currentUserId,
        ),
      ),
    );
  } catch (e) {
    print('FCM: Error opening chat from notification: $e');
  }
}

/// Open an event screen from a notification (invite or reminder)
Future<void> _openEventFromNotification(String eventId) async {
  try {
    final authService = FirebaseAuth.instance;
    final currentUserId = authService.currentUser?.uid;
    
    if (currentUserId == null) {
      print('FCM: Cannot open event - user not logged in');
      return;
    }
    
    // Fetch the event
    final eventService = EventService();
    final event = await eventService.getEvent(eventId);
    
    if (event == null) {
      print('FCM: Event not found: $eventId');
      return;
    }
    
    // Fetch experiences referenced in the event
    final experienceService = ExperienceService();
    final experienceIds = event.experiences
        .map((entry) => entry.experienceId)
        .where((id) => id.isNotEmpty)
        .toList();
    
    List<Experience> experiences = [];
    if (experienceIds.isNotEmpty) {
      experiences = await experienceService.getExperiencesByIds(experienceIds);
    }
    
    // Fetch categories
    final categories = await experienceService.getUserCategories();
    final colorCategories = await experienceService.getUserColorCategories();

    // Navigate to event editor modal
    navigatorKey.currentState?.push(
      MaterialPageRoute(
        builder: (context) => EventEditorModal(
          event: event,
          experiences: experiences,
          categories: categories,
          colorCategories: colorCategories,
          isReadOnly: true,
        ),
        fullscreenDialog: true,
      ),
    );
  } catch (e) {
    print('FCM: Error opening event from notification: $e');
  }
}

Future<Map<String, dynamic>?> _loadEventData(String token) async {
  try {
    // Ensure user is authenticated (anonymously if not signed in) to view shared media
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      try {
        print('DeepLink: Signing in anonymously to view shared event content');
        await FirebaseAuth.instance.signInAnonymously();
        print('DeepLink: Anonymous sign-in successful');
        // Wait for auth state to propagate
        await Future.delayed(const Duration(milliseconds: 300));
      } catch (e) {
        print('DeepLink: Anonymous sign-in failed: $e');
        // Continue anyway - event metadata can still be viewed
      }
    }

    final eventService = EventService();
    final event = await eventService.getEventByShareToken(token);
    if (event == null) {
      print('DeepLink: Event not found for token: $token');
      return null;
    }

    final experienceService = ExperienceService();
    
    List<Experience> experiences = [];
    List<UserCategory> categories = [];
    List<ColorCategory> colorCategories = [];
    
    // Load related data for both authenticated and unauthenticated users
    // Firestore rules now allow public read access to experiences/categories
    try {
      final experienceIds = event.experiences
          .map((entry) => entry.experienceId)
          .where((id) => id.isNotEmpty)
          .toList();

      if (experienceIds.isNotEmpty) {
        experiences = await experienceService.getExperiencesByIds(experienceIds);
      }

      // Collect unique category and color category IDs from experiences, grouped by owner
      final Map<String, Set<String>> categoriesByOwner = {};
      final Map<String, Set<String>> colorCategoriesByOwner = {};
      
      for (final exp in experiences) {
        final ownerId = exp.createdBy;
        if (ownerId != null && ownerId.isNotEmpty) {
          // Add primary category
          if (exp.categoryId != null && exp.categoryId!.isNotEmpty) {
            categoriesByOwner.putIfAbsent(ownerId, () => {}).add(exp.categoryId!);
          }
          // Add primary color category
          if (exp.colorCategoryId != null && exp.colorCategoryId!.isNotEmpty) {
            colorCategoriesByOwner.putIfAbsent(ownerId, () => {}).add(exp.colorCategoryId!);
          }
          // Add other categories
          for (final catId in exp.otherCategories) {
            if (catId.isNotEmpty) {
              categoriesByOwner.putIfAbsent(ownerId, () => {}).add(catId);
            }
          }
          // Add other color categories
          for (final colorCatId in exp.otherColorCategoryIds) {
            if (colorCatId.isNotEmpty) {
              colorCategoriesByOwner.putIfAbsent(ownerId, () => {}).add(colorCatId);
            }
          }
        }
      }
      
      // Fetch categories from each owner
      final List<Future<List<UserCategory>>> categoryFutures = [];
      for (final entry in categoriesByOwner.entries) {
        categoryFutures.add(
          experienceService.getUserCategoriesByOwnerAndIds(
            entry.key,
            entry.value.toList(),
          )
        );
      }
      
      final List<Future<List<ColorCategory>>> colorCategoryFutures = [];
      for (final entry in colorCategoriesByOwner.entries) {
        colorCategoryFutures.add(
          experienceService.getColorCategoriesByOwnerAndIds(
            entry.key,
            entry.value.toList(),
          )
        );
      }
      
      // Wait for all category fetches to complete
      if (categoryFutures.isNotEmpty) {
        final results = await Future.wait(categoryFutures);
        categories = results.expand((list) => list).toList();
      }
      
      if (colorCategoryFutures.isNotEmpty) {
        final results = await Future.wait(colorCategoryFutures);
        colorCategories = results.expand((list) => list).toList();
      }
      
      print('DeepLink: Loaded ${experiences.length} experiences, ${categories.length} categories, ${colorCategories.length} color categories');
    } catch (e) {
      print('DeepLink: Error loading related data (non-critical): $e');
      // Continue with empty lists - event will display with denormalized data
    }

    return {
      'event': event,
      'experiences': experiences,
      'categories': categories,
      'colorCategories': colorCategories,
    };
  } catch (e) {
    print('DeepLink: Error loading event data for token $token: $e');
    rethrow;
  }
}

Future<void> _configureLocalNotifications() async {
  // Ensure you have an app icon, e.g., android/app/src/main/res/mipmap-hdpi/ic_launcher.png
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  // Add iOS and macOS settings
  // Request permissions for local notifications on iOS
  const DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings(
    requestSoundPermission: true,
    requestBadgePermission: true,
    requestAlertPermission: true,
  );

  const DarwinInitializationSettings initializationSettingsMacOS =
      DarwinInitializationSettings(
    requestSoundPermission: true,
    requestBadgePermission: true,
    requestAlertPermission: true,
  );

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
    macOS: initializationSettingsMacOS,
  );
  
  final initialized = await flutterLocalNotificationsPlugin.initialize(initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse notificationResponse) async {
    // Handle notification tap when app is in foreground/background but not terminated
    print(
        'Local notification tapped with payload: ${notificationResponse.payload}');
    if (notificationResponse.payload != null &&
        notificationResponse.payload!.isNotEmpty) {
      final payload = notificationResponse.payload!;
      print("Local notification: Handling payload: $payload");

      // Try to parse as JSON first (for new message notifications)
      try {
        final data = jsonDecode(payload) as Map<String, dynamic>;
        final type = data['type'] as String?;
        
        if (type == 'new_message') {
          final threadId = data['threadId'] as String?;
          if (threadId != null) {
            await _openChatFromNotification(threadId);
            return;
          }
        } else if (type == 'event_reminder' || type == 'event_invite' ||
                   type == 'event_role_change') {
          final eventId = data['eventId'] as String?;
          if (eventId != null) {
            print('Event notification tapped ($type) - eventId: $eventId');
            await _openEventFromNotification(eventId);
            return;
          }
        }
      } catch (_) {
        // Not JSON, treat as screen path
      }

      // Handle as screen path (for follow requests, etc.)
      if (payload == '/follow_requests' && navigatorKey.currentState != null) {
        navigatorKey.currentState!.push(
          MaterialPageRoute(
            builder: (context) => const FollowRequestsScreen(),
          ),
        );
      }
    }
  });
  
  print('Local notifications initialized: $initialized');
  
  // Create notification channels on Android
  if (Platform.isAndroid) {
    final AndroidFlutterLocalNotificationsPlugin? androidImplementation =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    
    // Messages channel
    await androidImplementation?.createNotificationChannel(
      const AndroidNotificationChannel(
        'messages',
        'Messages',
        description: 'Notifications for new messages',
        importance: Importance.max,
        playSound: true,
      ),
    );
    
    // Events channel
    await androidImplementation?.createNotificationChannel(
      const AndroidNotificationChannel(
        'events',
        'Events',
        description: 'Notifications for event reminders',
        importance: Importance.max,
        playSound: true,
      ),
    );
    
    // Social channel
    await androidImplementation?.createNotificationChannel(
      const AndroidNotificationChannel(
        'social',
        'Social',
        description: 'Notifications for followers and follow requests',
        importance: Importance.max,
        playSound: true,
      ),
    );
    
    print('Android notification channels created');
  }
  
  // Check permissions on iOS
  if (Platform.isIOS) {
    final result = await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>()
        ?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        );
    print('iOS local notification permissions granted: $result');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    // Enable path-based URLs on web (no hash in URL)
    usePathUrlStrategy();
  }

  // Load environment variables (if .env file exists) - non-blocking
  unawaited(dotenv.load(fileName: ".env").catchError((e) {
    print('No .env file found - using API keys from config files instead: $e');
  }));

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Initialize Firebase App Check (invisible; no user prompt)
  // Kick off App Check without delaying the first Flutter frame
  unawaited(_initializeAppCheck());

  // Preload user location in the background to keep startup fast
  unawaited(_preloadUserLocation());

  // Preload Collections data in background to warm up Firestore cache
  // This makes Collections screen load instantly when user navigates to it
  unawaited(_preloadCollectionsData());

  // Initialize Discovery cover service (fetch list of available covers)
  unawaited(_initializeDiscoveryCoverService());

  // Initialize sharing service
  // Conditionally initialize SharingService if not on web
  if (!kIsWeb) {
    SharingService().init();

    // Initialize foreground scan service for background AI scans
    // This allows scans to continue when the app is minimized
    unawaited(ForegroundScanService().initialize());

    // DEBUG: Start timer to check for shared data (Android only)
    if (Platform.isAndroid) {
      _startShareDebugTimer();
    }

    // --- FCM Setup ---
    // Setup local notifications in background to not delay app startup
    await _configureLocalNotifications(); // Make this blocking to ensure it's ready
    
    // DISABLE automatic iOS notification display in foreground
    // We need to filter notifications (e.g., don't show event_invite to wrong user)
    // so we handle ALL foreground notifications manually via flutter_local_notifications
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: false, // Don't show automatically - we'll show manually after filtering
      badge: true,
      sound: false, // We'll play sound when showing manually
    );

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('FCM: Got a message whilst in the foreground!');
      print('FCM: Message data: ${message.data}');
      print('FCM: Message ID: ${message.messageId}');

      // Deduplicate messages (iOS sometimes delivers the same message twice)
      // Use a combination that's unique per notification but same for duplicates
      final threadId = message.data['threadId'] ?? '';
      final senderId = message.data['senderId'] ?? '';
      final type = message.data['type'] ?? '';
      final sentTimestamp = message.sentTime?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
      
      // Create unique ID - use sentTime to group duplicates that arrive within same second
      final uniqueId = '$type:$threadId:$senderId:${sentTimestamp ~/ 1000}';
      
      print('FCM: Dedup ID: $uniqueId');
      print('FCM: Already seen: ${_recentlyReceivedMessageIds.contains(uniqueId)}');
      
      if (_recentlyReceivedMessageIds.contains(uniqueId)) {
        print('FCM: ⚠️ Ignoring duplicate message');
        return;
      }
      
      // Track this message and clean it up after 5 seconds
      _recentlyReceivedMessageIds.add(uniqueId);
      Timer(const Duration(seconds: 5), () {
        _recentlyReceivedMessageIds.remove(uniqueId);
      });

      // Check if current user is the sender - don't show notification for own messages
      final currentUserId = FirebaseAuth.instance.currentUser?.uid;
      
      print('FCM: Current user ID: $currentUserId');
      print('FCM: Sender ID from message: $senderId');
      print('FCM: Match check: ${currentUserId == senderId}');
      
      if (currentUserId != null && senderId == currentUserId) {
        print('FCM: ⚠️ BLOCKING notification - you are the sender!');
        // Note: iOS may have already shown this notification before we could block it
        // The apns-collapse-id helps, but iOS shows notifications before Flutter runs
        return;
      }
      
      // For event notifications, check if current user is the intended recipient
      // This handles cases where FCM tokens are registered under wrong accounts
      final messageType = message.data['type'] as String?;
      final recipientUserId = message.data['recipientUserId'] as String?;
      
      // Block event_invite and event_role_change if not intended for this user
      if ((messageType == 'event_invite' || messageType == 'event_role_change') && 
          recipientUserId != null) {
        if (currentUserId != recipientUserId) {
          print('FCM: ⚠️ BLOCKING $messageType - not intended recipient');
          print('FCM: Intended: $recipientUserId, Current: $currentUserId');
          return;
        }
      }
      
      print('FCM: ✅ Proceeding to show notification');

      if (message.notification != null) {
        print(
            'FCM: Message also contained a notification: ${message.notification}');
        
        // Show notification manually on BOTH Android and iOS
        // We disabled automatic iOS display so we can filter first
        
        // Prepare payload with notification data
        String? payload;
        
        // Determine channel ID based on notification type (messageType already defined above)
        String channelId = 'messages'; // default
        String channelName = 'Messages';
        String channelDescription = 'Notifications for new messages';

        if (messageType == 'new_message') {
          if (threadId.isNotEmpty) {
            payload = jsonEncode({'type': messageType, 'threadId': threadId});
          }
          channelId = 'messages';
          channelName = 'Messages';
          channelDescription = 'Notifications for new messages';
        } else if (messageType == 'event_reminder' || messageType == 'event_invite' ||
                   messageType == 'event_role_change') {
          final eventId = message.data['eventId'] as String?;
          if (eventId != null) {
            payload = jsonEncode({'type': messageType, 'eventId': eventId});
          }
          channelId = 'events';
          channelName = 'Events';
          channelDescription = 'Notifications for event reminders and invites';
        } else if (messageType == 'follow_request' || messageType == 'new_follower') {
          payload = message.data['screen'] as String?;
          channelId = 'social';
          channelName = 'Social';
          channelDescription = 'Notifications for followers and follow requests';
        } else {
          payload = message.data['screen'] as String?;
        }
        
        // Use uniqueId as the notification ID to prevent duplicate notifications
        final notificationId = uniqueId.hashCode;
        
        flutterLocalNotificationsPlugin.show(
          notificationId,
          message.notification!.title,
          message.notification!.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              channelId,
              channelName,
              channelDescription: channelDescription,
              importance: Importance.max,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
            iOS: const DarwinNotificationDetails(
              presentAlert: true,
              presentBadge: true,
              presentSound: true,
            ),
          ),
          payload: payload,
        ).then((_) {
          print('FCM: ✅ Local notification shown successfully on channel: $channelId');
        }).catchError((e) {
          print('FCM: ❌ Error showing local notification: $e');
        });
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) async {
      print('FCM: Message clicked and opened app!');
      print('FCM: Message data: ${message.data}');
      
      // Deduplicate messages using the same logic as onMessage
      final threadId = message.data['threadId'] ?? '';
      final senderId = message.data['senderId'] ?? '';
      final type = message.data['type'] ?? '';
      final sentTimestamp = message.sentTime?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
      final uniqueId = '$type:$threadId:$senderId:${sentTimestamp ~/ 1000}';
      
      print('FCM: Dedup ID: $uniqueId');
      
      if (_recentlyReceivedMessageIds.contains(uniqueId)) {
        print('FCM: ⚠️ Ignoring duplicate message tap');
        return;
      }
      
      _recentlyReceivedMessageIds.add(uniqueId);
      Timer(const Duration(seconds: 5), () {
        _recentlyReceivedMessageIds.remove(uniqueId);
      });
      
      final screen = message.data['screen'] as String?;

      if (screen != null && navigatorKey.currentState != null) {
        print("FCM: Navigating to screen: $screen");

        // Handle different notification types
        if (type == 'follow_request' && screen == '/follow_requests') {
          // Navigate to Follow Requests screen
          navigatorKey.currentState!.push(
            MaterialPageRoute(
              builder: (context) => const FollowRequestsScreen(),
            ),
          );
        } else if (type == 'new_follower') {
          // For new follower notifications, you might want to navigate to the user's profile
          // For now, we'll just print a message
          print(
              "FCM: New follower notification - would navigate to user profile");
          // You could implement navigation to user profile here:
          // final followerId = message.data['followerId'] as String?;
          // if (followerId != null) {
          //   // Navigate to user profile screen with followerId
          // }
        } else if (type == 'new_message' && screen == '/messages') {
          // Navigate to the specific chat thread
          final threadId = message.data['threadId'] as String?;
          final senderId = message.data['senderId'] as String?;

          print(
              "FCM: New message notification - threadId: $threadId, senderId: $senderId");

          if (threadId != null) {
            // Navigate directly to the chat screen
            await _openChatFromNotification(threadId);
          } else {
            // Fallback: Navigate to Messages screen if no threadId
            navigatorKey.currentState!.push(
              MaterialPageRoute(
                builder: (context) => const MessagesScreen(),
              ),
            );
          }
        } else if (type == 'event_reminder' || type == 'event_invite' ||
                   type == 'event_role_change') {
          final eventId = message.data['eventId'] as String?;
          print("FCM: Event notification ($type) - eventId: $eventId");
          if (eventId != null) {
            await _openEventFromNotification(eventId);
          }
        }
      }
    });
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    // --- End FCM Setup ---
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>(
          create: (_) => AuthService(),
        ),
        ChangeNotifierProvider<NotificationStateService>(
          create: (_) => NotificationStateService(),
        ),
        ChangeNotifierProvider<CategorySaveProgressNotifier>(
          create: (_) => CategorySaveProgressNotifier(),
        ),
        ChangeNotifierProvider<DiscoveryShareCoordinator>(
          create: (_) => DiscoveryShareCoordinator(),
        ),
      ],
      child: const MyApp(),
    ),
  );
}

Future<void> _initializeAppCheck() async {
  try {
    if (kIsWeb) {
      await FirebaseAppCheck.instance.activate(
        webProvider:
            ReCaptchaV3Provider('6Ldt0sIrAAAAABBHbSmj07DU8gEEzqijAk70XwKA'),
        androidProvider: AndroidProvider.playIntegrity,
        appleProvider: AppleProvider.appAttest,
      );
      print('App Check activated (web + providers).');
    } else {
      // Use Debug provider for debug/profile builds to simplify local dev.
      final androidProvider =
          kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug;
      final appleProvider =
          kReleaseMode ? AppleProvider.appAttest : AppleProvider.debug;

      await FirebaseAppCheck.instance.activate(
        androidProvider: androidProvider,
        appleProvider: appleProvider,
      );
      print('App Check activated (native providers: ${kReleaseMode ? 'release' : 'debug'})');
    }
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
    // Force initial token request so reCAPTCHA key leaves "Incomplete" and headers appear
    try {
      final token = await FirebaseAppCheck.instance.getToken(true);
      print('App Check initial token fetched: ${token != null && token.isNotEmpty ? 'ok' : 'empty'}');
    } catch (e) {
      print('App Check initial token fetch error: $e');
    }
  } catch (e) {
    print('App Check activation error: $e');
  }
}

Future<void> _preloadUserLocation() async {
  try {
    print("MAIN: Starting background location preload...");
    final mapsService = GoogleMapsService();
    await mapsService.getCurrentLocation(); // Attempt to get location
    print("MAIN: Background location preload attempt finished.");
  } catch (e) {
    // Catch errors silently - we don't want to crash the app or bother the user here.
    print(
        "MAIN: Error during background location preload (expected if permissions not granted yet): $e");
  }
}

/// Initialize Discovery cover service by fetching list of available cover images
Future<void> _initializeDiscoveryCoverService() async {
  try {
    print("MAIN: Initializing Discovery cover service...");
    final coverService = DiscoveryCoverService();
    await coverService.initialize();
    print("MAIN: Discovery cover service initialized");
  } catch (e) {
    print("MAIN: Error initializing Discovery cover service: $e");
  }
}

/// Preload Collections data in background to warm up Firestore cache
/// This runs the slow permission queries during app startup so Collections loads instantly
bool _collectionsPreloaded = false; // Ensure we only preload once per app session

Future<void> _preloadCollectionsData() async {
  try {
    // Wait for user to be authenticated
    final auth = FirebaseAuth.instance;
    
    // Listen for auth state and preload when user is available (only once)
    auth.authStateChanges().listen((user) async {
      if (user != null && !_collectionsPreloaded) {
        _collectionsPreloaded = true; // Mark as done to avoid duplicate preloads
        print("MAIN: [Preload] User authenticated, preloading Collections data...");
        final sw = Stopwatch()..start();
        
        try {
          final experienceService = ExperienceService();
          final sharingService = SharingService();
          
          // Run the slow queries in parallel to warm up caches
          await Future.wait([
            // Categories and permissions (~2s)
            experienceService.getUserAndColorCategories(includeSharedEditable: true),
            // Share permissions
            sharingService.getSharedItemsForUser(user.uid),
            sharingService.getOwnedSharePermissions(user.uid),
            // User's experiences (~5-10s for 1000+ experiences) - the BIG one
            experienceService.getExperiencesByUser(user.uid, limit: 0),
          ]);
          
          sw.stop();
          print("MAIN: [Preload] Collections data preloaded in ${sw.elapsedMilliseconds}ms");
        } catch (e) {
          print("MAIN: [Preload] Error preloading Collections data: $e");
        }
      }
    });
  } catch (e) {
    print("MAIN: [Preload] Error setting up Collections preload: $e");
  }
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final SharingService _sharingService = SharingService();
  StreamSubscription? _intentSub;
  List<SharedMediaFile>? _sharedFiles;
  bool _initialCheckComplete = false;
  bool _shouldShowReceiveShare = false;
  bool _forceOnboarding = false;
  bool _deepLinkStreamFired =
      false; // Track if a fresh deep link arrived via stream
  String? _deferredDiscoveryShareToken;
  String?
      _initialDiscoveryShareToken; // NEW: Track initial discovery share token from URL
  String? _initialEventShareToken; // Track initial event share token from URL
  String? _initialExperienceShareToken; // Track initial experience share token from URL
  bool _showDataDeletion = false; // Track if data deletion page should be shown
  String? _initialProfileUserId; // Track initial profile user ID from URL
  static const int _maxNavigatorPushRetries = 12;
  Future<void>? _coverPreloadFuture; // Track the preload operation

  void _pushRouteWhenReady(WidgetBuilder builder,
      {RouteSettings? settings, int attempt = 0}) {
    if (!mounted) {
      return;
    }
    if (navigatorKey.currentState?.mounted ?? false) {
      navigatorKey.currentState!
          .push(MaterialPageRoute(builder: builder, settings: settings));
      return;
    }
    if (attempt >= _maxNavigatorPushRetries) {
      print(
          'DeepLink: Navigator not ready after ${attempt + 1} attempts; dropping deep link navigation');
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _pushRouteWhenReady(builder, settings: settings, attempt: attempt + 1);
    });
  }

  Uri _normalizeDeepLinkUri(Uri uri) {
    Uri current = _coerceIntentUri(uri);
    final Set<String> visited = <String>{};
    while (true) {
      if (!visited.add(current.toString())) {
        return current;
      }
      final Uri? nested = _tryExtractNestedUri(current);
      if (nested == null) {
        return current;
      }
      current = _coerceIntentUri(nested);
    }
  }

  Uri _coerceIntentUri(Uri uri) {
    if (uri.scheme != 'intent') {
      return uri;
    }
    const String prefix = 'intent://';
    final String raw = uri.toString();
    if (!raw.startsWith(prefix)) {
      return uri;
    }
    final int hashIndex = raw.indexOf('#Intent;');
    final String core = hashIndex >= 0
        ? raw.substring(prefix.length, hashIndex)
        : raw.substring(prefix.length);
    if (core.isEmpty) {
      return uri;
    }
    final String candidate = 'https://$core';
    try {
      return Uri.parse(candidate);
    } catch (e) {
      print('DeepLink: Failed to coerce intent URI: $e');
      return uri;
    }
  }

  Uri? _tryExtractNestedUri(Uri uri) {
    final String? linkParam = uri.queryParameters['link'];
    if (linkParam != null && linkParam.isNotEmpty) {
      try {
        final Uri nested = Uri.parse(linkParam);
        print('DeepLink: Unwrapped link parameter -> $nested');
        return nested;
      } catch (e) {
        print('DeepLink: Failed to parse link parameter "$linkParam": $e');
      }
    }

    final String? deepLinkId = uri.queryParameters['deep_link_id'];
    if (deepLinkId != null && deepLinkId.isNotEmpty) {
      try {
        final Uri nested = Uri.parse(deepLinkId);
        print('DeepLink: Unwrapped deep_link_id -> $nested');
        return nested;
      } catch (e) {
        print('DeepLink: Failed to parse deep_link_id "$deepLinkId": $e');
      }
    }

    final String? applinkData = uri.queryParameters['al_applink_data'];
    if (applinkData != null && applinkData.isNotEmpty) {
      try {
        final String decoded = Uri.decodeFull(applinkData);
        final dynamic parsed = jsonDecode(decoded);
        if (parsed is Map<String, dynamic>) {
          final dynamic target = parsed['target_url'];
          if (target is String && target.isNotEmpty) {
            final Uri nested = Uri.parse(target);
            print('DeepLink: Unwrapped al_applink_data target_url -> $nested');
            return nested;
          }
        }
      } catch (e) {
        print('DeepLink: Failed to parse al_applink_data: $e');
      }
    }

    if (uri.fragment.isNotEmpty) {
      final String fragment = uri.fragment;
      if (fragment.startsWith('http')) {
        try {
          final Uri nested = Uri.parse(fragment);
          print('DeepLink: Unwrapped fragment URL -> $nested');
          return nested;
        } catch (e) {
          print('DeepLink: Failed to parse fragment URI "$fragment": $e');
        }
      } else if (uri.host.isNotEmpty) {
        final String prefix =
            '${uri.scheme.isEmpty ? 'https' : uri.scheme}://${uri.host}';
        final String candidate =
            fragment.startsWith('/') ? fragment : '/$fragment';
        try {
          final Uri nested = Uri.parse(prefix + candidate);
          print('DeepLink: Composed fragment URL -> $nested');
          return nested;
        } catch (e) {
          print('DeepLink: Failed to compose fragment URI "$fragment": $e');
        }
      }
    }

    return null;
  }

  String? _cleanToken(String? rawToken) {
    if (rawToken == null) {
      return null;
    }
    final String trimmed = rawToken.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '');
  }

  @override
  void initState() {
    super.initState();

    print("MAIN: App initializing");

    // NEW: Check if this is a discovery share or event share preview link on web
    if (kIsWeb) {
      try {
        final uri = Uri.base;
        final segments = uri.pathSegments;
        if (segments.isNotEmpty) {
          final firstSegment = segments.first.toLowerCase();
          
          // Check for discovery share link
          if (firstSegment == 'discovery-share' && segments.length > 1) {
            final rawToken = segments[1];
            final token = _cleanToken(rawToken);
            if (token != null && token.isNotEmpty) {
              setState(() {
                _initialDiscoveryShareToken = token;
              });
              print(
                  "MAIN: Detected initial discovery share token from URL: $token");
            }
          }
          // Check for event share link
          else if (firstSegment == 'event' && segments.length > 1) {
            final rawToken = segments[1];
            final token = _cleanToken(rawToken);
            if (token != null && token.isNotEmpty) {
              setState(() {
                _initialEventShareToken = token;
              });
              print(
                  "MAIN: Detected initial event share token from URL: $token");
            }
          }
          // Check for experience share link
          else if (firstSegment == 'shared' && segments.length > 1) {
            final rawToken = segments[1];
            final token = _cleanToken(rawToken);
            if (token != null && token.isNotEmpty) {
              setState(() {
                _initialExperienceShareToken = token;
              });
              print(
                  "MAIN: Detected initial experience share token from URL: $token");
            }
          }
          // Check for profile link
          else if (firstSegment == 'profile' && segments.length > 1) {
            final userId = segments[1];
            if (userId.isNotEmpty) {
              setState(() {
                _initialProfileUserId = userId;
              });
              print(
                  "MAIN: Detected initial profile user ID from URL: $userId");
            }
          }
          // Check for data deletion page (public, no auth required)
          else if (firstSegment == 'data-deletion') {
            print('MAIN: Web URL detected data-deletion page. Setting _showDataDeletion=true');
            setState(() {
              _showDataDeletion = true;
            });
          }
        }
      } catch (e) {
        print("MAIN: Error checking for initial share token from URL: $e");
      }
    }

    // Add toast right at startup to confirm we're getting here
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   Fluttertoast.showToast(
    //     msg: "App Started - initState called",
    //     toastLength: Toast.LENGTH_LONG,
    //     gravity: ToastGravity.TOP,
    //     backgroundColor: Colors.red.withOpacity(0.8),
    //     textColor: Colors.white,
    //   );
    // });

    if (!kIsWeb) {
      // Check for initial shared files when app was closed
      ShareHandlerPlatform.instance
          .getInitialSharedMedia()
          .then((SharedMedia? media) {
        print("MAIN: Initial media check complete");

        final value =
            media != null ? _convertSharedMedia(media) : <SharedMediaFile>[];

        if (value.isNotEmpty) {
          print("MAIN: Found initial shared files: ${value.length}");

          // Add toast when we detect shared files
          // Fluttertoast.showToast(
          //   msg: "Found ${value.length} shared files in initState",
          //   toastLength: Toast.LENGTH_LONG,
          //   gravity: ToastGravity.TOP,
          //   backgroundColor: Colors.green.withOpacity(0.8),
          //   textColor: Colors.white,
          // );

          if (mounted) {
            // Check if this is a Yelp URL during cold start - if so, check for existing session
            bool isYelpUrl = false;
            for (final file in value) {
              if (file.type == SharedMediaType.text ||
                  file.type == SharedMediaType.url) {
                String content = file.path.toLowerCase();
                if (content.contains('yelp.com/biz') ||
                    content.contains('yelp.to/')) {
                  isYelpUrl = true;
                  break;
                }
              }
            }

            // For Yelp URLs during cold start, always create ReceiveShareScreen
            // but let it handle restoration internally
            if (isYelpUrl) {
              print(
                  "MAIN: Cold start Yelp URL detected - will create ReceiveShareScreen with restoration logic");
            }

            setState(() {
              _sharedFiles = value;
              _initialCheckComplete = true;
              _shouldShowReceiveShare = true;
            });
          }
          print("MAIN: Stored initial share data for display");
        } else {
          print("MAIN: No initial shared files found");

          // Add toast when no files found
          // Fluttertoast.showToast(
          //   msg: "No shared files found in initState",
          //   toastLength: Toast.LENGTH_LONG,
          //   gravity: ToastGravity.TOP,
          //   backgroundColor: Colors.orange.withOpacity(0.8),
          //   textColor: Colors.white,
          // );

          if (mounted) {
            setState(() {
              _initialCheckComplete = true;
            });
          }
        }
      }).catchError((err) {
        print("MAIN: Error getting initial media (expected on web): $err");
        if (mounted) {
          setState(() {
            _initialCheckComplete = true;
          });
        }
      });

      // Listen for incoming shares while the app is running
      _intentSub = ShareHandlerPlatform.instance.sharedMediaStream.listen(
          (SharedMedia media) {
        if (OnboardingScreen.suppressShareHandling) {
          OnboardingScreen.onboardingShareDetected = true;
          return;
        }
        final value = _convertSharedMedia(media);
        if (mounted) {
          setState(() {
            _sharedFiles = value;
            _initialCheckComplete = true;
          });
        }
        // Optionally, navigate immediately if context is available
        // This might need refinement depending on app structure
        if (navigatorKey.currentContext != null && value.isNotEmpty) {
          _sharingService.showReceiveShareScreen(
              navigatorKey.currentContext!, value);
        }
      }, onError: (err) {
        print("getIntentDataStream error (expected on web): $err");
      });
    } else {
      // On web, mark initial check as complete immediately
      if (mounted) {
        setState(() {
          _initialCheckComplete = true;
        });
      }
    }

    // Listen for app going to foreground to reinitialize sharing capabilities
    WidgetsBinding.instance.addObserver(AppLifecycleObserver(
      onResumed: () {
        // Recreate listeners when app comes to foreground
        print("MAIN: App resumed - recreating sharing service listeners");
        if (!kIsWeb && !OnboardingScreen.suppressShareHandling) {
          _sharingService.recreateListeners();
        }
      },
      onPaused: () {
        print("MAIN: App paused");
      },
    ));

    // Deep link handling for shared links
    _initDeepLinks();
  }

  Future<void> _preloadDiscoveryCoverImages(BuildContext context) async {
    if (!mounted) return;
    
    try {
      final coverService = DiscoveryCoverService();
      
      // Preload 1 image during startup
      print('MAIN: Preloading 1 Discovery cover image...');
      await coverService.preloadSingleImage(context);
      print('MAIN: Discovery cover image preloaded');
      
      // Preload 5 more images in background
      if (!mounted) return;
      Future.microtask(() async {
        try {
          print('MAIN: Preloading 5 additional Discovery cover images in background...');
          await coverService.preloadBackgroundImages(context, count: 5);
          print('MAIN: Background Discovery cover preload complete');
        } catch (e) {
          print('MAIN: Error in background Discovery cover preload: $e');
        }
      });
    } catch (e) {
      print('MAIN: Error preloading Discovery cover images: $e');
    }
  }

  void _initDeepLinks() async {
    final appLinks = AppLinks();

    // iOS: Listen for manually posted deep links (to avoid Safari opening)
    if (Platform.isIOS) {
      const platform = MethodChannel('deep_link_channel');
      platform.setMethodCallHandler((call) async {
        if (call.method == 'onDeepLink') {
          final String url = call.arguments as String;
          print('DeepLink: Received from native iOS: $url');
          _handleIncomingUri(Uri.parse(url));
        }
      });
    }

    // WEB: Handle current URL directly (no plugin needed)
    if (kIsWeb) {
      try {
        _handleIncomingUri(Uri.base);
      } catch (e) {
        print('DeepLink: Error handling web Uri.base: $e');
      }
    }

    // Link stream - process incoming links (fresh intents)
    // Note: On iOS, for /shared/* links, this won't fire because we consume them in AppDelegate
    appLinks.uriLinkStream.listen((uri) {
      print('DeepLink: Stream received fresh URI: $uri');
      _deepLinkStreamFired = true;
      _handleIncomingUri(uri);
    }, onError: (e) {
      print('DeepLink: Stream error: $e');
    });

    // Process initial link after a short delay; if stream already fired, skip.
    Future.delayed(const Duration(milliseconds: 900), () async {
      try {
        if (_deepLinkStreamFired) {
          print(
              'DeepLink: Skipping delayed initial app link (stream already fired)');
          return;
        }
        final initialUri = await appLinks.getInitialAppLink();
        if (initialUri != null) {
          print('DeepLink: Delayed initial app link: $initialUri');
          _handleIncomingUri(initialUri);
        } else {
          print('DeepLink: No initial app link found');
        }
      } catch (e) {
        print('DeepLink: Error getting initial app link: $e');
      }
    });
  }

  void _handleIncomingUri(Uri uri) {
    final Uri normalizedUri = _normalizeDeepLinkUri(uri);
    print('DeepLink: Processing URI: $uri');
    if (normalizedUri != uri) {
      print('DeepLink: Normalized URI: $normalizedUri');
    }
    final List<String> segments = normalizedUri.pathSegments;
    print('DeepLink: Path segments: $segments');

    if (segments.isEmpty) {
      return;
    }

    final String firstSegment = segments.first.toLowerCase();

    if (firstSegment == 'shared') {
      final String? rawToken = segments.length > 1 ? segments[1] : null;
      final String? token = _cleanToken(rawToken);
      print('DeepLink: Experience share - rawToken: $rawToken, cleanToken: $token');
      if (token != null && token.isNotEmpty) {
        if (rawToken != null && rawToken != token) {
          print('DeepLink: Sanitized share token from $rawToken to $token');
        }
        _pushRouteWhenReady(
          (_) => SharePreviewScreen(token: token),
          settings: RouteSettings(name: '/shared/$token'),
        );
      } else {
        print('DeepLink: Experience share token missing or empty.');
      }
    } else if (firstSegment == 'discovery-share') {
      final String? rawToken = segments.length > 1 ? segments[1] : null;
      final String? token = _cleanToken(rawToken);
      print('DeepLink: Discovery share - rawToken: $rawToken, cleanToken: $token');
      if (token != null && token.isNotEmpty) {
        final BuildContext? ctx = navigatorKey.currentContext;
        if (ctx != null) {
          final coordinator =
              Provider.of<DiscoveryShareCoordinator>(ctx, listen: false);
          coordinator.openSharedToken(token);
        } else {
          print('DeepLink: Navigator context unavailable for discovery share.');
          _deferredDiscoveryShareToken = token;
        }
        if (kIsWeb) {
          _pushRouteWhenReady(
            (_) => DiscoverySharePreviewScreen(token: token),
            settings: RouteSettings(name: '/discovery-share/$token'),
          );
        } else {
          navigatorKey.currentState?.popUntil((route) => route.isFirst);
        }
      } else {
        print('DeepLink: Discovery share token missing or empty.');
      }
    } else if (firstSegment == 'shared-category') {
      final String? rawToken = segments.length > 1 ? segments[1] : null;
      final String? token = _cleanToken(rawToken);
      print('DeepLink: Category share - rawToken: $rawToken, cleanToken: $token');
      if (token != null && token.isNotEmpty) {
        if (rawToken != null && rawToken != token) {
          print('DeepLink: Sanitized category share token from $rawToken to $token');
        }
        _pushRouteWhenReady(
          (_) => CategorySharePreviewScreen(token: token),
          settings: RouteSettings(name: '/shared-category/$token'),
        );
      } else {
        print('DeepLink: Category share token missing or empty.');
      }
    } else if (firstSegment == 'event') {
      final String? rawToken = segments.length > 1 ? segments[1] : null;
      final String? token = _cleanToken(rawToken);
      print('DeepLink: Event share - rawToken: $rawToken, cleanToken: $token');
      if (token != null && token.isNotEmpty) {
        if (rawToken != null && rawToken != token) {
          print('DeepLink: Sanitized event share token from $rawToken to $token');
        }
        
        // Store the token to show the event as root widget for unauthenticated users
        setState(() {
          _initialEventShareToken = token;
        });
        
        // Also push the route for authenticated users (will be on top of MainScreen)
        _pushRouteWhenReady(
          (context) => FutureBuilder<Map<String, dynamic>?>(
            future: _loadEventData(token),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Scaffold(
                  body: Center(child: CircularProgressIndicator()),
                );
              }

              if (snapshot.hasError || snapshot.data == null) {
                return Scaffold(
                  appBar: AppBar(title: const Text('Error')),
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          'Unable to load event',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          snapshot.hasError 
                              ? 'Error: ${snapshot.error}'
                              : 'Event not found',
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }

              final data = snapshot.data!;
              return EventEditorModal(
                event: data['event'] as Event,
                experiences: data['experiences'] as List<Experience>,
                categories: data['categories'] as List<UserCategory>,
                colorCategories: data['colorCategories'] as List<ColorCategory>,
                isReadOnly: true,
              );
            },
          ),
          settings: RouteSettings(name: '/event/$token'),
        );
      } else {
        print('DeepLink: Event share token missing or empty.');
      }
    } else if (firstSegment == 'profile') {
      final String? userId = segments.length > 1 ? segments[1] : null;
      print('DeepLink: Profile - userId: $userId');
      if (userId != null && userId.isNotEmpty) {
        _pushRouteWhenReady(
          (_) => PublicProfileScreen(userId: userId),
          settings: RouteSettings(name: '/profile/$userId'),
        );
      } else {
        print('DeepLink: Profile userId missing or empty.');
      }
    } else if (firstSegment == 'data-deletion') {
      print('DeepLink: Data deletion page requested');
      setState(() {
        _showDataDeletion = true;
      });
    } else {
      print('DeepLink: No handler for path segments: $segments');
    }
  }

  @override
  void dispose() {
    // Clean up observers
    WidgetsBinding.instance.removeObserver(AppLifecycleObserver());
    if (!kIsWeb) {
      _intentSub?.cancel(); // Cancel the stream subscription
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use the dedicated flag instead of calculating each time
    bool launchedFromShare = !kIsWeb &&
        _shouldShowReceiveShare &&
        _sharedFiles != null &&
        _sharedFiles!.isNotEmpty;

    print("MAIN BUILD DEBUG: Detailed calculation:");
    print("  !kIsWeb = ${!kIsWeb}");
    print("  _shouldShowReceiveShare = $_shouldShowReceiveShare");
    print("  _sharedFiles != null = ${_sharedFiles != null}");
    if (_sharedFiles != null) {
      print("  _sharedFiles!.isNotEmpty = ${_sharedFiles!.isNotEmpty}");
    }
    print("  Final launchedFromShare = $launchedFromShare");

    print(
        "MAIN BUILD DEBUG: _initialCheckComplete=$_initialCheckComplete, kIsWeb=$kIsWeb, _sharedFiles is null? ${_sharedFiles == null}");
    print("MAIN BUILD DEBUG: _shouldShowReceiveShare=$_shouldShowReceiveShare");
    if (_sharedFiles != null) {
      print("MAIN BUILD DEBUG: _sharedFiles count=${_sharedFiles!.length}");
      if (_sharedFiles!.isNotEmpty) {
        print(
            "MAIN BUILD DEBUG: first file=${_sharedFiles!.first.path.substring(0, math.min(100, _sharedFiles!.first.path.length))}");
      }
    }
    print(
        "MAIN BUILD DEBUG: launchedFromShare=$launchedFromShare, _initialCheckComplete=$_initialCheckComplete");

    // Add visual debugging for cold start
    // if (!kIsWeb) {
    //   WidgetsBinding.instance.addPostFrameCallback((_) {
    //     final message = "Cold Start Debug: launchedFromShare=$launchedFromShare, files=${_sharedFiles?.length ?? 0}, shouldShow=$_shouldShowReceiveShare, kIsWeb=$kIsWeb";
    //     print(message);
    //     _writeDebugLog(message);
    //     // Visual toast debugging:
    //     Fluttertoast.showToast(
    //       msg: message,
    //       toastLength: Toast.LENGTH_LONG,
    //       gravity: ToastGravity.CENTER,
    //       backgroundColor: Colors.black.withOpacity(0.8),
    //       textColor: Colors.white,
    //     );
    //   });
    // }

    // For cold start with shared files, we simply proceed to show ReceiveShareScreen
    // The complex flow checking is only needed for warm app scenarios
    if (launchedFromShare) {
      print(
          "MAIN: Cold start with shared files - will create ReceiveShareScreen");
    } else {
      print(
          "MAIN: No shared files or not cold start - proceeding to normal auth flow");
    }

    // --- ADDED: Get AuthService from Provider ---
    final authService = Provider.of<AuthService>(context, listen: false);
    final pendingDiscoveryToken = _deferredDiscoveryShareToken;
    if (pendingDiscoveryToken != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final coordinator =
            Provider.of<DiscoveryShareCoordinator>(context, listen: false);
        coordinator.openSharedToken(pendingDiscoveryToken);
      });
      _deferredDiscoveryShareToken = null;
    }

    final baseTheme = ThemeData(
      primarySwatch: const MaterialColor(
        0xFF9E2A39,
        <int, Color>{
          50: Color(0xFFFCE8E8),
          100: Color(0xFFF5C2C2),
          200: Color(0xFFE79797),
          300: Color(0xFFD96C6C),
          400: Color(0xFFCB4949),
          500: Color(0xFF9E2A39),
          600: Color(0xFF8E2433),
          700: Color(0xFF7D1E2D),
          800: Color(0xFF6D1827),
          900: Color(0xFF5C1221),
        },
      ),
      primaryColor: const Color(0xFF9E2A39), // Bold red for primary elements
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF9E2A39),
        primary: const Color(0xFF9E2A39),
        secondary: Colors.white, // Lighter red for secondary elements
      ),
    );
    final TextStyle appBarTitleStyle = GoogleFonts.notoSerif(
      textStyle: baseTheme.textTheme.titleLarge,
      fontSize: 24.0,
      fontWeight: FontWeight.w700,
    );

    return MaterialApp(
      navigatorKey: navigatorKey, // Assign the key to MaterialApp
      debugShowCheckedModeBanner: false, // Optional: removes debug banner
      theme: baseTheme.copyWith(
        textTheme: baseTheme.textTheme.copyWith(
          titleLarge: baseTheme.textTheme.titleLarge?.copyWith(
            fontSize: 24.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        appBarTheme: baseTheme.appBarTheme.copyWith(
          titleTextStyle: appBarTitleStyle,
        ),
      ),
      builder: (context, child) {
        // Start preloading Discovery cover images as soon as MaterialApp builds
        _coverPreloadFuture ??= _preloadDiscoveryCoverImages(context);
        return child ?? const SizedBox.shrink();
      },
      home: _buildHomeWidget(authService, launchedFromShare),
    );
  }

  void _handleOnboardingFinished() {
    if (!_forceOnboarding || !mounted) {
      return;
    }
    setState(() {
      _forceOnboarding = false;
    });
  }

  Widget _buildHomeWidget(AuthService authService, bool launchedFromShare) {
    print(
        "MAIN BUILD DEBUG: _buildHomeWidget called with launchedFromShare=$launchedFromShare");

    // Prioritize data deletion page (public, no auth required)
    if (_showDataDeletion) {
      print("MAIN BUILD DEBUG: Showing DataDeletionScreen");
      return const DataDeletionScreen();
    }

    // NEW: Prioritize event share preview (for unauthenticated users)
    if (_initialEventShareToken != null && _initialEventShareToken!.isNotEmpty) {
      print(
          "MAIN BUILD DEBUG: Showing EventEditorModal for token: $_initialEventShareToken");
      return FutureBuilder<Map<String, dynamic>?>(
        future: _loadEventData(_initialEventShareToken!),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          if (snapshot.hasError || snapshot.data == null) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('Error'),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const AuthScreen(),
                        ),
                      );
                    },
                    child: const Text(
                      'Sign In',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(
                      'Unable to load event',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snapshot.hasError 
                          ? 'Error: ${snapshot.error}'
                          : 'Event not found',
                      style: Theme.of(context).textTheme.bodyMedium,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          final data = snapshot.data!;
          return EventEditorModal(
            event: data['event'] as Event,
            experiences: data['experiences'] as List<Experience>,
            categories: data['categories'] as List<UserCategory>,
            colorCategories: data['colorCategories'] as List<ColorCategory>,
            isReadOnly: true,
          );
        },
      );
    }

    // NEW: Prioritize discovery share preview on web
    if (kIsWeb &&
        _initialDiscoveryShareToken != null &&
        _initialDiscoveryShareToken!.isNotEmpty) {
      print(
          "MAIN BUILD DEBUG: Showing DiscoverySharePreviewScreen for token: $_initialDiscoveryShareToken");
      return DiscoverySharePreviewScreen(token: _initialDiscoveryShareToken!);
    }

    // NEW: Prioritize experience share preview on web (for unauthenticated users)
    if (kIsWeb &&
        _initialExperienceShareToken != null &&
        _initialExperienceShareToken!.isNotEmpty) {
      print(
          "MAIN BUILD DEBUG: Showing SharePreviewScreen for token: $_initialExperienceShareToken");
      return SharePreviewScreen(token: _initialExperienceShareToken!);
    }

    // NEW: Prioritize profile preview on web (for unauthenticated users)
    if (kIsWeb &&
        _initialProfileUserId != null &&
        _initialProfileUserId!.isNotEmpty) {
      print(
          "MAIN BUILD DEBUG: Showing PublicProfileScreen for userId: $_initialProfileUserId");
      return PublicProfileScreen(userId: _initialProfileUserId!);
    }

    // If we have shared files, show ReceiveShareScreen
    if (launchedFromShare && _sharedFiles != null && _sharedFiles!.isNotEmpty) {
      print(
          "MAIN BUILD DEBUG: Creating ReceiveShareScreen with ${_sharedFiles!.length} files");
      // iOS shared content handling - no toast needed
      return ChangeNotifierProvider(
        create: (_) => ReceiveShareProvider(),
        child: ReceiveShareScreen(
            sharedFiles: _sharedFiles!,
            onCancel: () {
              print("MyApp: Closing share screen launched initially");
              if (mounted) {
                setState(() {
                  _sharedFiles = null; // Clear shared files
                  _shouldShowReceiveShare = false; // Reset flag
                });
              }
              // No explicit reset needed with share_handler
            }),
      );
    }

    // Otherwise, proceed with normal auth flow
    print("MAIN BUILD DEBUG: Going to auth flow instead of ReceiveShareScreen");
    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        print("AUTH FLOW: connectionState=${snapshot.connectionState}, hasData=${snapshot.hasData}, hasError=${snapshot.hasError}");
        
        // Use currentUser if stream hasn't emitted yet (avoid waiting state)
        final User? effectiveUser = snapshot.hasData ? snapshot.data : authService.currentUser;
        
        print("AUTH FLOW: effectiveUser=${effectiveUser?.uid}");
        
        // If stream is waiting but we have a current user, use that user
        // If stream is waiting and no current user, go directly to AuthScreen
        // (no need to wait - there's no user to load)
        if (snapshot.connectionState == ConnectionState.waiting && effectiveUser == null) {
          print("AUTH FLOW: No user detected - showing AuthScreen immediately");
          return const AuthScreen();
        }

        // Initialize/cleanup NotificationStateService based on auth state
        final notificationService =
            Provider.of<NotificationStateService>(context, listen: false);
        if (effectiveUser != null) {
          // User is logged in - initialize notification service
          WidgetsBinding.instance.addPostFrameCallback((_) {
            notificationService.initializeForUser(effectiveUser.uid);
          });
        } else {
          // User is logged out - clean up notification service
          WidgetsBinding.instance.addPostFrameCallback((_) {
            notificationService.cleanup();
          });
        }

        // Print debug info
        print(
            'Auth state changed: ${effectiveUser != null ? 'Logged in' : 'Logged out'}');

        // --- ADDED: Reset share data on logout ---
        if (effectiveUser == null && _sharedFiles != null) {
          // If user logs out while share data is present, clear it
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _sharedFiles = null;
              });
              // No explicit reset needed with share_handler
              print("MyApp: Cleared share data due to logout.");
            }
          });
        }

        if (effectiveUser == null) {
          if (_forceOnboarding) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _forceOnboarding) {
                setState(() {
                  _forceOnboarding = false;
                });
              }
            });
          }
          return const AuthScreen();
        }

        final user = effectiveUser;
        print("AUTH FLOW: User logged in, uid=${user.uid}");
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, userSnapshot) {
            print("USER DOC: connectionState=${userSnapshot.connectionState}, hasData=${userSnapshot.hasData}, hasError=${userSnapshot.hasError}");
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              print("USER DOC: Waiting for user doc");
              return const _DelayedLoadingIndicator();
            }

            if (userSnapshot.hasError) {
              print("USER DOC: Error loading user doc: ${userSnapshot.error}");
              return const Center(child: Text('Unable to load profile.'));
            }

            final data = userSnapshot.data?.data();
            
            // Check if this user requires email verification (only new users)
            // Existing users won't have this field, so they pass through
            final requiresEmailVerification = 
                data?['requiresEmailVerification'] as bool? ?? false;
            final emailVerifiedAt = data?['emailVerifiedAt'];
            
            // If user requires verification and hasn't verified yet
            if (requiresEmailVerification && 
                emailVerifiedAt == null && 
                !user.emailVerified) {
              return EmailVerificationScreen(
                email: user.email ?? '',
                onVerified: () {
                  // Trigger a rebuild by reloading user
                  authService.reloadCurrentUser();
                },
              );
            }
            
            final username = (data?['username'] as String?)?.trim() ?? '';
            final firestoreDisplayName =
                (data?['displayName'] as String?)?.trim() ?? '';
            final authDisplayName = user.displayName?.trim() ?? '';
            final hasDisplayName =
                firestoreDisplayName.isNotEmpty || authDisplayName.isNotEmpty;
            final hasUsername = username.isNotEmpty;
            final hasFinishedOnboardingFlow =
                data?['hasFinishedOnboardingFlow'] as bool? ?? true;
            final requiresOnboarding =
                !hasDisplayName || !hasUsername || !hasFinishedOnboardingFlow;

            if (requiresOnboarding && !_forceOnboarding) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && !_forceOnboarding) {
                  setState(() {
                    _forceOnboarding = true;
                  });
                }
              });
            }

            final shouldShowOnboarding = requiresOnboarding || _forceOnboarding;
            print("USER DOC: requiresOnboarding=$requiresOnboarding, forceOnboarding=$_forceOnboarding, shouldShowOnboarding=$shouldShowOnboarding");

            if (shouldShowOnboarding) {
              print("USER DOC: Showing OnboardingScreen");
              return OnboardingScreen(
                onFinishedFlow: _handleOnboardingFinished,
              );
            }
            print("USER DOC: Showing MainScreen");
            return const MainScreen();
          },
        );
      },
    );
  }
}

// Minimal converters duplicated here for main.dart context
List<SharedMediaFile> _convertSharedMedia(SharedMedia media) {
  final List<SharedMediaFile> out = [];
  final content = media.content;
  if (content != null && content.trim().isNotEmpty) {
    final url = _extractFirstUrl(content);
    out.add(SharedMediaFile(
      // Use the extracted URL if found, otherwise use the full content
      // This handles cases like "Share the event! https://..." where we only want the URL
      path: url ?? content,
      thumbnail: null,
      duration: null,
      type: url != null ? SharedMediaType.url : SharedMediaType.text,
    ));
  }
  final atts = media.attachments ?? [];
  for (final att in atts) {
    if (att == null) continue;
    SharedMediaType t = SharedMediaType.file;
    switch (att.type) {
      case SharedAttachmentType.image:
        t = SharedMediaType.image;
        break;
      case SharedAttachmentType.video:
        t = SharedMediaType.video;
        break;
      case SharedAttachmentType.file:
      default:
        t = SharedMediaType.file;
    }
    out.add(SharedMediaFile(
      path: att.path,
      thumbnail: null,
      duration: null,
      type: t,
    ));
  }
  return out;
}

String? _extractFirstUrl(String text) {
  if (text.isEmpty) return null;
  final RegExp urlRegex = RegExp(
      r"(?:(?:https?|ftp):\/\/|www\.)[-a-zA-Z0-9@:%._\+~#=]{1,256}\.[a-zA-Z0-9()]{1,6}\b(?:[-a-zA-Z0-9()@:%_\+.~#?&\/=]*)",
      caseSensitive: false);
  final match = urlRegex.firstMatch(text);
  return match?.group(0);
}

// Simple observer for app lifecycle events
class AppLifecycleObserver extends WidgetsBindingObserver {
  final VoidCallback? onResumed;
  final VoidCallback? onPaused;

  AppLifecycleObserver({this.onResumed, this.onPaused});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    print("LIFECYCLE: App state changed to $state");

    if (state == AppLifecycleState.resumed && onResumed != null) {
      onResumed!();
    } else if (state == AppLifecycleState.paused && onPaused != null) {
      onPaused!();
    }
  }
}

class _DelayedLoadingIndicator extends StatefulWidget {
  const _DelayedLoadingIndicator({this.delay = const Duration(seconds: 5)});

  final Duration delay;

  @override
  State<_DelayedLoadingIndicator> createState() =>
      _DelayedLoadingIndicatorState();
}

class _DelayedLoadingIndicatorState extends State<_DelayedLoadingIndicator> {
  bool _showSpinner = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.delay, () {
      if (!mounted) {
        return;
      }
      setState(() {
        _showSpinner = true;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final background = Theme.of(context).scaffoldBackgroundColor;
    return ColoredBox(
      color: background,
      child: _showSpinner
          ? const Center(child: CircularProgressIndicator())
          : const SizedBox.shrink(),
    );
  }
}
