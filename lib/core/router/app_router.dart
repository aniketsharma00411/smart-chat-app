import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vayu/core/services/auth_service.dart';
import 'package:vayu/features/splash/screens/splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/chat/screens/chat_list_screen.dart';
import '../../features/chat/screens/chat_detail_screen.dart';
import '../../features/call/screens/call_screen.dart';
import 'package:vayu/features/ai_assistant/screens/ai_chat_screen.dart';
import '../../features/settings/screens/settings_screen.dart';

final authProvider = StreamProvider((ref) => AuthService().authStateChanges);
final authAuthServiceProvider = Provider((ref) => AuthService());

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);
  final authService = ref.watch(authAuthServiceProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      debugPrint("🔄 Router Redirect Check: Location: ${state.uri}, AuthLoading: ${authState.isLoading}, HasValue: ${authState.asData?.value != null}");
      
      final isLoggedIn = authState.asData?.value != null;
      final isLoggingIn = state.uri.toString() == '/login';
      final isSplash = state.uri.toString() == '/';

      if (authState.isLoading) {
        debugPrint("⏳ Auth is loading, staying on Splash");
        return '/';
      }

      if (!isLoggedIn && !isLoggingIn) {
        debugPrint("🔒 Not logged in, redirecting to /login");
        return '/login';
      }

      if (isLoggedIn && (isLoggingIn || isSplash)) {
        debugPrint("✅ Logged in, redirecting to /chats");
        return '/chats';
      }

      debugPrint("➡ No redirect needed");
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const SplashScreen()),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/chats',
        builder: (context, state) => const ChatListScreen(),
        routes: [
          GoRoute(
            path: 'detail/:chatId',
            builder: (context, state) {
               final chatId = state.pathParameters['chatId']!;
               return ChatDetailScreen(chatId: chatId);
            },
          ),
        ],
      ),
      GoRoute(
        path: '/chat/:id',
        builder: (context, state) => ChatDetailScreen(chatId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/ai-chat',
        builder: (context, state) {
           final prompt = state.extra as String? ?? '';
           return AIChatScreen(initialPrompt: prompt);
        },
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsScreen(),
      ),
      GoRoute(
        path: '/call/:callId',
        builder: (context, state) => CallScreen(callId: state.pathParameters['callId']!),
      ),
    ],
  );
});
