import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/api_service.dart';
import '../services/call_service_agora.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final agoraCallServiceProvider = Provider<AgoraCallService>((ref) => AgoraCallService());

final firestoreServiceProvider = Provider<FirestoreService>((ref) => FirestoreService());

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

final currentUserProvider = StreamProvider((ref) => ref.watch(authServiceProvider).authStateChanges);

final userProfileProvider = StreamProvider<Map<String, dynamic>?>((ref) {
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return Stream.value(null);
  return ref.watch(firestoreServiceProvider).getUserStream(user.uid);
});

final chatProvider = FutureProvider.family<Map<String, dynamic>?, String>((ref, chatId) {
  return ref.watch(firestoreServiceProvider).getChat(chatId);
});

final otherUserProvider = FutureProvider.family<Map<String, dynamic>?, String>((ref, userId) {
  return ref.watch(firestoreServiceProvider).getUser(userId);
});

final incomingCallsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return Stream.value([]);
  return ref.watch(firestoreServiceProvider).streamIncomingCalls(user.uid);
});

final currentCallStreamProvider = StreamProvider.family<Map<String, dynamic>?, String>((ref, callId) {
  return ref.watch(firestoreServiceProvider).streamCall(callId);
});
