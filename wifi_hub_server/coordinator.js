/**
 * WiFi Hub — Coordinator Server
 *
 * Will always run on my laptop. Does three jobs:
 *   1. WebSocket server (port 8080) — contributor phones register here
 *   2. TCP server (port 1080)       — wifi users connect here via SOCKS5
 *   3. Frame router                 — pipes bytes between users and contributors
 *
 * Frame format (binary, same protocol as ContributorWebSocket.kt):
 *   [4 bytes big-endian: tunnelId][1 byte: type][remaining bytes: payload]
 *
 * Types:
 *   0x01 DATA     — raw bytes to pipe
 *   0x02 OPEN     — coordinator → contributor: new tunnel
 *   0x03 CLOSE    — either side closing a tunnel
 *   0x04 REGISTER — contributor → coordinator: "I'm available"
 *   0x05 ACK      — coordinator → contributor: confirmed
 */
const { open } = require("inspector/promises");
const net = require("net");
const { WebSocketServer } = require("ws");

//ports
WS_PORT = 8080;
TCP_PORT = 1080;

const TYPE_DATA = 0x01;
const TYPE_OPEN = 0x02;
const TYPE_CLOSE = 0x03;
const TYPE_REGISTER = 0x04;
const TYPE_ACK = 0x05;

const contributorRegistry = new Map();
const tunnelMap = new Map();
const stickyMap = new Map(); //for sticky sessions so that the current requests of the client are routed to a particular contributor(temporary)
let nextTunnelId = 1;
let tunnelId = 1;
const STICKY_TTL_MS = 10 * 60 * 1000;
const stickyTimers = new Map();

//helper functions

function buildFrame(tunnelId, type, payload = Buffer.alloc(0)) {
  const frame = Buffer.allocUnsafe(4 + 1 + payload.length);
  frame.writeUInt32BE(tunnelId, 0);
  frame[4] = type;
  if (payload.length > 0) payload.copy(frame, 5);
  return frame;
}
function parseFrame(buf) {
  if (buf.length < 5) return null;
  return {
    tunnelId: buf.readUInt32BE(0),
    type: buf[4],
    payload: buf.slice(5),
  };
}
//load balancer
function pickContributor(excludedId = null) {
  let bestId = null;
  let bestCount = Infinity;

  for (const [id, info] of contributorRegistry) {
    if (id === excludedId) continue;
    if (info.tunnelCount < bestCount) {
      bestCount = info.tunnelCount;
      bestId = id;
    }
  }
  return bestId;
}

function getOrAssignContributor(clientIP) {
  // Cancel any pending release timer for this client
  if (stickyTimers.has(clientIP)) {
    clearTimeout(stickyTimers.get(clientIP));
    stickyTimers.delete(clientIP);
  }

  // If already assigned to a contributor that is still connected, reuse it
  const existingId = stickyMap.get(clientIP);
  if (existingId && contributorRegistry.has(existingId)) {
    console.log(`[STICKY] ${clientIP} reusing contributor ${existingId}`);
    return existingId;
  }

  // Otherwise pick a new one
  const newId = pickContributor();
  if (!newId) return null;

  stickyMap.set(clientIP, newId);
  console.log(`[STICKY] ${clientIP} assigned to contributor ${newId}`);
  return newId;
}

function scheduleRelease(clientIP) {
  if (stickyTimers.has(clientIP)) return; // already scheduled

  const handle = setTimeout(() => {
    stickyMap.delete(clientIP);
    stickyTimers.delete(clientIP);
    console.log(`[STICKY] Released assignment for ${clientIP} after TTL`);
  }, STICKY_TTL_MS);

  stickyTimers.set(clientIP, handle);
}

//lifecycle
/**
 * Builds the TYPE_OPEN payload carrying the target host and port.
 *
 * Layout:
 *   [1 byte : host length]
 *   [N bytes: host string (UTF-8)]
 *   [2 bytes: port, big-endian]
 *
 * The contributor's TunnelSession reads this to synthesise the SOCKS5
 * handshake against its own local ProxyService.
 */
function buildOpenPayload(host, port) {
  const hostbuf = Buffer.from(host, "utf8");
  const payload = Buffer.allocUnsafe(1 + hostbuf.length + 2);
  payload.writeUInt16BE(port, 1 + hostbuf.length);
  return payload;
}

