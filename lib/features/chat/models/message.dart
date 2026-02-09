import 'package:cloud_firestore/cloud_firestore.dart';

class Message {
  final String id;
  final String text;
  final String senderId;
  final DateTime timestamp;
  final Map<String, dynamic>? tone; 
  final Map<String, dynamic>? translation; 
  final Map<String, dynamic>? translations; // {'es': 'Hola', 'fr': 'Bonjour'}
  final String? originalLanguage;

  Message({
    required this.id,
    required this.text,
    required this.senderId,
    required this.timestamp,
    this.tone,
    this.translation,
    this.originalLanguage,
    this.translations,
  });

  factory Message.fromMap(Map<String, dynamic> map, String id) {
    // Handle timestamp properly for both web and mobile
    DateTime parsedTimestamp;
    final timestampValue = map['timestamp'];
    
    if (timestampValue == null) {
      parsedTimestamp = DateTime.now();
    } else if (timestampValue is DateTime) {
      parsedTimestamp = timestampValue;
    } else if (timestampValue is Timestamp) {
      parsedTimestamp = timestampValue.toDate();
    } else {
      // For web builds, check if object has toDate method (duck typing)
      try {
        if (timestampValue is Map && timestampValue.containsKey('seconds') && timestampValue.containsKey('nanoseconds')) {
          // Raw Firebase timestamp object (web)
          final seconds = timestampValue['seconds'] as int;
          final nanoseconds = (timestampValue['nanoseconds'] as int?) ?? 0;
          parsedTimestamp = DateTime.fromMillisecondsSinceEpoch(seconds * 1000 + nanoseconds ~/ 1000000);
        } else if (timestampValue.toString().contains('Timestamp')) {
          // Has toDate method but type check failed
          parsedTimestamp = (timestampValue as dynamic).toDate();
        } else {
          throw Exception('Unknown timestamp format');
        }
      } catch (e) {
        print('❌ Message $id: Failed to parse timestamp: $e, value: $timestampValue, type: ${timestampValue.runtimeType}');
        parsedTimestamp = DateTime.now();
      }
    }
    
    return Message(
      id: id,
      text: map['text'] ?? '',
      senderId: map['senderId'] ?? '',
      timestamp: parsedTimestamp,
      tone: map['tone'],
      translation: map['translation'],
      originalLanguage: map['originalLanguage'],
      translations: map['translations'],
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
      'translations': translations,
    };
  }
}
