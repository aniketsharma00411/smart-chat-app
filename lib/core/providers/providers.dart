import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../services/api_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

final firestoreServiceProvider = Provider<FirestoreService>((ref) => FirestoreService());

final apiServiceProvider = Provider<ApiService>((ref) => ApiService());

final currentUserProvider = StreamProvider((ref) => ref.watch(authServiceProvider).authStateChanges);
