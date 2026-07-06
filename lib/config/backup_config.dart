/// Drive file naming for the full-state backup pipeline.
///
/// Rotation contract: each successful backup run promotes its merged
/// result to [latestBackupFileName]. Before promoting, whatever was
/// previously at that name is renamed one generation back
/// ([backupGenerationFileName] for gen 1, 2, 3). Once a 4th generation
/// would be created, the oldest one ([maxBackupGenerations]) is deleted
/// instead of rotated further — so at most [maxBackupGenerations] + 1
/// snapshots (the current one plus that many prior generations) ever
/// exist on Drive at once.
class BackupConfig {
  static const String folderName = 'Tether';
  static const String latestBackupFileName = 'latest_backup.json.enc';
  static const String pendingBackupFileName = 'latest_backup.new.json.enc';
  static const int maxBackupGenerations = 3;

  static String backupGenerationFileName(int generation) =>
      'backup_gen$generation.json.enc';
}
