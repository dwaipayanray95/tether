import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' show Random;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth_service.dart';
import 'log_service.dart';

class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  final _secureStorage = const FlutterSecureStorage();
  final _x25519 = X25519();
  final _aesGcm = AesGcm.with256bits();
  final _sha256 = Sha256();

  // Secure Storage keys
  static const _privateKeyStorageKey = 'tether_e2ee_private_key';
  static const _publicKeyStorageKey = 'tether_e2ee_public_key';

  // Cached in-memory shared secret key to avoid computing it on every message
  SecretKey? _cachedSharedKey;

  /// Generate X25519 keypair, save private key in Secure Storage, and return public key.
  Future<String> initializeKeys() async {
    try {
      final existingPubKey = await _secureStorage.read(key: _publicKeyStorageKey);
      final existingPrivKey = await _secureStorage.read(key: _privateKeyStorageKey);

      if (existingPubKey != null && existingPrivKey != null) {
        LogService.log('Crypto: Loaded existing X25519 keypair');
        return existingPubKey;
      }

      LogService.log('Crypto: Generating new X25519 keypair');
      final keyPair = await _x25519.newKeyPair();
      final privateKeyBytes = await keyPair.extractPrivateKeyBytes();
      final publicKey = await keyPair.extractPublicKey();

      final pubKeyBase64 = base64Encode(publicKey.bytes);
      final privKeyBase64 = base64Encode(privateKeyBytes);

      await _secureStorage.write(key: _publicKeyStorageKey, value: pubKeyBase64);
      await _secureStorage.write(key: _privateKeyStorageKey, value: privKeyBase64);

      return pubKeyBase64;
    } catch (e) {
      LogService.log('Crypto Error: Keypair generation failed: $e');
      rethrow;
    }
  }

  /// Manually set the keys (e.g. after restoring from Google Drive backup)
  Future<void> restoreKeys(String publicKeyBase64, String privateKeyBase64) async {
    await _secureStorage.write(key: _publicKeyStorageKey, value: publicKeyBase64);
    await _secureStorage.write(key: _privateKeyStorageKey, value: privateKeyBase64);
    _cachedSharedKey = null; // Reset cache
    LogService.log('Crypto: Restored keys into Secure Storage');
  }

  Future<String?> getPublicKey() async {
    return await _secureStorage.read(key: _publicKeyStorageKey);
  }

  Future<String?> getPrivateKey() async {
    return await _secureStorage.read(key: _privateKeyStorageKey);
  }

  /// Clean key cache and local keys (used for signout/reset)
  Future<void> clearKeys() async {
    await _secureStorage.delete(key: _publicKeyStorageKey);
    await _secureStorage.delete(key: _privateKeyStorageKey);
    _cachedSharedKey = null;
    LogService.log('Crypto: Cleared keys from Secure Storage');
  }

  /// Derive shared secret using My Private Key and Partner's Public Key.
  Future<SecretKey> getSharedKey(String partnerPublicKeyBase64) async {
    if (_cachedSharedKey != null) return _cachedSharedKey!;

    try {
      final myPrivKeyBase64 = await _secureStorage.read(key: _privateKeyStorageKey);
      if (myPrivKeyBase64 == null) {
        throw StateError('Crypto: Private key not found in storage. Initialize keys first.');
      }

      final myPrivKeyBytes = base64Decode(myPrivKeyBase64);
      final myPubKeyBase64 = await _secureStorage.read(key: _publicKeyStorageKey);
      if (myPubKeyBase64 == null) {
        throw StateError('Crypto: Public key not found in storage.');
      }

      // Reconstruct keypair
      final myKeyPair = SimpleKeyPairData(
        myPrivKeyBytes,
        publicKey: SimplePublicKey(base64Decode(myPubKeyBase64), type: KeyPairType.x25519),
        type: KeyPairType.x25519,
      );

      final partnerPublicKey = SimplePublicKey(
        base64Decode(partnerPublicKeyBase64),
        type: KeyPairType.x25519,
      );

      // Perform Diffie-Hellman
      final sharedSecret = await _x25519.sharedSecretKey(
        keyPair: myKeyPair,
        remotePublicKey: partnerPublicKey,
      );
      final sharedSecretBytes = await sharedSecret.extractBytes();

      // SHA-256 to get key
      final hash = await _sha256.hash(sharedSecretBytes);
      _cachedSharedKey = SecretKey(hash.bytes);
      
      LogService.log('Crypto: Derived shared secret key successfully');
      return _cachedSharedKey!;
    } catch (e) {
      LogService.log('Crypto Error: Shared key derivation failed: $e');
      rethrow;
    }
  }

  /// Encrypt a plain text string using the derived shared secret.
  Future<Map<String, String>> encryptText(String plainText, SecretKey sharedKey) async {
    final bytes = utf8.encode(plainText);
    final secretBox = await _aesGcm.encrypt(bytes, secretKey: sharedKey);

    return {
      'ciphertext': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(secretBox.nonce),
      'mac': base64Encode(secretBox.mac.bytes),
    };
  }

  /// Decrypt a cipher text string using the derived shared secret.
  Future<String> decryptText(Map<String, dynamic> encryptedData, SecretKey sharedKey) async {
    final cipherText = base64Decode(encryptedData['ciphertext'] as String);
    final nonce = base64Decode(encryptedData['nonce'] as String);
    final mac = Mac(base64Decode(encryptedData['mac'] as String));

    final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
    final decryptedBytes = await _aesGcm.decrypt(secretBox, secretKey: sharedKey);
    return utf8.decode(decryptedBytes);
  }

  /// Encrypt binary data (like raw snap photos).
  Future<Map<String, String>> encryptBytes(Uint8List plainBytes, SecretKey sharedKey) async {
    final secretBox = await _aesGcm.encrypt(plainBytes, secretKey: sharedKey);

    return {
      'ciphertext': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(secretBox.nonce),
      'mac': base64Encode(secretBox.mac.bytes),
    };
  }

  /// Decrypt binary data (like raw snap photos).
  Future<Uint8List> decryptBytes(Map<String, dynamic> encryptedData, SecretKey sharedKey) async {
    final cipherText = base64Decode(encryptedData['ciphertext'] as String);
    final nonce = base64Decode(encryptedData['nonce'] as String);
    final mac = Mac(base64Decode(encryptedData['mac'] as String));

    final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
    final decryptedBytes = await _aesGcm.decrypt(secretBox, secretKey: sharedKey);
    return Uint8List.fromList(decryptedBytes);
  }

  // ── PIN-Based Backup Cryptography ──────────────────────────────────────────

  /// Derive key from PIN using PBKDF2.
  Future<SecretKey> _deriveKeyFromPin(String pin, List<int> salt) async {
    final pbkdf2 = Pbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: 1000,
      bits: 256,
    );
    return await pbkdf2.deriveKeyFromPassword(
      password: pin,
      nonce: salt,
    );
  }

  /// Encrypt private key using user's PIN code.
  Future<Map<String, String>> encryptPrivateKey(String pin, String privateKeyBase64) async {
    final random = Random.secure();
    final salt = List<int>.generate(16, (i) => random.nextInt(256));
    final key = await _deriveKeyFromPin(pin, salt);
    final plainBytes = utf8.encode(privateKeyBase64);

    final secretBox = await _aesGcm.encrypt(plainBytes, secretKey: key);

    return {
      'ciphertext': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(secretBox.nonce),
      'mac': base64Encode(secretBox.mac.bytes),
      'salt': base64Encode(salt),
    };
  }

  /// Decrypt private key using user's PIN code.
  Future<String> decryptPrivateKey(String pin, Map<String, dynamic> backupData) async {
    final cipherText = base64Decode(backupData['ciphertext'] as String);
    final nonce = base64Decode(backupData['nonce'] as String);
    final mac = Mac(base64Decode(backupData['mac'] as String));
    final salt = base64Decode(backupData['salt'] as String);

    final key = await _deriveKeyFromPin(pin, salt);
    final secretBox = SecretBox(cipherText, nonce: nonce, mac: mac);
    final decryptedBytes = await _aesGcm.decrypt(secretBox, secretKey: key);

    return utf8.decode(decryptedBytes);
  }

  Future<String?> fetchPartnerPublicKey() async {
    try {
      final partnerKey = AuthService().partnerName.toLowerCase();
      final doc = await FirebaseFirestore.instance.doc('couples/ray-aproo/status/presence').get();
      final data = doc.data();
      if (data != null && data[partnerKey] != null) {
        return data[partnerKey]['publicKey'] as String?;
      }
    } catch (e) {
      LogService.log('Crypto Error: Failed to fetch partner public key: $e');
    }
    return null;
  }

  /// High-level utility to encrypt a string. Automatically handles key agreement.
  /// Falls back to plaintext if setup is incomplete or error occurs.
  Future<String> encryptString(String plainText) async {
    if (plainText.isEmpty) return plainText;
    try {
      final partnerPubKey = await fetchPartnerPublicKey();
      if (partnerPubKey == null) return plainText;

      final sharedKey = await getSharedKey(partnerPubKey);
      final encryptedMap = await encryptText(plainText, sharedKey);
      return jsonEncode(encryptedMap);
    } catch (e) {
      LogService.log('Crypto: High-level encrypt failed: $e');
      return plainText;
    }
  }

  /// High-level utility to decrypt a string. Automatically handles legacy formats and errors.
  Future<String> decryptString(String text) async {
    if (text.isEmpty || !text.startsWith('{"ciphertext":')) return text;
    try {
      final partnerPubKey = await fetchPartnerPublicKey();
      if (partnerPubKey == null) return text;

      final sharedKey = await getSharedKey(partnerPubKey);
      final encryptedData = jsonDecode(text) as Map<String, dynamic>;
      return await decryptText(encryptedData, sharedKey);
    } catch (e) {
      LogService.log('Crypto: High-level decrypt failed: $e');
      return text;
    }
  }
}
