import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'firebase_options.dart';

import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'features/call/widgets/call_overlay.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint("🚀 Starting App initialization...");

  try {
    await dotenv.load(fileName: ".env");
    debugPrint("✅ Loaded .env file");
  } catch (e) {
    debugPrint("⚠️ No .env file found, using defaults: $e");
  }

  try {
    await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform);
    debugPrint("✅ Firebase initialized successfully");

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      debugPrint(
          "👤 User already logged in: ${user.email}. Checking profile...");
      final authService = AuthService();
      await authService.ensureUserDocument(user);
      debugPrint("✅ Profile verified.");
    }
  } catch (e) {
    debugPrint("❌ Firebase initialization failed: $e.");
  }

  debugPrint("🚀 Running App...");
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Vayu',
      theme: AppTheme.lightTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return CallOverlay(child: child!);
      },
    );
  }
}