function openTunnel(clientSocket, contributorId, host, port) {
  const tunnelId = nextTunnelId++;
  const contributor = contributorRegistry.get(contributorId);

  tunnelMap.set(tunnelId, { clientSocket, contributorId });
  contributor.tunnelCount++;

  const payload = buildOpenPayload(host, port);
  contributor.ws.send(buildFrame(tunnelId, TYPE_OPEN, payload));
  console.log(
    `[TUNNEL] Opened tunnelId=${tunnelId} → contributor=${contributorId} target=${host}:${port} (now ${contributor.tunnelCount} active)`,
  );

  return tunnelId;
}

function closeTunnel(tunnelId, clientIP) {
  const tunnel = tunnelMap.get(tunnelId);
  if (!tunnel) return;

  const contributor = contributorRegistry.get(tunnel.contributorId);
  if (contributor) {
    contributor.ws.send(buildFrame(tunnelId, TYPE_CLOSE));
    contributor.tunnelCount = Math.max(0, contributor.tunnelCount - 1);
  }

  tunnelMap.delete(tunnelId);
  console.log(`[TUNNEL] Closed tunnelId=${tunnelId}`);

  // Check if this client IP has any remaining tunnels
  const clientStillActive = [...tunnelMap.values()].some(
    (t) => t.clientSocket.remoteAddress === clientIP,
  );
  if (!clientStillActive) {
    scheduleRelease(clientIP);
  }
}
//contributor to server connection
const wss = new WebSocketServer({ port: WS_PORT });

wss.on("listening", (ws) => {
  console.log(`[WS] contributor websocket server listening on port ${WS_PORT}`);
});

wss.on("connection", (ws) => {
  const contributorID = `contrib_${Date.now()}_${Math.random().toString(36).slice(2, 7)}`;
  console.log(
    `new contributor enlsited on with connection ID ${contributorID}`,
  );

  contributorRegistry.set(contributorID, { ws, tunnelCount: 0 });

  ws.send(buildFrame(0, TYPE_ACK));

  ws.on("message", (data) => {
    const frame = parseFrame(Buffer.isBuffer(data) ? data : Buffer.from(data));
    if (!frame) return;
    const { tunnelId, type, payload } = frame;

    if (type === TYPE_REGISTER) {
      ws.send(buildFrame(0, TYPE_ACK));
      return;
    }

    if (type === TYPE_DATA) {
      const tunnel = tunnelMap.get(tunnelId);
      if (!tunnel) {
        console.warn(`[WS]  DATA for unknown tunnelId=${tunnelId}`);
        return;
      }
      tunnel.clientSocket.write(payload);
      return;
    }

    if (type === TYPE_CLOSE) {
      const tunnel = tunnelMap.get(tunnelId);
      if (tunnel) {
        const ip = tunnel.clientSocket.remoteAddress;
        tunnel.clientSocket.destroy();
        closeTunnel(tunnelId, ip);
      }
      return;
    }
  });

  ws.on("close", (ws) => {
    console.log(`contributor with ID ${contributorID} closed`);
    contributorRegistry.delete(contributorID);

    for (const [tunnelId, tunnel] of tunnelMap) {
      if (tunnel.contributorID === contributorID) {
        const ip = tunnel.clientSocket.remoteAddress;
        tunnel.clientSocket.destroy();
        tunnelMap.delete(tunnelId);
        console.log(
          `[WS] closed tunnel with ID ${tunnelId}. Contributor disconnected`,
        );
        scheduleRelease(ip);
      }
    }

    for (const [ip, cId] of stickyMap) {
      if (cId === contributorID) {
        stickyMap.delete(ip);
        console.log(
          `[STICKY] Released ${ip} sticky assignment (contributor left`,
        );
      }
    }
  });

  ws.on("error", (e) => {
    console.error(`[WS] Contributor ${contributorID} error: ${e.message}`);
  });
});

