// lib/main.dart
import 'package:artisans_app/auth/login_logic.dart';
import 'package:artisans_app/auth/signup_logic.dart';
import 'package:artisans_app/auth/forgot_password_screen.dart';
import 'package:artisans_app/auth/reset_password_screen.dart';
import 'package:artisans_app/screens/artisan_dashboard.dart';
import 'package:artisans_app/screens/user_home_screen.dart';
import 'package:artisans_app/screens/home_screen.dart';
import 'package:artisans_app/screens/admin_dashboard.dart';
import 'package:artisans_app/screens/artisan_profile.dart';
import 'package:artisans_app/screens/conversations_screen.dart';
import 'package:artisans_app/screens/account_settings_screen.dart';
import 'package:artisans_app/screens/booking_history_screen.dart';
import 'package:artisans_app/screens/edit_artisan_profile_screen.dart';
import 'package:artisans_app/screens/dispute_screen.dart';
import 'package:artisans_app/screens/admin_dispute_screen.dart';
import 'package:artisans_app/screens/admin_customers_screen.dart';
import 'package:artisans_app/screens/admin_chat_screen.dart';
import 'package:artisans_app/screens/artisan_map_screen.dart';
import 'package:artisans_app/screens/notification_screen.dart';
import 'package:artisans_app/screens/verification_documents_screen.dart';
import 'package:artisans_app/screens/plans_screen.dart';
import 'package:artisans_app/models/artisan.dart';
import 'package:artisans_app/theme/app_colors.dart';
import 'package:artisans_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:provider/provider.dart';
import 'package:artisans_app/viewmodels/auth_view_model.dart';
import 'package:artisans_app/viewmodels/profile_view_model.dart';
import 'package:artisans_app/viewmodels/chat_view_model.dart';
import 'package:artisans_app/viewmodels/admin_view_model.dart';
import 'package:artisans_app/models/user.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Single shared AuthViewModel instance used by both Provider and initial routing
  static final AuthViewModel _authViewModel = AuthViewModel();
  bool _initialAuthCheckComplete = false;

  @override
  void initState() {
    super.initState();
    // Listen for auth state changes — redirect to login when user signs out
    // or session expires (currentUser becomes null while app is running)
    _authViewModel.addListener(_onAuthChanged);
  }

  @override
  void dispose() {
    _authViewModel.removeListener(_onAuthChanged);
    super.dispose();
  }

  void _onAuthChanged() {
    // Don't redirect during initial auth check — only react to sign-out/expiry
    // after the app has finished its startup routing
    if (!_initialAuthCheckComplete) return;
    if (_authViewModel.currentUser == null && _authViewModel.state == AuthState.idle) {
      // User signed out or session expired — navigate to login
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
      }
    }
  }

  // GlobalKey for accessing the navigator from the listener
  static final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthViewModel>.value(value: _authViewModel),
        ChangeNotifierProvider(create: (_) => ProfileViewModel()),
        ChangeNotifierProvider(create: (_) => ChatViewModel()),
        ChangeNotifierProvider(create: (_) => AdminViewModel()),
      ],
      child: MaterialApp(
        navigatorKey: navigatorKey,
        title: 'FixIt App',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme(),
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
            case '/home':
              return MaterialPageRoute(builder: (_) => const HomeScreen());
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
            case '/disputes':
              final args = settings.arguments as Map<String, dynamic>?;
              return MaterialPageRoute(
                builder: (_) => DisputeScreen(jobId: args?['jobId'] as int?),
              );
            case '/admin_disputes':
              return MaterialPageRoute(builder: (_) => const AdminDisputeScreen());
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
            case '/forgot_password':
              return MaterialPageRoute(builder: (_) => const ForgotPasswordScreen());
            case '/reset_password':
              final args = settings.arguments as Map<String, dynamic>?;
              final email = args?['email'] as String? ?? '';
              return MaterialPageRoute(
                builder: (_) => ResetPasswordScreen(email: email),
              );
            case '/notifications':
              return MaterialPageRoute(builder: (_) => const NotificationScreen());
            case '/plans':
              return MaterialPageRoute(builder: (_) => const PlansScreen());
            case '/verification_documents':
              return MaterialPageRoute(builder: (_) => const VerificationDocumentsScreen());
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

  /// Uses the shared AuthViewModel so Provider state is consistent from startup
  /// Routes directly to the role-appropriate screen, skipping the persona picker.
  Future<Widget> _getInitialScreen() async {
    final isAuth = await _authViewModel.checkAuth();
    // Mark initial auth check as complete so the listener can start reacting
    _initialAuthCheckComplete = true;
    if (isAuth && _authViewModel.currentUser != null) {
      final role = _authViewModel.currentUser!.role;
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
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.background,
      body: Center(child: CircularProgressIndicator()),
    );
  }
}