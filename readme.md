# WiFi Hub

WiFi Hub is a distributed internet-sharing system that allows one Android device to access the internet through another device's mobile data connection.

Instead of routing packets directly over a VPN, WiFi Hub implements its own tunneling protocol over WebSockets while using SOCKS5 as the local proxy protocol on Android.

The project is split into two components:

```
wifi_hub/
├── wifi_hub_frontend/   # Flutter Android application
└── wifi_hub_server/     # Node.js WebSocket coordinator
```

---

# Overview

A user device (WiFi user) connects to a contributor device that has an active mobile data connection.

The coordinator server acts only as a signaling and tunneling server.

The contributor performs the actual internet access.

```
Browser
    │
    ▼
Coordinator SOCKS5 Proxy
    │
    ▼
WebSocket Tunnel
    │
    ▼
Contributor SOCKS5 Proxy
    │
    ▼
Mobile Data
    │
    ▼
Internet
```

---

# Features

- Flutter frontend
- Android foreground SOCKS5 proxy service
- WebSocket-based coordinator
- Binary multiplexed tunnel protocol
- Multiple simultaneous tunnels
- SOCKS5 protocol implementation
- Bidirectional TCP relay
- Automatic contributor registration
- Background Android service
- No VPN permissions required

---

# Repository Structure

```
wifi_hub/
│
├── wifi_hub_frontend/
│   ├── android/
│   ├── lib/
│   ├── ios/
│   └── ...
│
└── wifi_hub_server/
    ├── coordinator.js
    ├── package.json
    └── ...
```

---

# Architecture

## Frontend

Responsible for:

- User interface
- Starting/stopping proxy service
- Connecting to coordinator
- Managing contributor mode
- Tunnel creation

Technology:

- Flutter
- Kotlin (Android platform code)
- MethodChannels

---

## Coordinator Server

Responsibilities:

- Accept contributor WebSocket connections
- Register contributors
- Create tunnels
- Forward binary packets
- Manage active sessions

Technology:

- Node.js
- WebSocket

---

## Contributor

Runs a local SOCKS5 proxy.

Responsibilities:

- Receive tunnel requests
- Perform SOCKS5 handshake
- Open internet connections
- Relay traffic
- Send responses back

---

# Tunnel Protocol

The coordinator and contributor communicate using custom binary frames.

Each frame contains:

```
+-----------+--------+-----------+
| Tunnel ID |  Type  | Payload   |
+-----------+--------+-----------+
```

Frame types include:

- REGISTER
- OPEN
- DATA
- CLOSE

This allows multiple TCP connections to be multiplexed over a single WebSocket.

---

# SOCKS5 Flow

Browser

↓

Greeting

↓

CONNECT Request

↓

Coordinator

↓

OPEN Frame

↓

Contributor

↓

Local SOCKS5 Server

↓

Internet

After the SOCKS5 CONNECT request succeeds, all TCP traffic is relayed through the tunnel.

---

# Technologies

Frontend

- Flutter
- Dart
- Kotlin
- Android SDK

Backend

- Node.js
- WebSocket

Networking

- SOCKS5
- TCP
- WebSocket
- Kotlin Coroutines

---

# Current Status

Implemented:

- SOCKS5 greeting
- SOCKS5 CONNECT parsing
- Binary tunnel protocol
- Tunnel session management
- WebSocket coordinator
- TCP relay
- Android foreground service

In Progress:

- Contributor selection
- Load balancing
- Multiple contributors
- Authentication
- Encryption
- Failure recovery

---

# Running the Project

## Frontend

```
cd wifi_hub_frontend
flutter pub get
flutter run
```

---

## Coordinator

```
cd wifi_hub_server
npm install
node coordinator.js
```

---

# Future Improvements

- End-to-end encryption
- Contributor reputation system
- Bandwidth accounting
- Multi-hop routing
- Offline peer discovery
- QUIC transport
- Better congestion control
- Usage analytics
- NAT traversal
- TLS support

---

# License

This project is intended for educational and research purposes.
