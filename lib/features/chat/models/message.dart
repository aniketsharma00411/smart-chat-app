// import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart'; 

class Message {
  final String id;
  final String text;
  final String senderId;
  final DateTime timestamp;
  final Map<String, dynamic>? tone; 
  final Map<String, dynamic>? translation; 
  final String? originalLanguage;

  Message({
    required this.id,
    required this.text,
    required this.senderId,
    required this.timestamp,
    this.tone,
    this.translation,
    this.originalLanguage,
  });

  factory Message.fromMap(Map<String, dynamic> map, String id) {
    return Message(
      id: id,
      text: map['text'] ?? '',
      senderId: map['senderId'] ?? '',
      // Handle Timestamp or DateTime
      timestamp: (map['timestamp'] is DateTime) 
          ? map['timestamp'] 
          : (map['timestamp'] != null && map['timestamp'].runtimeType.toString().contains('Timestamp')) 
              ? (map['timestamp'] as dynamic).toDate() 
              : DateTime.now(),
      tone: map['tone'],
      translation: map['translation'],
      originalLanguage: map['originalLanguage'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'text': text,
      'senderId': senderId,
      'timestamp': timestamp, // Mock service will handle this
      'tone': tone,
      'translation': translation,
      'originalLanguage': originalLanguage,
    };
  }
}
