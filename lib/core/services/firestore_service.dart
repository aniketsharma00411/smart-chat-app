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
  
  // Search user by Share ID
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
}
