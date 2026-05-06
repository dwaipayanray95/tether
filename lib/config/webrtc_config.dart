class WebRTCConfig {
  // Oracle Cloud Signaling Server URL (e.g., http://your-ip:8080)
  static const String signalingServerUrl = 'http://140.245.15.108:8080';

  // Metered STUN/TURN Credentials
  // You get these from your Metered Dashboard
  static const List<Map<String, dynamic>> iceServers = [
    {
      'urls': [
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
      ],
    },
    {
      'urls': [
        'turn:relay.metered.ca:80',
        'turn:relay.metered.ca:443',
        'turn:relay.metered.ca:443?transport=tcp',
      ],
      'username': '71c5d2bddc6d2a6803c970ae',
      'credential': 'Hh5k8NKgycg2vJL1',
    },
  ];

  static const Map<String, dynamic> dcConstraints = {
    'mandatory': {
      'OfferToReceiveAudio': true,
      'OfferToReceiveVideo': false,
    },
    'optional': [],
  };

  static const Map<String, dynamic> mediaConstraints = {
    'audio': true,
    'video': false,
  };
}
