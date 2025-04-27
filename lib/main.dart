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

// Define a GlobalKey for the Navigator
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");

  await Firebase.initializeApp();

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
  SharingService().init();
  runApp(MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  _MyAppState createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  final AuthService _authService = AuthService();
  final SharingService _sharingService = SharingService();
  StreamSubscription? _intentSub;
  List<SharedMediaFile>? _sharedFiles;

  @override
  void initState() {
    super.initState();

    print("MAIN: App initializing");

    // Check for initial shared files when app was closed
    ReceiveSharingIntent.instance
        .getInitialMedia()
        .then((List<SharedMediaFile>? value) {
      print("MAIN: Initial media check complete");

      if (value != null && value.isNotEmpty) {
        print("MAIN: Found initial shared files: ${value.length}");
        setState(() {
          _sharedFiles = value;
        });

        // Don't reset on first load to ensure we keep the data
        // ReceiveSharingIntent.instance.reset();
        print("MAIN: Stored initial share data for display");
      } else {
        print("MAIN: No initial shared files found");
      }
    });

    // Listen for app going to foreground to reinitialize sharing capabilities
    WidgetsBinding.instance.addObserver(AppLifecycleObserver(
      onResumed: () {
        // Recreate listeners when app comes to foreground
        print("MAIN: App resumed - recreating sharing service listeners");
        _sharingService.recreateListeners();
      },
      onPaused: () {
        print("MAIN: App paused");
      },
    ));

    // Listen for incoming shares while the app is running
    _intentSub = ReceiveSharingIntent.instance.getMediaStream().listen(
        (List<SharedMediaFile> value) {
      setState(() {
        _sharedFiles = value;
      });
      // Optionally, navigate immediately if context is available
      // This might need refinement depending on app structure
      if (navigatorKey.currentContext != null && value.isNotEmpty) {
        _sharingService.showReceiveShareScreen(
            navigatorKey.currentContext!, value);
      }
    }, onError: (err) {
      print("getIntentDataStream error: $err");
    });
  }

  @override
  void dispose() {
    // Clean up observers
    WidgetsBinding.instance.removeObserver(AppLifecycleObserver());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Check if launched from share AND there are files
    bool launchedFromShare = _sharedFiles != null && _sharedFiles!.isNotEmpty;

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
                    _sharedFiles = null; // Clear shared files
                    ReceiveSharingIntent.instance.reset(); // Reset intent
                    // Trigger rebuild to show AuthWrapper/MainScreen
                    setState(() {});
                    // Potentially navigate to a default screen if needed
                    // navigatorKey.currentState?.pushReplacementNamed('/');
                  }),
            )
          // Otherwise, proceed with normal auth flow
          : StreamBuilder<User?>(
              stream: AuthService().authStateChanges,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator());
                }

                // Print debug info
                print(
                    'Auth state changed: ${snapshot.hasData ? 'Logged in' : 'Logged out'}');

                return snapshot.hasData ? MainScreen() : AuthScreen();
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
