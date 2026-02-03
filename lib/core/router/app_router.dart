import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_chat_app/core/services/auth_service.dart';
import 'package:smart_chat_app/features/splash/screens/splash_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/chat/screens/chat_list_screen.dart';
import '../../features/chat/screens/chat_detail_screen.dart';
import '../../features/call/screens/call_screen.dart';
import 'package:smart_chat_app/features/ai_assistant/screens/ai_chat_screen.dart';

final authProvider = StreamProvider((ref) => AuthService().authStateChanges);
final authAuthServiceProvider = Provider((ref) => AuthService());

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);
  final authService = ref.watch(authAuthServiceProvider);

  return GoRouter(
    initialLocation: '/',
    redirect: (context, state) {
      // Temp disable auth guard for UI demo
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
        path: '/call',
        builder: (context, state) => const CallScreen(),
      ),
    ],
  );
});
