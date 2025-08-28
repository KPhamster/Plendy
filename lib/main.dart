import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'dart:io';
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
import 'services/auth_service.dart';
import 'services/sharing_service.dart';
import 'models/shared_media_compat.dart';
import 'services/notification_state_service.dart'; // Import NotificationStateService
import 'package:provider/provider.dart';
import 'providers/receive_share_provider.dart';
import 'dart:async'; // Import dart:async for StreamSubscription
import 'services/google_maps_service.dart'; // ADDED: Import GoogleMapsService
import 'firebase_options.dart'; // Import Firebase options
import 'package:flutter/foundation.dart' show kIsWeb; // Import kIsWeb
import 'package:fluttertoast/fluttertoast.dart';

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
      // Show a toast to indicate we received data
      if (!kIsWeb) {
        Fluttertoast.showToast(
          msg: "Received ${files.length} shared item(s)",
          toastLength: Toast.LENGTH_LONG,
          gravity: ToastGravity.TOP,
          backgroundColor: Colors.green,
          textColor: Colors.white,
        );
      }
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
        // Show a toast to indicate we received data
        if (!kIsWeb) {
          Fluttertoast.showToast(
            msg: "Stream received ${value.length} item(s)",
            toastLength: Toast.LENGTH_LONG,
            gravity: ToastGravity.TOP,
            backgroundColor: Colors.blue,
            textColor: Colors.white,
          );
        }
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

  // Load environment variables (if .env file exists)
  try {
    await dotenv.load(fileName: ".env");
  } catch (e) {
    print('No .env file found - using API keys from config files instead: $e');
  }

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
    
    // DEBUG: Start timer to check for shared data
    _startShareDebugTimer();

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
  bool _initialCheckComplete = false;
  bool _shouldShowReceiveShare = false;

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
        primarySwatch: Colors.blue,
      ),
      home: _buildHomeWidget(authService, launchedFromShare),
    );
  }

  Widget _buildHomeWidget(AuthService authService, bool launchedFromShare) {
    print("MAIN BUILD DEBUG: _buildHomeWidget called with launchedFromShare=$launchedFromShare");
    
    // If we have shared files, show ReceiveShareScreen
    if (launchedFromShare && _sharedFiles != null && _sharedFiles!.isNotEmpty) {
      print("MAIN BUILD DEBUG: Creating ReceiveShareScreen with ${_sharedFiles!.length} files");
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
