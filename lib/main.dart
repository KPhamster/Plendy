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
import 'screens/receive_share_screen.dart';
import 'screens/follow_requests_screen.dart'; // Import FollowRequestsScreen
import 'screens/messages_screen.dart'; // Import MessagesScreen
import 'services/auth_service.dart';
import 'services/sharing_service.dart';
import 'models/shared_media_compat.dart';
import 'services/notification_state_service.dart'; // Import NotificationStateService
import 'package:provider/provider.dart';
import 'providers/receive_share_provider.dart';
import 'providers/category_save_progress_notifier.dart';
import 'dart:async'; // Import dart:async for StreamSubscription
import 'services/google_maps_service.dart'; // ADDED: Import GoogleMapsService
import 'firebase_options.dart'; // Import Firebase options
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode; // Import kIsWeb, kReleaseMode
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:app_links/app_links.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'screens/share_preview_screen.dart';
import 'screens/category_share_preview_screen.dart';

// Define a GlobalKey for the Navigator
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();


// Debug logging function for cold start issues
// _writeDebugLog disabled (unused)

// Initialize FlutterLocalNotificationsPlugin (if you want to show foreground notifications)
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// FCM: Background message handler (must be a top-level function)
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform, // Ensure Firebase is initialized here too
  );
  print("Handling a background message: ${message.messageId}");
  print("Background Message data: ${message.data}");
   if (message.notification != null) {
      print('Background message also contained a notification: ${message.notification}');
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
    if (initial != null && ((initial.content?.isNotEmpty ?? false) || (initial.attachments?.isNotEmpty ?? false))) {
      final files = _convertSharedMedia(initial);
      print("🎯 DEBUG: Found INITIAL shared data: ${files.length} items");
      for (var item in files) {
        print("🎯 DEBUG: ${item.type}: ${item.path}");
      }
      // Shared content received - no toast needed
    }

    // Note: URL/text are delivered via getInitialMedia as SharedMediaType.text on iOS
    
    // Also check the stream for live updates
    ShareHandlerPlatform.instance.sharedMediaStream.listen((media) {
      final value = _convertSharedMedia(media);
      if (value.isNotEmpty) {
        print("🎯 DEBUG: Found STREAM shared data: ${value.length} items");
        for (var item in value) {
          print("🎯 DEBUG: ${item.type}: ${item.path}");
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

Future<void> _configureLocalNotifications() async {
  // Ensure you have an app icon, e.g., android/app/src/main/res/mipmap-hdpi/ic_launcher.png
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher'); 
  
  // Add iOS and macOS settings
  const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
    requestSoundPermission: false,
    requestBadgePermission: false,
    requestAlertPermission: false,
  );
  
  const DarwinInitializationSettings initializationSettingsMacOS = DarwinInitializationSettings(
    requestSoundPermission: false,
    requestBadgePermission: false,
    requestAlertPermission: false,
  );

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
    macOS: initializationSettingsMacOS,
  );
  await flutterLocalNotificationsPlugin.initialize(
    initializationSettings,
    onDidReceiveNotificationResponse: (NotificationResponse notificationResponse) {
      // Handle notification tap when app is in foreground/background but not terminated
      print('Local notification tapped with payload: ${notificationResponse.payload}');
      if (notificationResponse.payload != null && notificationResponse.payload!.isNotEmpty) {
        // Navigate based on the payload (screen path)
        final screen = notificationResponse.payload!;
        print("Local notification: Navigating to screen: $screen");
        
        if (screen == '/follow_requests' && navigatorKey.currentState != null) {
          navigatorKey.currentState!.push(
            MaterialPageRoute(
              builder: (context) => const FollowRequestsScreen(),
            ),
          );
        }
      }
    }
  );
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

  // Initialize sharing service
  // Conditionally initialize SharingService if not on web
  if (!kIsWeb) {
    SharingService().init();
    
    // DEBUG: Start timer to check for shared data (Android only)
    if (Platform.isAndroid) {
      _startShareDebugTimer();
    }

    // --- FCM Setup ---
    // Setup local notifications in background to not delay splash screen
    unawaited(_configureLocalNotifications());

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('FCM: Got a message whilst in the foreground!');
      print('FCM: Message data: ${message.data}');

      if (message.notification != null) {
        print('FCM: Message also contained a notification: ${message.notification}');
        flutterLocalNotificationsPlugin.show(
          message.hashCode, 
          message.notification!.title,
          message.notification!.body,
          const NotificationDetails( // Use const for NotificationDetails
            android: AndroidNotificationDetails(
              'plendy_follow_channel', // Unique channel ID
              'Follow Notifications', // Channel name
              channelDescription: 'Notifications for new followers and follow requests.',
              importance: Importance.max,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher', 
            ),
            // iOS: DarwinNotificationDetails(), // Add if needed
          ),
          payload: message.data['screen'] as String?, // Example: screen to navigate to
        );
      }
    });

    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      print('FCM: Message clicked and opened app!');
      print('FCM: Message data: ${message.data}');
      final screen = message.data['screen'] as String?;
      final type = message.data['type'] as String?;
      
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
          print("FCM: New follower notification - would navigate to user profile");
          // You could implement navigation to user profile here:
          // final followerId = message.data['followerId'] as String?;
          // if (followerId != null) {
          //   // Navigate to user profile screen with followerId
          // }
        } else if (type == 'new_message' && screen == '/messages') {
          // Navigate to Messages screen, and potentially to the specific chat
          final threadId = message.data['threadId'] as String?;
          final senderId = message.data['senderId'] as String?;
          
          print("FCM: New message notification - threadId: $threadId, senderId: $senderId");
          
          // Navigate to Messages screen first
          navigatorKey.currentState!.push(
            MaterialPageRoute(
              builder: (context) => const MessagesScreen(),
            ),
          );
          
          // TODO: If threadId is provided, you could navigate directly to the chat
          // This would require updating the MessagesScreen to accept navigation parameters
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
      ],
      child: const MyApp(),
    ),
  );
}


