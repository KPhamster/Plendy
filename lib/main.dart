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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load environment variables
  await dotenv.load(fileName: ".env");

  await Firebase.initializeApp();
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
  final SharingService _sharingService = SharingService();
  List<SharedMediaFile>? _initialSharedFiles;

  @override
  void initState() {
    super.initState();

    // Check for initial shared files when app was closed
    ReceiveSharingIntent.instance
        .getInitialMedia()
        .then((List<SharedMediaFile> value) {
      if (value.isNotEmpty) {
        setState(() {
          _initialSharedFiles = value;
        });
        // Tell the library that we've handled the initial intent
        ReceiveSharingIntent.instance.reset();
        print("Initial share intent reset completed");
      }
    });

    // Listen for app going to foreground to reset sharing capabilities
    WidgetsBinding.instance.addObserver(AppLifecycleObserver(onResumed: () {
      // Reset when app comes to foreground to be ready for new shares
      _sharingService.resetSharedItems();
    }));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // Optional: removes debug banner
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: _initialSharedFiles != null && _initialSharedFiles!.isNotEmpty
          ? ReceiveShareScreen(
              sharedFiles: _initialSharedFiles!,
              onCancel: () {
                setState(() {
                  _initialSharedFiles = null;
                });
                _sharingService.resetSharedItems();

                // Navigate to the appropriate screen based on authentication state
                final user = AuthService().currentUser;
                if (user != null) {
                  Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (context) => MainScreen()));
                } else {
                  Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (context) => AuthScreen()));
                }
              },
            )
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

  AppLifecycleObserver({this.onResumed});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && onResumed != null) {
      onResumed!();
    }
  }
}
