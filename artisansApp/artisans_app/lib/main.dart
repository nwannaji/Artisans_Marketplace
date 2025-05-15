import 'package:artisans_app/auth/login_screen.dart';
import 'package:artisans_app/auth/sign_up.dart';
import 'package:artisans_app/models/user.dart';
import 'package:artisans_app/screens/artisan_dashboard.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await FirebaseAppCheck.instance.activate(
    androidProvider: AndroidProvider.debug,
    appleProvider: AppleProvider.debug,
  );
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This function checks the user's status and determines the next screen
  Future<Widget> _getInitialScreen() async {
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser != null) {
      final artisanDoc =
          await FirebaseFirestore.instance
              .collection('artisans')
              .doc(currentUser.uid)
              .get();

      if (artisanDoc.exists) {
        // If user is an artisan, show the Artisan Dashboard
        return ArtisanDashboardScreen();
      } else {
        // If the user is not an artisan, show the Artisan Dashboard to view available artisans
        return ArtisanDashboardScreen();
      }
    }
    // If the user is not logged in, show the login screen
    return const LoginScreen();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Artisan Services',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        appBarTheme: const AppBarTheme(elevation: 0, centerTitle: true),
      ),
      onGenerateRoute: (settings) {
        switch (settings.name) {
          case '/login':
            return MaterialPageRoute(builder: (_) => const LoginScreen());
          case '/signup':
            final args = settings.arguments as AppUser;
            return MaterialPageRoute(
              builder: (_) => ArtisanSignUpScreen(appUser: args),
            );
          case '/artisan_dashboard':
            return MaterialPageRoute(builder: (_) => ArtisanDashboardScreen());
          default:
            return MaterialPageRoute(builder: (_) => const SplashScreen());
        }
      },
      home: FutureBuilder<Widget>(
        future: _getInitialScreen(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SplashScreen();
          } else if (snapshot.hasError) {
            return const Center(child: Text('Error loading app'));
          } else {
            return snapshot.data!;
          }
        },
      ),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
      backgroundColor: Color.fromARGB(255, 104, 133, 146),
    );
  }
}
