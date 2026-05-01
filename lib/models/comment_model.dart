class TodoComment {
  final String id;
  final String text;
  final String authorName;
  final DateTime createdAt;

  const TodoComment({
    required this.id,
    required this.text,
    required this.authorName,
    required this.createdAt,
  });

  factory TodoComment.fromMap(String id, Map<String, dynamic> map) {
    return TodoComment(
      id: id,
      text: map['text'] as String,
      authorName: map['authorName'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
        'text': text,
        'authorName': authorName,
        'createdAt': createdAt.toIso8601String(),
      };
}
