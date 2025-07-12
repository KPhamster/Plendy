import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_messaging/firebase_messaging.dart'; // FCM Import
import 'package:flutter_local_notifications/flutter_local_notifications.dart'; // Local Notifications Import
import 'screens/auth_screen.dart';
import 'screens/main_screen.dart';
import 'screens/receive_share_screen.dart';
import 'screens/follow_requests_screen.dart'; // Import FollowRequestsScreen
import 'services/auth_service.dart';
import 'services/sharing_service.dart';
import 'services/notification_state_service.dart'; // Import NotificationStateService
import 'package:provider/provider.dart';
import 'providers/receive_share_provider.dart';
import 'dart:async'; // Import dart:async for StreamSubscription
import 'services/google_maps_service.dart'; // ADDED: Import GoogleMapsService
import 'firebase_options.dart'; // Import Firebase options
import 'package:flutter/foundation.dart' show kIsWeb; // Import kIsWeb

// Define a GlobalKey for the Navigator
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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

Future<void> _configureLocalNotifications() async {
  // Ensure you have an app icon, e.g., android/app/src/main/res/mipmap-hdpi/ic_launcher.png
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher'); 
  
  // iOS settings
  const DarwinInitializationSettings initializationSettingsIOS = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  
  // macOS settings
  const DarwinInitializationSettings initializationSettingsMacOS = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
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

  // Load environment variables
  await dotenv.load(fileName: ".env");

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // --- ADDED: Preload user location silently --- START ---
  try {
    print("📍 MAIN: Starting background location preload...");
    final mapsService = GoogleMapsService();
    await mapsService.getCurrentLocation(); // Attempt to get location
    print("📍 MAIN: Background location preload attempt finished.");
  } catch (e) {
    // Catch errors silently - we don't want to crash the app or bother the user here.
    print(
        "📍 MAIN: Error during background location preload (expected if permissions not granted yet): $e");
  }
  // --- ADDED: Preload user location silently --- END ---

  // Initialize sharing service
  // Conditionally initialize SharingService if not on web
  if (!kIsWeb) {
    SharingService().init();

    // --- FCM Setup ---
    await _configureLocalNotifications(); // Setup for local notifications (foreground)

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
            iOS: DarwinNotificationDetails(), // iOS notification details
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
      ],
      child: const MyApp(),
    ),
  );
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

  @override
  void initState() {
    super.initState();

    print("MAIN: App initializing");

    if (!kIsWeb) {
      // Check for initial shared files when app was closed
      ReceiveSharingIntent.instance
          .getInitialMedia()
          .then((List<SharedMediaFile>? value) {
        print("MAIN: Initial media check complete");

        if (value != null && value.isNotEmpty) {
          print("MAIN: Found initial shared files: ${value.length}");
          if (mounted) {
            setState(() {
              _sharedFiles = value;
            });
          }
          print("MAIN: Stored initial share data for display");
        } else {
          print("MAIN: No initial shared files found");
        }
      }).catchError((err) {
        print("MAIN: Error getting initial media (expected on web): $err");
      });

      // Listen for incoming shares while the app is running
      _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
          (List<SharedMediaFile> value) {
        if (mounted) {
          setState(() {
            _sharedFiles = value;
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
    // Check if launched from share AND there are files
    // Only consider launchedFromShare if not on web and files are present
    bool launchedFromShare = !kIsWeb && _sharedFiles != null && _sharedFiles!.isNotEmpty;

    // --- ADDED: Get AuthService from Provider ---
    final authService = Provider.of<AuthService>(context, listen: false);

    return MaterialApp(
      navigatorKey: navigatorKey, // Assign the key to MaterialApp
      debugShowCheckedModeBanner: false, // Optional: removes debug banner
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: launchedFromShare
          // If launched from share, show ReceiveShareScreen directly, wrapped in Provider
          ? ChangeNotifierProvider(
              create: (_) => ReceiveShareProvider(),
              child: ReceiveShareScreen(
                  sharedFiles: _sharedFiles!,
                  onCancel: () {
                    // Logic to navigate back or close app
                    // Maybe SystemNavigator.pop() or navigate to MainScreen
                    print("MyApp: Closing share screen launched initially");
                    if (mounted) {
                      setState(() {
                        // Use setState to trigger rebuild
                        _sharedFiles = null; // Clear shared files
                      });
                    }
                    if (!kIsWeb) {
                      ReceiveSharingIntent.instance.reset(); // Reset intent
                    }
                    // No explicit navigation needed here, the StreamBuilder below will handle it
                  }),
            )
          // Otherwise, proceed with normal auth flow
          : StreamBuilder<User?>(
              // --- MODIFIED: Use provided AuthService instance ---
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
                print(
                    'Auth state changed: ${snapshot.hasData ? 'Logged in' : 'Logged out'}');

                // --- ADDED: Reset share data on logout ---
                if (!snapshot.hasData && _sharedFiles != null) {
                  // If user logs out while share data is present, clear it
                  // Use a post-frame callback to avoid calling setState during build
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) {
                      // Check if still mounted
                      setState(() {
                        _sharedFiles = null;
                      });
                      if (!kIsWeb) {
                        ReceiveSharingIntent.instance.reset();
                      }
                      print("MyApp: Cleared share data due to logout.");
                    }
                  });
                }

                return snapshot.hasData
                    ? const MainScreen()
                    : const AuthScreen();
              },
            ),
    );
  }
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
