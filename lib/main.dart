import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'screens/auth_screen.dart';
import 'screens/main_screen.dart';
import 'screens/receive_share_screen.dart';
import 'services/auth_service.dart';
import 'services/sharing_service.dart';
import 'package:provider/provider.dart';
import 'providers/receive_share_provider.dart';
import 'dart:async'; // Import dart:async for StreamSubscription
import 'services/google_maps_service.dart'; // ADDED: Import GoogleMapsService
import 'firebase_options.dart'; // Import Firebase options
import 'package:flutter/foundation.dart' show kIsWeb; // Import kIsWeb

// Define a GlobalKey for the Navigator
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

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
  }
  runApp(
    Provider<AuthService>(
      create: (_) => AuthService(),
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
