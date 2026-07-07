/// The decrypted content of a Drive backup file: a full-state export of
/// everything the backup pipeline covers (todos, comments, messages,
/// sticky notes, both partners' profiles, the couple doc, and this
/// device's allowlisted app preferences). This is an archival structure,
/// not a live app model — fields are kept as loosely typed maps rather
/// than the app's normal typed models, since the content may include docs
/// whose shape has evolved across app versions.
class BackupSnapshot {
  final int version;
  final DateTime generatedAt;
  final List<Map<String, dynamic>> todos;
  final List<Map<String, dynamic>> comments; // each carries a 'todoId' key
  final List<Map<String, dynamic>> messages;
  final List<Map<String, dynamic>> stickyNotes;
  final Map<String, dynamic> profiles; // uid -> user doc
  final Map<String, dynamic>? coupleDoc;
  // App preferences (see BackupConfig.backedUpPreferenceKeys) — always the
  // full current set on each run, not a delta, since it's small local
  // key-value state rather than a growing Firestore collection.
  final Map<String, dynamic> preferences;

  const BackupSnapshot({
    required this.version,
    required this.generatedAt,
    this.todos = const [],
    this.comments = const [],
    this.messages = const [],
    this.stickyNotes = const [],
    this.profiles = const {},
    this.coupleDoc,
    this.preferences = const {},
  });

  factory BackupSnapshot.empty() =>
      BackupSnapshot(version: 1, generatedAt: DateTime.now());

  factory BackupSnapshot.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> asList(String key) =>
        ((json[key] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();

    return BackupSnapshot(
      version: json['version'] as int? ?? 1,
      generatedAt: DateTime.parse(json['generatedAt'] as String),
      todos: asList('todos'),
      comments: asList('comments'),
      messages: asList('messages'),
      stickyNotes: asList('stickyNotes'),
      profiles: Map<String, dynamic>.from(json['profiles'] as Map? ?? {}),
      coupleDoc: json['coupleDoc'] != null
          ? Map<String, dynamic>.from(json['coupleDoc'] as Map)
          : null,
      preferences: Map<String, dynamic>.from(json['preferences'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toJson() => {
        'version': version,
        'generatedAt': generatedAt.toIso8601String(),
        'todos': todos,
        'comments': comments,
        'messages': messages,
        'stickyNotes': stickyNotes,
        'profiles': profiles,
        'coupleDoc': coupleDoc,
        'preferences': preferences,
      };

  BackupSnapshot copyWith({
    DateTime? generatedAt,
    List<Map<String, dynamic>>? todos,
    List<Map<String, dynamic>>? comments,
    List<Map<String, dynamic>>? messages,
    List<Map<String, dynamic>>? stickyNotes,
    Map<String, dynamic>? profiles,
    Map<String, dynamic>? coupleDoc,
    Map<String, dynamic>? preferences,
  }) =>
      BackupSnapshot(
        version: version,
        generatedAt: generatedAt ?? this.generatedAt,
        todos: todos ?? this.todos,
        comments: comments ?? this.comments,
        messages: messages ?? this.messages,
        stickyNotes: stickyNotes ?? this.stickyNotes,
        profiles: profiles ?? this.profiles,
        coupleDoc: coupleDoc ?? this.coupleDoc,
        preferences: preferences ?? this.preferences,
      );
}
