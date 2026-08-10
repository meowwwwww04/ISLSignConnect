const express = require("express");
const http = require("http");
const { Server } = require("socket.io");
const cors = require("cors");
const path = require("path");

const app = express();
app.use(cors());
app.use(express.static(path.join(__dirname, "public")));

const server = http.createServer(app);
const io = new Server(server, {
  cors: {
    origin: "*",
    methods: ["GET", "POST"]
  }
});

// Store room states: room ID -> array of participant objects { id, role }
const rooms = {};

io.on("connection", (socket) => {
  console.log(`[Socket] New connection: ${socket.id}`);

  // Participant joins a room with a specified role ('deaf' or 'hearing')
  socket.on("join-room", ({ roomId, role }) => {
    socket.join(roomId);

    if (!rooms[roomId]) {
      rooms[roomId] = [];
    }

    // Clean up existing socket if present
    rooms[roomId] = rooms[roomId].filter(p => p.id !== socket.id);
    rooms[roomId].push({ id: socket.id, role: role || "hearing" });

    console.log(`[Room] ${socket.id} joined room '${roomId}' as '${role}'`);

    // Notify room of updated participant list and new user
    io.to(roomId).emit("room-participants", rooms[roomId]);
    socket.to(roomId).emit("user-joined", { id: socket.id, role: role || "hearing" });
  });

  // Relay WebRTC SDP offer
  socket.on("offer", (data) => {
    console.log(`[WebRTC] Relay offer from ${socket.id} to room ${data.roomId}`);
    socket.to(data.roomId).emit("offer", {
      senderId: socket.id,
      offer: data.offer
    });
  });

  // Relay WebRTC SDP answer
  socket.on("answer", (data) => {
    console.log(`[WebRTC] Relay answer from ${socket.id} to room ${data.roomId}`);
    socket.to(data.roomId).emit("answer", {
      senderId: socket.id,
      answer: data.answer
    });
  });

  // Relay ICE candidate
  socket.on("ice-candidate", (data) => {
    socket.to(data.roomId).emit("ice-candidate", {
      senderId: socket.id,
      candidate: data.candidate
    });
  });

  // Relay ISL Sign Recognition event (Deaf -> Hearing)
  socket.on("gesture-recognized", (data) => {
    console.log(`[SignConnect] Gesture recognized in room ${data.roomId}: ${data.word} (${data.confidence}%)`);
    socket.to(data.roomId).emit("gesture-recognized", {
      senderId: socket.id,
      word: data.word,
      confidence: data.confidence,
      timestamp: Date.now()
    });
  });

  // Relay Speech-to-Text transcript (Hearing -> Deaf)
  socket.on("speech-transcript", (data) => {
    console.log(`[SignConnect] Speech transcript in room ${data.roomId}: "${data.text}"`);
    socket.to(data.roomId).emit("speech-transcript", {
      senderId: socket.id,
      text: data.text,
      isFinal: data.isFinal,
      timestamp: Date.now()
    });
  });

  // Role toggle event
  socket.on("change-role", ({ roomId, role }) => {
    if (rooms[roomId]) {
      const p = rooms[roomId].find(p => p.id === socket.id);
      if (p) {
        p.role = role;
        io.to(roomId).emit("room-participants", rooms[roomId]);
      }
    }
  });

  // Disconnect handler
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

const PORT = process.env.PORT || 5000;
server.listen(PORT, () => {
  console.log(`====================================================`);
  console.log(`  SignConnect Server listening on http://localhost:${PORT}`);
  console.log(`  Open in browser: http://localhost:${PORT}`);
  console.log(`====================================================`);
});
