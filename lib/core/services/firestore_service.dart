import 'package:cloud_firestore/cloud_firestore.dart';
import '../../features/chat/models/message.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Stream Messages in a Chat
  Stream<List<Message>> getMessages(String chatId) {
    return _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        return Message.fromMap(doc.data(), doc.id);
      }).toList();
    });
  }

  // Send a Message
  Future<void> sendMessage(String chatId, Message message) async {
    final messageData = message.toMap();
    // Use server timestamp for consistency
    messageData['timestamp'] = FieldValue.serverTimestamp();

    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add(messageData);
        
    // Update last message in chat document
    await _firestore.collection('chats').doc(chatId).update({
      'lastMessage': message.text,
      'lastTimestamp': FieldValue.serverTimestamp(),
    });
  }
  
  // Search user by Share ID (Legacy, but kept for compatibility if needed)
  Future<Map<String, dynamic>?> searchUserByShareId(String shareId) async {
    final snapshot = await _firestore
        .collection('users')
        .where('shareId', isEqualTo: shareId)
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      return snapshot.docs.first.data();
    }
    return null;
  }
  
  // Search user by Email
  Future<Map<String, dynamic>?> searchUserByEmail(String email) async {
    final snapshot = await _firestore
        .collection('users')
        .where('email', isEqualTo: email)
        .limit(1)
        .get();

    if (snapshot.docs.isNotEmpty) {
      return snapshot.docs.first.data();
    }
    return null;
  }
  
  // Add Contact
  Future<void> addContact(String currentUserId, Map<String, dynamic> contactUser) async {
    await _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('contacts')
        .doc(contactUser['uid'])
        .set({
      'uid': contactUser['uid'],
      'email': contactUser['email'],
      'displayName': contactUser['displayName'],
      'photoURL': contactUser['photoURL'],
      'addedAt': FieldValue.serverTimestamp(),
    });
  }


  
  // Get Contacts Stream
  Stream<List<Map<String, dynamic>>> getContacts(String currentUserId) {
    return _firestore
        .collection('users')
        .doc(currentUserId)
        .collection('contacts')
        .orderBy('addedAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => doc.data()).toList();
    });
  }
  
  // Get Chats for User
  Stream<List<Map<String, dynamic>>> getChats(String uid) {
    return _firestore
        .collection('chats')
        .where('participants', arrayContains: uid)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => {...doc.data(), 'id': doc.id}).toList());
  }

  // Get Single Chat
  Future<Map<String, dynamic>?> getChat(String chatId) async {
    final doc = await _firestore.collection('chats').doc(chatId).get();
    return doc.data();
  }

  // Create or Get Chat
  Future<String> createChat(String currentUserId, String otherUserId) async {
    // Generate a consistent Chat ID based on UIDs
    List<String> ids = [currentUserId, otherUserId];
    ids.sort();
    String chatId = ids.join('_');
    
    final chatDoc = _firestore.collection('chats').doc(chatId);
    final snapshot = await chatDoc.get();
    
    if (!snapshot.exists) {
      await chatDoc.set({
        'participants': ids,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessage': '',
        'lastTimestamp': FieldValue.serverTimestamp(),
      });
    }
    
    return chatId;
  }
  
  // Get User Profile
  Future<Map<String, dynamic>?> getUser(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    return doc.data();
  }

  // Get User Profile Stream
  Stream<Map<String, dynamic>?> getUserStream(String uid) {
    return _firestore.collection('users').doc(uid).snapshots().map((snapshot) => snapshot.data());
  }

  // Update User Preferred Language
  Future<void> updateUserLanguage(String uid, String languageCode) async {
    await _firestore.collection('users').doc(uid).update({
      'preferredLanguage': languageCode,
    });
  }

  // Save Batch Translations
  Future<void> saveBatchTranslations(String chatId, List<Map<String, dynamic>> translations, String targetLanguage) async {
    final batch = _firestore.batch();
    
    for (var item in translations) {
      final messageId = item['id'];
      final translatedText = item['translated_text'];
      
      if (messageId != null && translatedText != null) {
        final docRef = _firestore
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .doc(messageId);
            
        batch.update(docRef, {
          'translations.$targetLanguage': translatedText
        });
      }
    }
    
    await batch.commit();
  }
  
  // --- CALL SIGNALING ---

  Future<String> createCall(String callerId, String receiverId) async {
    final callRef = _firestore.collection('calls').doc();
    await callRef.set({
      'id': callRef.id,
      'callerId': callerId,
      'receiverId': receiverId,
      'status': 'ringing', // ringing, accepted, rejected, ended
      'timestamp': FieldValue.serverTimestamp(),
      'type': 'audio',
    });
    return callRef.id;
  }

  Stream<List<Map<String, dynamic>>> streamIncomingCalls(String userId) {
    return _firestore
        .collection('calls')
        .where('receiverId', isEqualTo: userId)
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => doc.data()).toList());
  }

  Future<void> updateCallStatus(String callId, String status) async {
    await _firestore.collection('calls').doc(callId).update({
      'status': status,
    });
  }

  Future<void> endCall(String callId) async {
    await updateCallStatus(callId, 'ended');
  }

  Stream<Map<String, dynamic>?> streamCall(String callId) {
    return _firestore.collection('calls').doc(callId).snapshots().map((doc) => doc.data());
  }
}