const tcpServer = net.createServer((clientSocket) => {
  const clientIP = clientSocket.remoteAddress;
  console.log(`[TCP] New client connection from ${clientIP}`);

  let handshakeDone = false;
  let tunnelId = null;
  let buffer = Buffer.alloc(0);
  let stage = 0;

  clientSocket.on("data", (chunk) => {
    console.log(
      `[DEBUG] received ${chunk.length} bytes, handshakeDone=${handshakeDone}, buffer=${buffer.toString("hex").slice(0, 40)}`,
    );
    if (handshakeDone) {
      if (tunnelId !== null) {
        const tunnel = tunnelMap.get(tunnelId);
        if (tunnel) {
          const contributor = contributorRegistry.get(tunnel.contributorID);
          if (contributor)
            contributor.ws.send(buildFrame(tunnelId, TYPE_DATA, chunk));
        }
      }
      return;
    }

    buffer = Buffer.concat([buffer, chunk]);
    processBuffer();
  });

  function processBuffer() {
    if (stage === 0) {
      if (buffer.length < 2) return;
      const nMethods = buffer[1];
      if (buffer.length < 2 + nMethods) return;
      if (buffer[0] !== 5) {
        clientSocket.destroy();
        return;
      }
      clientSocket.write(Buffer.from([0x05, 0x00]));
      buffer = buffer.slice(2 + nMethods);
      stage = 1;
    }

    if (stage === 1) {
      if (buffer.length < 4) return;
      const cmd = buffer[1];
      const atyp = buffer[3];

      if (cmd !== 0x01) {
        clientSocket.write(
          Buffer.from([0x05, 0x07, 0x00, 0x01, 0, 0, 0, 0, 0, 0]),
        );
        clientSocket.destroy();
        return;
      }

      let host, consumed;
      if (atyp === 0x01) {
        if (buffer.length < 10) return;
        host = buffer[4] + "." + buffer[5] + "." + buffer[6] + "." + buffer[7];
        consumed = 10;
      } else if (atyp === 0x03) {
        if (buffer.length < 5) return;
        const len = buffer[4];
        if (buffer.length < 5 + len + 2) return;
        host = buffer.slice(5, 5 + len).toString();
        consumed = 5 + len + 2;
      } else if (atyp === 0x04) {
        if (buffer.length < 22) return;
        const parts = [];
        for (let i = 0; i < 16; i += 2)
          parts.push(buffer.readUInt16BE(4 + i).toString(16));
        host = parts.join(":");
        consumed = 22;
      } else {
        clientSocket.write(
          Buffer.from([0x05, 0x08, 0x00, 0x01, 0, 0, 0, 0, 0, 0]),
        );
        clientSocket.destroy();
        return;
      }

      const port = buffer.readUInt16BE(consumed - 2);
      buffer = buffer.slice(consumed);
      console.log(
        "[TCP] Client " + clientIP + " wants to reach " + host + ":" + port,
      );

      const contributorId = getOrAssignContributor(clientIP);
      if (!contributorId) {
        console.warn("[TCP] No contributors available for " + clientIP);
        clientSocket.write(
          Buffer.from([0x05, 0x04, 0x00, 0x01, 0, 0, 0, 0, 0, 0]),
        );
        clientSocket.destroy();
        return;
      }

      tunnelId = openTunnel(clientSocket, contributorId, host, port);
      handshakeDone = true;
      stage = 2;
      clientSocket.write(
        Buffer.from([0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]),
      );

      if (buffer.length > 0) {
        const contributor = contributorRegistry.get(contributorId);
        if (contributor)
          contributor.ws.send(buildFrame(tunnelId, TYPE_DATA, buffer));
        buffer = Buffer.alloc(0);
      }
    }
  }

  clientSocket.on("close", () => {
    console.log(`[TCP] Client ${clientIP} disconnected`);
    if (tunnelId !== null) {
      closeTunnel(tunnelId, clientIP);
    }
  });

  clientSocket.on("error", (err) => {
    console.error(`[TCP] Client ${clientIP} error: ${err.message}`);
    if (tunnelId !== null) {
      closeTunnel(tunnelId, clientIP);
    }
  });
});

tcpServer.listen(TCP_PORT, () => {
  console.log(`[TCP] SOCKS5 listener on port ${TCP_PORT}`);
});

tcpServer.on("error", (err) => {
  console.error(`[TCP] Server error: ${err.message}`);
});

setInterval(() => {
  console.log(
    `[STATUS] Contributors: ${contributorRegistry.size} | Active tunnels: ${tunnelMap.size} | Sticky sessions: ${stickyMap.size}`,
  );
}, 30_000);

console.log("WiFi Hub Coordinator starting...");