Future<void> _initializeAppCheck() async {
  try {
    if (kIsWeb) {
      await FirebaseAppCheck.instance.activate(
        webProvider: ReCaptchaV3Provider('6Ldt0sIrAAAAABBHbSmj07DU8gEEzqijAk70XwKA'),
        androidProvider: AndroidProvider.playIntegrity,
        appleProvider: AppleProvider.appAttest,
      );
      print('App Check activated (web + providers).');
    } else {
      // Use Debug provider for debug/profile builds to simplify local dev.
      final androidProvider = kReleaseMode
          ? AndroidProvider.playIntegrity
          : AndroidProvider.debug;
      final appleProvider = kReleaseMode
          ? AppleProvider.appAttest
          : AppleProvider.debug;

      await FirebaseAppCheck.instance.activate(
        androidProvider: androidProvider,
        appleProvider: appleProvider,
      );
      print('App Check activated (native providers: ' +
          (kReleaseMode ? 'release' : 'debug') + ')');
    }
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
    // Force initial token request so reCAPTCHA key leaves "Incomplete" and headers appear
    try {
      final token = await FirebaseAppCheck.instance.getToken(true);
      print('App Check initial token fetched: ' + (token != null && token.isNotEmpty ? 'ok' : 'empty'));
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
  bool _deepLinkStreamFired = false; // Track if a fresh deep link arrived via stream
  static const int _maxNavigatorPushRetries = 12;

  void _pushRouteWhenReady(WidgetBuilder builder, {RouteSettings? settings, int attempt = 0}) {
    if (!mounted) {
      return;
    }
    if (navigatorKey.currentState?.mounted ?? false) {
      navigatorKey.currentState!.push(MaterialPageRoute(builder: builder, settings: settings));
      return;
    }
    if (attempt >= _maxNavigatorPushRetries) {
      print('DeepLink: Navigator not ready after ${attempt + 1} attempts; dropping deep link navigation');
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
    final String core = hashIndex >= 0 ? raw.substring(prefix.length, hashIndex) : raw.substring(prefix.length);
    if (core.isEmpty) {
      return uri;
    }
    final String candidate = 'https://' + core;
    try {
      return Uri.parse(candidate);
    } catch (e) {
      print('DeepLink: Failed to coerce intent URI: ' + e.toString());
      return uri;
    }
  }

  Uri? _tryExtractNestedUri(Uri uri) {
    final String? linkParam = uri.queryParameters['link'];
    if (linkParam != null && linkParam.isNotEmpty) {
      try {
        final Uri nested = Uri.parse(linkParam);
        print('DeepLink: Unwrapped link parameter -> ' + nested.toString());
        return nested;
      } catch (e) {
        print('DeepLink: Failed to parse link parameter "' + linkParam + '": ' + e.toString());
      }
    }

    final String? deepLinkId = uri.queryParameters['deep_link_id'];
    if (deepLinkId != null && deepLinkId.isNotEmpty) {
      try {
        final Uri nested = Uri.parse(deepLinkId);
        print('DeepLink: Unwrapped deep_link_id -> ' + nested.toString());
        return nested;
      } catch (e) {
        print('DeepLink: Failed to parse deep_link_id "' + deepLinkId + '": ' + e.toString());
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
            print('DeepLink: Unwrapped al_applink_data target_url -> ' + nested.toString());
            return nested;
          }
        }
      } catch (e) {
        print('DeepLink: Failed to parse al_applink_data: ' + e.toString());
      }
    }

    if (uri.fragment.isNotEmpty) {
      final String fragment = uri.fragment;
      if (fragment.startsWith('http')) {
        try {
          final Uri nested = Uri.parse(fragment);
          print('DeepLink: Unwrapped fragment URL -> ' + nested.toString());
          return nested;
        } catch (e) {
          print('DeepLink: Failed to parse fragment URI "' + fragment + '": ' + e.toString());
        }
      } else if (uri.host.isNotEmpty) {
        final String prefix = (uri.scheme.isEmpty ? 'https' : uri.scheme) + '://' + uri.host;
        final String candidate = fragment.startsWith('/') ? fragment : '/' + fragment;
        try {
          final Uri nested = Uri.parse(prefix + candidate);
          print('DeepLink: Composed fragment URL -> ' + nested.toString());
          return nested;
        } catch (e) {
          print('DeepLink: Failed to compose fragment URI "' + fragment + '": ' + e.toString());
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

        final value = media != null ? _convertSharedMedia(media) : <SharedMediaFile>[];

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
              if (file.type == SharedMediaType.text || file.type == SharedMediaType.url) {
                String content = file.path.toLowerCase();
                if (content.contains('yelp.com/biz') || content.contains('yelp.to/')) {
                  isYelpUrl = true;
                  break;
                }
              }
            }
            
            // For Yelp URLs during cold start, always create ReceiveShareScreen
            // but let it handle restoration internally
            if (isYelpUrl) {
              print("MAIN: Cold start Yelp URL detected - will create ReceiveShareScreen with restoration logic");
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
        if (!kIsWeb) {
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
          print('DeepLink: Skipping delayed initial app link (stream already fired)');
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
    print('DeepLink: Processing URI: ' + uri.toString());
    if (normalizedUri != uri) {
      print('DeepLink: Normalized URI: ' + normalizedUri.toString());
    }
    final List<String> segments = normalizedUri.pathSegments;
    print('DeepLink: Path segments: ' + segments.toString());

    if (segments.isEmpty) {
      return;
    }

    final String firstSegment = segments.first.toLowerCase();

    if (firstSegment == 'shared') {
      final String? rawToken = segments.length > 1 ? segments[1] : null;
      final String? token = _cleanToken(rawToken);
      print('DeepLink: Experience share - rawToken: ' + rawToken.toString() + ', cleanToken: ' + token.toString());
      if (token != null && token.isNotEmpty) {
        if (rawToken != null && rawToken != token) {
          print('DeepLink: Sanitized share token from ' + rawToken + ' to ' + token);
        }
        _pushRouteWhenReady(
          (_) => SharePreviewScreen(token: token),
          settings: RouteSettings(name: '/shared/' + token),
        );
      } else {
        print('DeepLink: Experience share token missing or empty.');
      }
    } else if (firstSegment == 'shared-category') {
      final String? rawToken = segments.length > 1 ? segments[1] : null;
      final String? token = _cleanToken(rawToken);
      print('DeepLink: Category share - rawToken: ' + rawToken.toString() + ', cleanToken: ' + token.toString());
      if (token != null && token.isNotEmpty) {
        if (rawToken != null && rawToken != token) {
          print('DeepLink: Sanitized category share token from ' + rawToken + ' to ' + token);
        }
        _pushRouteWhenReady(
          (_) => CategorySharePreviewScreen(token: token),
          settings: RouteSettings(name: '/shared-category/' + token),
        );
      } else {
        print('DeepLink: Category share token missing or empty.');
      }
    } else {
      print('DeepLink: No handler for path segments: ' + segments.toString());
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
    bool launchedFromShare = !kIsWeb && _shouldShowReceiveShare && _sharedFiles != null && _sharedFiles!.isNotEmpty;
    
    print("MAIN BUILD DEBUG: Detailed calculation:");
    print("  !kIsWeb = ${!kIsWeb}");
    print("  _shouldShowReceiveShare = $_shouldShowReceiveShare");
    print("  _sharedFiles != null = ${_sharedFiles != null}");
    if (_sharedFiles != null) {
      print("  _sharedFiles!.isNotEmpty = ${_sharedFiles!.isNotEmpty}");
    }
    print("  Final launchedFromShare = $launchedFromShare");
    
    print("MAIN BUILD DEBUG: _initialCheckComplete=$_initialCheckComplete, kIsWeb=$kIsWeb, _sharedFiles is null? ${_sharedFiles == null}");
    print("MAIN BUILD DEBUG: _shouldShowReceiveShare=$_shouldShowReceiveShare");
    if (_sharedFiles != null) {
      print("MAIN BUILD DEBUG: _sharedFiles count=${_sharedFiles!.length}");
      if (_sharedFiles!.isNotEmpty) {
        print("MAIN BUILD DEBUG: first file=${_sharedFiles!.first.path.substring(0, math.min(100, _sharedFiles!.first.path.length))}");
      }
    }
    print("MAIN BUILD DEBUG: launchedFromShare=$launchedFromShare, _initialCheckComplete=$_initialCheckComplete");
    
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
      print("MAIN: Cold start with shared files - will create ReceiveShareScreen");
    } else {
      print("MAIN: No shared files or not cold start - proceeding to normal auth flow");
    }

    // --- ADDED: Get AuthService from Provider ---
    final authService = Provider.of<AuthService>(context, listen: false);

    return MaterialApp(
      navigatorKey: navigatorKey, // Assign the key to MaterialApp
      debugShowCheckedModeBanner: false, // Optional: removes debug banner
      theme: ThemeData(
        primarySwatch: Colors.red,
        primaryColor: const Color(0xFFD40000), // Bold red for primary elements
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD40000),
          primary: const Color(0xFFD40000),
          secondary: Colors.white, // Lighter red for secondary elements
        ),
      ),
      home: _buildHomeWidget(authService, launchedFromShare),
    );
  }

  Widget _buildHomeWidget(AuthService authService, bool launchedFromShare) {
    print("MAIN BUILD DEBUG: _buildHomeWidget called with launchedFromShare=$launchedFromShare");
    
    // If we have shared files, show ReceiveShareScreen
    if (launchedFromShare && _sharedFiles != null && _sharedFiles!.isNotEmpty) {
      print("MAIN BUILD DEBUG: Creating ReceiveShareScreen with ${_sharedFiles!.length} files");
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
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        // Initialize/cleanup NotificationStateService based on auth state
        final notificationService = Provider.of<NotificationStateService>(context, listen: false);
        if (snapshot.hasData && snapshot.data?.uid != null) {
          // User is logged in - initialize notification service
          WidgetsBinding.instance.addPostFrameCallback((_) {
            notificationService.initializeForUser(snapshot.data!.uid);
          });
        } else {
          // User is logged out - clean up notification service
          WidgetsBinding.instance.addPostFrameCallback((_) {
            notificationService.cleanup();
          });
        }

        // Print debug info
        print('Auth state changed: ${snapshot.hasData ? 'Logged in' : 'Logged out'}');

        // --- ADDED: Reset share data on logout ---
        if (!snapshot.hasData && _sharedFiles != null) {
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

        return snapshot.hasData
            ? const MainScreen()
            : const AuthScreen();
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
      path: content,
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
