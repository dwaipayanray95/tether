class TodoItem {
  final String id;
  final String title;
  final bool isDone;
  final String createdBy;
  final DateTime createdAt;

  const TodoItem({
    required this.id,
    required this.title,
    required this.isDone,
    required this.createdBy,
    required this.createdAt,
  });

  factory TodoItem.fromMap(String id, Map<String, dynamic> map) {
    return TodoItem(
      id: id,
      title: map['title'] as String,
      isDone: map['isDone'] as bool? ?? false,
      createdBy: map['createdBy'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'isDone': isDone,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
      };

  TodoItem copyWith({bool? isDone}) => TodoItem(
        id: id,
        title: title,
        isDone: isDone ?? this.isDone,
        createdBy: createdBy,
        createdAt: createdAt,
      );
}
