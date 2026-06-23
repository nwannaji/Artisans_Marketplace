// lib/main.dart
import 'package:artisans_app/auth/login_logic.dart';
import 'package:artisans_app/auth/signup_logic.dart';
import 'package:artisans_app/screens/artisan_dashboard.dart';
import 'package:artisans_app/screens/user_home_screen.dart';
import 'package:artisans_app/screens/admin_dashboard.dart';
import 'package:artisans_app/screens/artisan_profile.dart';
import 'package:artisans_app/screens/conversations_screen.dart';
import 'package:artisans_app/screens/escrow_payment_screen.dart';
import 'package:artisans_app/screens/account_settings_screen.dart';
import 'package:artisans_app/screens/booking_history_screen.dart';
import 'package:artisans_app/screens/edit_artisan_profile_screen.dart';
import 'package:artisans_app/screens/wallet_screen.dart';
import 'package:artisans_app/screens/dispute_screen.dart';
import 'package:artisans_app/screens/admin_dispute_screen.dart';
import 'package:artisans_app/screens/admin_escrow_screen.dart';
import 'package:artisans_app/screens/admin_customers_screen.dart';
import 'package:artisans_app/screens/admin_chat_screen.dart';
import 'package:artisans_app/screens/artisan_map_screen.dart';
import 'package:artisans_app/models/artisan.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:artisans_app/viewmodels/auth_view_model.dart';
import 'package:artisans_app/viewmodels/profile_view_model.dart';
import 'package:artisans_app/viewmodels/chat_view_model.dart';
import 'package:artisans_app/viewmodels/payment_view_model.dart';
import 'package:artisans_app/viewmodels/admin_view_model.dart';
import 'package:artisans_app/models/user.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // App-wide color constants
  static const Color primaryColor = Color(0xFF00897B);       // Teal 600
  static const Color primaryDark = Color(0xFF00695C);         // Teal 800
  static const Color primaryLight = Color(0xFFB2DFDB);        // Teal 100
  static const Color accentColor = Color(0xFFFFB300);          // Amber 600
  static const Color backgroundColor = Color(0xFFECEFF1);      // Blue Grey 50
  static const Color surfaceColor = Color(0xFFFFFFFF);
  static const Color textPrimary = Color(0xFF212121);
  static const Color textSecondary = Color(0xFF757575);

  Future<Widget> _getInitialScreen() async {
    final authViewModel = AuthViewModel();
    final isAuth = await authViewModel.checkAuth();
    if (isAuth && authViewModel.currentUser != null) {
      final role = authViewModel.currentUser!.role;
      if (role == UserRole.customer) {
        return const HomePage();
      } else if (role == UserRole.artisan) {
        return const ArtisanDashboardScreen();
      } else if (role == UserRole.admin) {
        return const AdminDashboard();
      }
    }
    return const LoginPage();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthViewModel()),
        ChangeNotifierProvider(create: (_) => ProfileViewModel()),
        ChangeNotifierProvider(create: (_) => ChatViewModel()),
        ChangeNotifierProvider(create: (_) => PaymentViewModel()),
        ChangeNotifierProvider(create: (_) => AdminViewModel()),
      ],
      child: MaterialApp(
        title: 'Artisan Services',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: primaryColor,
            primary: primaryColor,
            secondary: accentColor,
            surface: surfaceColor,
          ),
          primaryColor: primaryColor,
          scaffoldBackgroundColor: backgroundColor,
          appBarTheme: const AppBarTheme(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
            elevation: 0,
            centerTitle: true,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          cardTheme: CardThemeData(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            filled: true,
            fillColor: surfaceColor,
          ),
          floatingActionButtonTheme: const FloatingActionButtonThemeData(
            backgroundColor: primaryColor,
            foregroundColor: Colors.white,
          ),
          snackBarTheme: SnackBarThemeData(
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          visualDensity: VisualDensity.adaptivePlatformDensity,
        ),
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case '/login':
              return MaterialPageRoute(builder: (_) => const LoginPage());
            case '/signup':
              return MaterialPageRoute(builder: (_) => const SignupPage());
            case '/artisan_dashboard':
              return MaterialPageRoute(
                builder: (_) => const ArtisanDashboardScreen(),
              );
            case '/user_home':
              return MaterialPageRoute(builder: (_) => const HomePage());
            case '/admin_dashboard':
              return MaterialPageRoute(builder: (_) => const AdminDashboard());
            case '/profile':
              return MaterialPageRoute(builder: (_) => const ProfileScreen());
            case '/conversations':
              return MaterialPageRoute(builder: (_) => const ConversationsScreen());
            case '/account_settings':
              return MaterialPageRoute(builder: (_) => const AccountSettingsScreen());
            case '/booking_history':
              return MaterialPageRoute(builder: (_) => const BookingHistoryScreen());
            case '/manage_services':
              return MaterialPageRoute(builder: (_) => const EditArtisanProfileScreen());
            case '/escrow':
              final args = settings.arguments as Map<String, dynamic>?;
              return MaterialPageRoute(
                builder: (_) => EscrowPaymentScreen(
                  jobId: (args?['jobId'] as int?) ?? 0,
                  agreedPrice: (args?['agreedPrice'] as num?)?.toDouble() ?? 0.0,
                ),
              );
            case '/wallet':
              return MaterialPageRoute(builder: (_) => const WalletScreen());
            case '/disputes':
              final args = settings.arguments as Map<String, dynamic>?;
              return MaterialPageRoute(
                builder: (_) => DisputeScreen(jobId: args?['jobId'] as int?),
              );
            case '/admin_disputes':
              return MaterialPageRoute(builder: (_) => const AdminDisputeScreen());
            case '/admin_escrow':
              return MaterialPageRoute(builder: (_) => const AdminEscrowScreen());
            case '/admin_customers':
              return MaterialPageRoute(builder: (_) => const AdminCustomersScreen());
            case '/admin_chat':
              return MaterialPageRoute(builder: (_) => const AdminChatScreen());
            case '/artisan_map':
              final args = settings.arguments as Map<String, dynamic>?;
              if (args != null && args['artisan'] != null) {
                final artisan = args['artisan'] as Artisan;
                final userLoc = args['userLocation'] as Map<String, dynamic>?;
                LatLng? userLatLng;
                if (userLoc != null) {
                  userLatLng = LatLng(userLoc['latitude'] as double, userLoc['longitude'] as double);
                }
                return MaterialPageRoute(
                  builder: (_) => ArtisanMapScreen(artisan: artisan, userLocation: userLatLng),
                );
              }
              return MaterialPageRoute(builder: (_) => const SplashScreen());
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
      ),
    );
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: MyApp.backgroundColor,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}