class ChecklistItem {
  final String id;
  final String title;
  final bool isDone;

  const ChecklistItem({
    required this.id,
    required this.title,
    required this.isDone,
  });

  factory ChecklistItem.fromMap(Map<String, dynamic> map) {
    return ChecklistItem(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      isDone: map['isDone'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'title': title,
        'isDone': isDone,
      };

  ChecklistItem copyWith({
    String? title,
    bool? isDone,
  }) =>
      ChecklistItem(
        id: id,
        title: title ?? this.title,
        isDone: isDone ?? this.isDone,
      );
}

class TodoItem {
  final String id;
  final String title;
  final String? details;
  final bool isDone;
  final String createdBy;
  final DateTime createdAt;
  final DateTime? dueDate;
  final String? assignedTo;
  final String? priority;
  final DateTime? completedAt;
  final List<ChecklistItem> checklist;

  const TodoItem({
    required this.id,
    required this.title,
    this.details,
    required this.isDone,
    required this.createdBy,
    required this.createdAt,
    this.dueDate,
    this.assignedTo,
    this.priority,
    this.completedAt,
    this.checklist = const [],
  });

  factory TodoItem.fromMap(String id, Map<String, dynamic> map) {
    return TodoItem(
      id: id,
      title: map['title'] as String,
      details: map['details'] as String?,
      isDone: map['isDone'] as bool? ?? false,
      createdBy: map['createdBy'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      dueDate: map['dueDate'] != null ? DateTime.parse(map['dueDate'] as String) : null,
      assignedTo: map['assignedTo'] as String?,
      priority: map['priority'] as String?,
      completedAt: map['completedAt'] != null ? DateTime.parse(map['completedAt'] as String) : null,
      checklist: (map['checklist'] as List? ?? [])
          .map((item) => ChecklistItem.fromMap(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }

  Map<String, dynamic> toMap() => {
        'title': title,
        'details': details,
        'isDone': isDone,
        'createdBy': createdBy,
        'createdAt': createdAt.toIso8601String(),
        if (dueDate != null) 'dueDate': dueDate!.toIso8601String(),
        if (assignedTo != null) 'assignedTo': assignedTo,
        if (priority != null) 'priority': priority,
        if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
        'checklist': checklist.map((item) => item.toMap()).toList(),
      };

  TodoItem copyWith({
    bool? isDone,
    String? details,
    DateTime? dueDate,
    String? assignedTo,
    String? priority,
    DateTime? completedAt,
    List<ChecklistItem>? checklist,
  }) =>
      TodoItem(
        id: id,
        title: title,
        details: details ?? this.details,
        isDone: isDone ?? this.isDone,
        createdBy: createdBy,
        createdAt: createdAt,
        dueDate: dueDate ?? this.dueDate,
        assignedTo: assignedTo ?? this.assignedTo,
        priority: priority ?? this.priority,
        completedAt: completedAt ?? this.completedAt,
        checklist: checklist ?? this.checklist,
      );
}
