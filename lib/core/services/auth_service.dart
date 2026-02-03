import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:math';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Stream of auth changes
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // Get current user
  User? get currentUser => _auth.currentUser;

  // Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      if (kIsWeb) {
        GoogleAuthProvider authProvider = GoogleAuthProvider();
        return await _auth.signInWithPopup(authProvider);
      } else {
        final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
        if (googleUser == null) return null; // User canceled

        final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
        final AuthCredential credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        final UserCredential userCredential = await _auth.signInWithCredential(credential);
        await ensureUserDocument(userCredential.user);
        return userCredential;
      }
    } catch (e) {
      debugPrint("Error signing in with Google: $e");
      return null;
    }
  }

  // Save user data to Firestore if new
  Future<void> ensureUserDocument(User? user) async {
    if (user == null) {
      debugPrint("ensureUserDocument: User is null");
      return;
    }
    
    debugPrint("ensureUserDocument: Starting for user ${user.uid}");

    try {
      final userDoc = _firestore.collection('users').doc(user.uid);
      final snapshot = await userDoc.get();
      debugPrint("ensureUserDocument: Snapshot exists? ${snapshot.exists}");

      if (!snapshot.exists) {
        // New user
        debugPrint("ensureUserDocument: Creating new user document");
        String shareId = _generateShareId();
        await userDoc.set({
          'uid': user.uid,
          'email': user.email,
          'displayName': user.displayName,
          'photoURL': user.photoURL,
          'shareId': shareId,
          'createdAt': FieldValue.serverTimestamp(),
        });
        debugPrint("ensureUserDocument: User document created successfully");
      } else {
        // Existing user: Check if shareId is missing (e.g. created before migration)
        final data = snapshot.data();
        if (data != null && !data.containsKey('shareId')) {
          debugPrint("ensureUserDocument: Updating existing user with shareId");
          String shareId = _generateShareId();
          await userDoc.update({'shareId': shareId});
        } else {
          debugPrint("ensureUserDocument: User already exists and has shareId");
        }
      }
    } catch (e) {
      debugPrint("ensureUserDocument ERROR: $e");
      rethrow; // Re-throw to be caught by signInWithGoogle
    }
  }

  String _generateShareId() {
    var r = Random();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(6, (index) => chars[r.nextInt(chars.length)]).join();
  }

  // Sign out
  Future<void> signOut() async {
    try {
      if (!kIsWeb) {
        await _googleSignIn.signOut();
      }
      await _auth.signOut();
    } catch (e) {
      debugPrint("Error signing out: $e");
    }
  }
}
