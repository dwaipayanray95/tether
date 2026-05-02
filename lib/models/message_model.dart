enum MessageType { text, image, poke }

class Message {
  final String id;
  final String senderId;
  final String text;
  final MessageType type;
  final String? imageUrl;
  final DateTime sentAt;
  final List<String> readBy; // list of UIDs who have read this message

  const Message({
    required this.id,
    required this.senderId,
    required this.text,
    required this.type,
    this.imageUrl,
    required this.sentAt,
    this.readBy = const [],
  });

  factory Message.fromMap(String id, Map<String, dynamic> map) {
    return Message(
      id: id,
      senderId: map['senderId'] as String,
      text: map['text'] as String? ?? '',
      type: MessageType.values.byName(map['type'] as String? ?? 'text'),
      imageUrl: map['imageUrl'] as String?,
      sentAt: DateTime.parse(map['sentAt'] as String),
      readBy: List<String>.from(map['readBy'] as List? ?? []),
    );
  }

  Map<String, dynamic> toMap() => {
        'senderId': senderId,
        'text': text,
        'type': type.name,
        'imageUrl': imageUrl,
        'sentAt': sentAt.toIso8601String(),
        'readBy': readBy,
      };
}
