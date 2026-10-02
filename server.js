const express = require("express");
const http = require("http");
const { Server } = require("socket.io");
const cors = require("cors");
const path = require("path");
const fs = require("fs");

const app = express();
app.use(cors());
app.use(express.json());

// --- Browser room page (no app install needed) ---
// Shared link format: https://<host>/room/<roomcode>
app.get("/room/:code", (req, res) => {
  res.sendFile(path.join(__dirname, "public", "room.html"));
});

// Legacy shared links: /?room=<code> → /room/<code>
app.get("/", (req, res, next) => {
  const room = req.query.room;
  if (room && typeof room === "string" && room.trim()) {
    return res.redirect(302, `/room/${encodeURIComponent(room.trim())}`);
  }
  next();
});

// Serve the working pure-web client first; Flutter web build only if present locally
app.use(express.static(path.join(__dirname, "public")));
app.use(express.static(path.join(__dirname, "signconnect_app", "build", "web")));
app.use(express.static(path.join(__dirname, "signconnect_app", "web")));

// --- TURN Credential Proxy ---
// Clients call /api/turn-credentials to get ICE servers for WebRTC.
// Google STUN (public, documented, no account needed) + Metered Open Relay TURN.

const METERED_API_KEY = process.env.METERED_API_KEY || "";
const METERED_API_URL = process.env.METERED_API_URL || "https://aiml_project.metered.live/api/v1/turn/credentials";

// Google STUN servers — officially documented, no account, no quota
const GOOGLE_STUN = [
  { urls: "stun:stun.l.google.com:19302" },
  { urls: "stun:stun1.l.google.com:19302" },
  { urls: "stun:stun2.l.google.com:19302" },
];

app.get("/api/turn-credentials", async (req, res) => {
  const iceServers = [...GOOGLE_STUN];

  if (!METERED_API_KEY) {
    console.log("[TURN] METERED_API_KEY not set — returning STUN only");
    return res.json({ iceServers });
  }

  try {
    const url = `${METERED_API_URL}?apiKey=${METERED_API_KEY}`;
    const response = await fetch(url, { signal: AbortSignal.timeout(5000) });
    if (response.ok) {
      const meteredServers = await response.json();
      iceServers.push(...meteredServers);
      console.log("[TURN] Returned Google STUN + Metered TURN servers");
    } else {
      console.warn(`[TURN] Metered API returned ${response.status} — STUN only`);
    }
  } catch (e) {
    console.warn(`[TURN] Metered API unreachable: ${e.message} — STUN only`);
  }

  res.json({ iceServers });
});
console.log("[TURN] Credential endpoint ready at /api/turn-credentials");

const server = http.createServer(app);

const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

// Store room states
const rooms = {};

io.on("connection", (socket) => {
  console.log(`[Socket] New connection: ${socket.id}`);

  socket.on("join-room", ({ roomId, role }) => {
    socket.join(roomId);

    if (!rooms[roomId]) {
      rooms[roomId] = [];
    }

    rooms[roomId] = rooms[roomId].filter(p => p.id !== socket.id);
    rooms[roomId].push({ id: socket.id, role: role || "hearing" });

    console.log(`[Room] ${socket.id} joined room '${roomId}' as '${role}' (room size: ${rooms[roomId].length})`);

    io.to(roomId).emit("room-participants", rooms[roomId]);
    socket.to(roomId).emit("user-joined", { id: socket.id, role: role || "hearing" });
  });

  socket.on("offer", (data) => {
    console.log(`[WebRTC] Relay offer from ${socket.id} to room ${data.roomId}`);
    socket.to(data.roomId).emit("offer", {
      senderId: socket.id,
      offer: data.offer
    });
  });

  socket.on("answer", (data) => {
    console.log(`[WebRTC] Relay answer from ${socket.id} to room ${data.roomId}`);
    socket.to(data.roomId).emit("answer", {
      senderId: socket.id,
      answer: data.answer
    });
  });

  socket.on("ice-candidate", (data) => {
    socket.to(data.roomId).emit("ice-candidate", {
      senderId: socket.id,
      candidate: data.candidate
    });
  });

  socket.on("gesture-recognized", (data) => {
    console.log(`[SignConnect] Gesture: ${data.word} (${data.confidence}%) in room ${data.roomId}`);
    socket.to(data.roomId).emit("gesture-recognized", {
      senderId: socket.id,
      word: data.word,
      confidence: data.confidence,
      origin: data.origin,
      timestamp: Date.now()
    });
  });

  socket.on("room-log", (data) => {
    if (!data || !data.roomId || !data.msg) return;
    console.log(`[Room ${data.roomId}] ${data.msg}`);
    socket.to(data.roomId).emit("room-log", {
      senderId: socket.id,
      msg: data.msg,
      t: Date.now()
    });
  });

  socket.on("speech-transcript", (data) => {
    console.log(`[SignConnect] Speech: "${data.text}" (final=${data.isFinal}) in room ${data.roomId}`);
    socket.to(data.roomId).emit("speech-transcript", {
      senderId: socket.id,
      text: data.text,
      isFinal: data.isFinal,
      timestamp: Date.now()
    });
  });

  socket.on("change-role", ({ roomId, role }) => {
    if (rooms[roomId]) {
      const p = rooms[roomId].find(p => p.id === socket.id);
      if (p) {
        p.role = role;
        io.to(roomId).emit("room-participants", rooms[roomId]);
      }
    }
  });

  socket.on("disconnecting", () => {
    for (const roomId of socket.rooms) {
      if (rooms[roomId]) {
        rooms[roomId] = rooms[roomId].filter(p => p.id !== socket.id);
        if (rooms[roomId].length === 0) {
          delete rooms[roomId];
        } else {
          io.to(roomId).emit("room-participants", rooms[roomId]);
          io.to(roomId).emit("user-left", socket.id);
        }
      }
    }
    console.log(`[Socket] Disconnected: ${socket.id}`);
  });
});

const PORT = process.env.PORT || 8080;

server.listen(PORT, "0.0.0.0", () => {
  console.log(``);
  console.log(`========================================================`);
  console.log(`  SignConnect Server Running`);
  console.log(`========================================================`);
  console.log(`  Local URL  : http://localhost:${PORT}`);
  console.log(`  Signaling  : Connects peers via Socket.IO`);
  console.log(`  TURN       : Metered Open Relay (via /api/turn-credentials)`);
  console.log(`========================================================`);
  console.log(``);
});
