class TodoItem {
  final String id;
  final String title;
  final String? details;
  final bool isDone;
  final String createdBy;
  final DateTime createdAt;

  const TodoItem({
    required this.id,
    required this.title,
    this.details,
    required this.isDone,
    required this.createdBy,
    required this.createdAt,
  });

  factory TodoItem.fromMap(String id, Map<String, dynamic> map) {
    return TodoItem(
      id: id,
      title: map['title'] as String,
      details: map['details'] as String?,
      isDone: map['isDone'] as bool? ?? false,
      createdBy: map['createdBy'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'details': details,
        'isDone': isDone,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
      };

  TodoItem copyWith({bool? isDone, String? details}) => TodoItem(
        id: id,
        title: title,
        details: details ?? this.details,
        isDone: isDone ?? this.isDone,
        createdBy: createdBy,
        createdAt: createdAt,
      );
}
