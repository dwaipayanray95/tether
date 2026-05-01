class TetherUser {
  final String uid;
  final String name;
  final String email;
  final String? photoUrl;
  final String? partnerId;
  final DateTime? togetherSince;

  const TetherUser({
    required this.uid,
    required this.name,
    required this.email,
    this.photoUrl,
    this.partnerId,
    this.togetherSince,
  });

  factory TetherUser.fromMap(Map<String, dynamic> map) {
    return TetherUser(
      uid: map['uid'] as String,
      name: map['name'] as String,
      email: map['email'] as String,
      photoUrl: map['photoUrl'] as String?,
      partnerId: map['partnerId'] as String?,
      togetherSince: map['togetherSince'] != null
          ? DateTime.parse(map['togetherSince'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'name': name,
        'email': email,
        'photoUrl': photoUrl,
        'partnerId': partnerId,
        'togetherSince': togetherSince?.toIso8601String(),
      };
}
