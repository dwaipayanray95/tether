# Voice Calling Setup Guide

This guide helps you set up the infrastructure for the WebRTC voice calling feature.

## 1. Metered (STUN/TURN)
Metered provides the relay servers needed for calls to connect over different networks (NAT).
1. Go to [metered.ca](https://www.metered.ca/) and create a free account.
2. Create a new "TURN Server" application.
3. In the "Global Turn Servers" section, you will find your credentials.
4. Open `lib/config/webrtc_config.dart` and add your TURN server configuration to the `iceServers` list.

## 2. Oracle Cloud (Signaling Server)
The signaling server helps the two apps "find" each other and exchange connection details.
1. Log into your [Oracle Cloud Console](https://www.oracle.com/cloud/).
2. **Create Compute Instance**:
   - Create an "Always Free" Ubuntu instance.
   - Note the **Public IP Address**.
3. **Network Configuration**:
   - Go to your VCN -> Security Lists -> Default Security List.
   - Add an **Ingress Rule**:
     - Source CIDR: `0.0.0.0/0`
     - IP Protocol: `TCP`
     - Destination Port Range: `8080`
4. **Server Setup**:
   - SSH into your Ubuntu instance.
   - Install Node.js: `sudo apt update && sudo apt install nodejs npm -y`
   - Upload the contents of the `signaling-server` folder to the server.
   - Run `npm install`.
   - Start the server: `node index.js`. (Use `pm2` to keep it running in the background).
5. **App Configuration**:
   - Update `lib/config/webrtc_config.dart` with your Oracle Cloud Public IP:
     `static const String signalingServerUrl = 'http://your-ip:8080';`

## 3. Platform-Specific Notes

### Android
- Ensure `minSdkVersion` is at least **24** in `android/app/build.gradle.kts`.
- The permissions and `ConnectionService` have been added to `AndroidManifest.xml`.

### iOS
- The microphone permission and background modes (VOIP/Audio) have been added to `Info.plist`.
- You may need to run `pod install` in the `ios` directory.

## 4. Usage
Once everything is configured:
1. Open the app on both devices.
2. Go to the Home screen and tap the **Call** button.
3. The other device should ring (using the native CallKit UI) even if the app is in the background.
