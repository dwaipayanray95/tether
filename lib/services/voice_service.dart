import 'dart:io';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:cryptography/cryptography.dart';
import 'package:record/record.dart';
import 'crypto_service.dart';
import 'log_service.dart';

class VoiceService {
  static final VoiceService _instance = VoiceService._internal();
  factory VoiceService() => _instance;
  VoiceService._internal();

  AudioRecorder? _recorder;
  bool _isRecorderInitialized = false;

  Future<void> initRecorder() async {
    if (_isRecorderInitialized) return;
    _recorder = AudioRecorder();
    _isRecorderInitialized = true;
  }

  Future<void> startRecording(String path) async {
    await initRecorder();
    LogService.log('Starting audio recording via record package to path: $path');
    
    final hasPermission = await _recorder!.hasPermission();
    if (!hasPermission) {
      throw StateError('Microphone permission not granted');
    }

    await _recorder!.start(
      const RecordConfig(
        encoder: AudioEncoder.opus,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: path,
    );
  }

  Future<String?> stopRecording() async {
    if (!_isRecorderInitialized || _recorder == null) return null;
    LogService.log('Stopping audio recording');
    final path = await _recorder!.stop();
    return path;
  }

  Future<void> disposeRecorder() async {
    if (_recorder != null) {
      await _recorder!.dispose();
      _recorder = null;
      _isRecorderInitialized = false;
    }
  }

  /// Encrypts local audio file and returns a JSON string of the encrypted payload
  Future<String?> encryptVoice(String localPath, SecretKey sharedKey) async {
    try {
      LogService.log('E2EE Voice: Encrypting audio file');
      final file = File(localPath);
      final bytes = await file.readAsBytes();

      // Encrypt voice file bytes
      final encryptedMap = await CryptoService().encryptBytes(bytes, sharedKey);
      return jsonEncode(encryptedMap);
    } catch (e) {
      LogService.log('E2EE Voice: Encryption failed: $e');
      return null;
    }
  }

  /// Decrypts JSON string payload and saves to a local temporary audio file
  Future<String?> decryptVoice(String encryptedJson, SecretKey sharedKey) async {
    try {
      LogService.log('E2EE Voice: Decrypting audio payload');
      final encryptedMap = jsonDecode(encryptedJson) as Map<String, dynamic>;
      final decryptedBytes = await CryptoService().decryptBytes(encryptedMap, sharedKey);

      final tempDir = await getTemporaryDirectory();
      final decryptedPath = '${tempDir.path}/decrypted_voice_${DateTime.now().microsecondsSinceEpoch}.ogg';
      final decryptedFile = File(decryptedPath);
      await decryptedFile.writeAsBytes(decryptedBytes);

      LogService.log('E2EE Voice: Saved decrypted audio to $decryptedPath');
      return decryptedPath;
    } catch (e) {
      LogService.log('E2EE Voice: Decryption failed: $e');
      return null;
    }
  }
}
