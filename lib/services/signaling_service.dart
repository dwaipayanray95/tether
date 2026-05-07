import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../config/webrtc_config.dart';
import 'log_service.dart';

class SignalingService {
  IO.Socket? _socket;
  final String userId;

  Function(Map<String, dynamic>)? onOffer;
  Function(Map<String, dynamic>)? onAnswer;
  Function(Map<String, dynamic>)? onIceCandidate;
  Function(String)? onUserJoined;
  Function(String)? onUserLeft;

  SignalingService({required this.userId});

  void connect() {
    LogService.log('Connecting to Signaling Server: ${WebRTCConfig.signalingServerUrl}');
    
    _socket = IO.io(WebRTCConfig.signalingServerUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
    });

    _socket?.connect();

    _socket?.onConnect((_) {
      LogService.log('Connected to Signaling Server');
      _socket?.emit('register', {'userId': userId});
    });

    _socket?.on('offer', (data) {
      LogService.log('Received Offer from ${data['from']}');
      onOffer?.call(data);
    });

    _socket?.on('answer', (data) {
      LogService.log('Received Answer from ${data['from']}');
      onAnswer?.call(data);
    });

    _socket?.on('ice-candidate', (data) {
      LogService.log('Received ICE Candidate from ${data['from']}');
      onIceCandidate?.call(data);
    });

    _socket?.on('user-joined', (data) {
      onUserJoined?.call(data['userId']);
    });

    _socket?.on('user-left', (data) {
      onUserLeft?.call(data['userId']);
    });

    _socket?.onDisconnect((_) {
      LogService.log('Disconnected from Signaling Server');
    });

    _socket?.onConnectError((err) {
      LogService.log('Signaling Connection Error: $err');
    });
  }

  void sendOffer(String to, Map<String, dynamic> sdp) {
    _socket?.emit('offer', {
      'to': to,
      'from': userId,
      'sdp': sdp,
    });
  }

  void sendAnswer(String to, Map<String, dynamic> sdp) {
    _socket?.emit('answer', {
      'to': to,
      'from': userId,
      'sdp': sdp,
    });
  }

  void sendIceCandidate(String to, Map<String, dynamic> candidate) {
    _socket?.emit('ice-candidate', {
      'to': to,
      'from': userId,
      'candidate': candidate,
    });
  }

  void sendCallPing(String to, String callerName) {
    _socket?.emit('call-ping', {
      'to': to,
      'from': userId,
      'callerName': callerName,
    });
  }

  void dispose() {
    _socket?.disconnect();
    _socket?.dispose();
  }
}
