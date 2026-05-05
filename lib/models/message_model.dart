enum MessageType { text, image, poke }

class Message {
  final String id;
  final String senderId;
  final String text;
  final MessageType type;
  final String? imageUrl;
  final DateTime sentAt;
  final List<String> readBy;
  final Map<String, DateTime> readTimes;
  final String? replyToId;
  final String? replyToText;
  final Map<String, List<String>> reactions; // emoji → [uids]

  const Message({
    required this.id,
    required this.senderId,
    required this.text,
    required this.type,
    this.imageUrl,
    required this.sentAt,
    this.readBy = const [],
    this.readTimes = const {},
    this.replyToId,
    this.replyToText,
    this.reactions = const {},
  });

  factory Message.fromMap(String id, Map<String, dynamic> map) {
    final rawReactions = map['reactions'] as Map<String, dynamic>? ?? {};
    final reactions = rawReactions.map(
      (k, v) => MapEntry(k, List<String>.from(v as List)),
    );
    
    final rawReadTimes = map['readTimes'] as Map<String, dynamic>? ?? {};
    final readTimes = rawReadTimes.map(
      (k, v) => MapEntry(k, DateTime.parse(v as String)),
    );

    return Message(
      id: id,
      senderId: map['senderId'] as String,
      text: map['text'] as String? ?? '',
      type: MessageType.values.byName(map['type'] as String? ?? 'text'),
      imageUrl: map['imageUrl'] as String?,
      sentAt: DateTime.parse(map['sentAt'] as String),
      readBy: List<String>.from(map['readBy'] as List? ?? []),
      readTimes: readTimes,
      replyToId: map['replyToId'] as String?,
      replyToText: map['replyToText'] as String?,
      reactions: reactions,
    );
  }

  Map<String, dynamic> toMap() => {
        'senderId': senderId,
        'text': text,
        'type': type.name,
        'imageUrl': imageUrl,
        'sentAt': sentAt.toIso8601String(),
        'readBy': readBy,
        if (readTimes.isNotEmpty)
          'readTimes': readTimes.map((k, v) => MapEntry(k, v.toIso8601String())),
        if (replyToId != null) 'replyToId': replyToId,
        if (replyToText != null) 'replyToText': replyToText,
        if (reactions.isNotEmpty) 'reactions': reactions,
      };
}
