import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'core/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'firebase_options.dart'; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  try {
    // If you have generated firebase_options.dart, uncomment the import and the options argument below
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    
    // Fallback logic was here, but we now have options
  } catch (e) {
    debugPrint("Firebase initialization failed: $e. Ensure you have configured Firebase.");
  }
  
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    
    return MaterialApp.router(
      title: 'Smart Chat',
      theme: AppTheme.lightTheme,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
    );
  }
}
