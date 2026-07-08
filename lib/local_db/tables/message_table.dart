import 'package:drift/drift.dart';

/// Mirrors Message.toMap()/fromMap() (lib/models/message_model.dart) field
/// for field. `sentAt` is stored as epoch millis for indexed sort/pagination
/// (Firestore itself stores it as an ISO string, not a native Timestamp —
/// see firestore_service.dart's sendMessage()). `updatedAt` and
/// `deliveryStatus` are local bookkeeping columns with no equivalent on the
/// Message model, the same way the backup pipeline already treats
/// `updatedAt` as sync metadata rather than app-visible data.
///
/// @DataClassName renames the generated row class to MessageRow — Drift's
/// default (singularizing "Messages" to "Message") would collide with the
/// app's own Message model in message_model.dart.
@DataClassName('MessageRow')
class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get senderId => text()();
  TextColumn get textContent => text().named('text')();
  TextColumn get type => text()();
  TextColumn get imageUrl => text().nullable()();
  TextColumn get audioUrl => text().nullable()();
  IntColumn get duration => integer().nullable()();
  IntColumn get sentAt => integer()();
  TextColumn get readBy => text().withDefault(const Constant('[]'))();
  TextColumn get readTimes => text().nullable()();
  TextColumn get replyToId => text().nullable()();
  TextColumn get replyToText => text().nullable()();
  TextColumn get reactions => text().nullable()();

  /// Sync cursor — epoch millis mirror of Firestore's updatedAt Timestamp.
  IntColumn get updatedAt => integer()();

  /// 'pending' | 'sent' | 'delivered' — see AGENTS.md's message delivery
  /// status design. Not part of the Message model; purely local UI state
  /// for the sender's own outgoing-message receipt icon.
  TextColumn get deliveryStatus =>
      text().withDefault(const Constant('sent'))();

  @override
  Set<Column> get primaryKey => {id};
}
