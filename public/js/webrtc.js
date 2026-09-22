/**
 * SignConnect — WebRTC & Socket.IO Real-Time Peer Connection Controller
 */

class SignConnectWebRTC {
  constructor(options = {}) {
    this.socket = null;
    this.peerConnection = null;
    this.localStream = null;
    this.remoteStream = null;
    this.roomId = null;
    this.role = options.role || "hearing";

    this.onRemoteStream = options.onRemoteStream || (() => {});
    this.onUserJoined = options.onUserJoined || (() => {});
    this.onUserLeft = options.onUserLeft || (() => {});
    this.onGestureReceived = options.onGestureReceived || (() => {});
    this.onSpeechReceived = options.onSpeechReceived || (() => {});
    this.onParticipantsUpdate = options.onParticipantsUpdate || (() => {});

    // Buffer ICE candidates that arrive before peer connection is ready
    this.pendingIceCandidates = [];

    this.iceServers = null; // Loaded async from /api/turn-credentials
    this._iceServersPromise = this._fetchIceServers();

    this.initSocket();
  }

  async _fetchIceServers() {
    const fallback = [
      { urls: "stun:stun.l.google.com:19302" },
      { urls: "stun:stun1.l.google.com:19302" }
    ];
    try {
      const resp = await fetch("/api/turn-credentials", { signal: AbortSignal.timeout(3000) });
      if (resp.ok) {
        const data = await resp.json();
        if (data.iceServers && data.iceServers.length > 0) {
          this.iceServers = data.iceServers;
          console.log("[WebRTC] Loaded", data.iceServers.length, "ICE servers (incl. TURN)");
          return this.iceServers;
        }
      }
    } catch (e) {
      console.warn("[WebRTC] TURN credential fetch failed, using STUN-only:", e.message);
    }
    this.iceServers = fallback;
    return this.iceServers;
  }

  initSocket() {
    this.socket = io();

    this.socket.on("connect", () => {
      console.log("[WebRTC] Socket connected, ID:", this.socket.id);
    });

    this.socket.on("connect_error", (err) => {
      console.error("[WebRTC] Socket connection error:", err.message);
    });

    this.socket.on("room-participants", (participants) => {
      console.log("[WebRTC] Room participants:", participants.length, "users");
      this.onParticipantsUpdate(participants);
    });

    this.socket.on("user-joined", async (data) => {
      console.log("[WebRTC] Peer joined:", data.id, "role:", data.role);
      this.onUserJoined(data);
      // This peer becomes the initiator - create and send offer
      console.log("[WebRTC] Creating offer as initiator...");
      await this.createOffer();
    });

    this.socket.on("offer", async (data) => {
      console.log("[WebRTC] Received offer from:", data.senderId);
      await this.handleOffer(data.offer);
    });

    this.socket.on("answer", async (data) => {
      console.log("[WebRTC] Received answer from:", data.senderId);
      await this.handleAnswer(data.answer);
    });

    this.socket.on("ice-candidate", async (data) => {
      if (!data.candidate) return;
      if (this.peerConnection && this.peerConnection.remoteDescription) {
        try {
          await this.peerConnection.addIceCandidate(data.candidate);
          console.log("[WebRTC] ICE candidate added successfully");
        } catch (err) {
          console.error("[WebRTC] Error adding ICE candidate:", err.message);
        }
      } else {
        // Buffer candidate if peer connection or remote desc not ready yet
        console.log("[WebRTC] Buffering ICE candidate (not ready yet)");
        this.pendingIceCandidates.push(data.candidate);
      }
    });

    this.socket.on("user-left", (userId) => {
      console.log("[WebRTC] Peer left:", userId);
      this.onUserLeft(userId);
      this.cleanupPeerConnection();
    });

    // Sign Gesture relay (Deaf -> Hearing)
    this.socket.on("gesture-recognized", (data) => {
      console.log("[WebRTC] Gesture received from peer:", data.word);
      this.onGestureReceived(data);
    });

    // Speech Transcript relay (Hearing -> Deaf)
    this.socket.on("speech-transcript", (data) => {
      console.log("[WebRTC] Speech received from peer:", data.text);
      this.onSpeechReceived(data);
    });
  }

  async joinRoom(roomId, role, localStream) {
    this.roomId = roomId;
    this.role = role;
    this.localStream = localStream;
    console.log("[WebRTC] Joining room:", roomId, "as", role);
    this.socket.emit("join-room", { roomId, role });
  }

  async createPeerConnection() {
    if (this.peerConnection) return this.peerConnection;

    // Ensure ICE servers are loaded (with TURN credentials if available)
    if (!this.iceServers) {
      await this._iceServersPromise;
    }

    console.log("[WebRTC] Creating new RTCPeerConnection with", this.iceServers.length, "ICE servers");
    this.peerConnection = new RTCPeerConnection({ iceServers: this.iceServers });

    if (this.localStream) {
      this.localStream.getTracks().forEach(track => {
        console.log("[WebRTC] Adding local track:", track.kind);
        this.peerConnection.addTrack(track, this.localStream);
      });
    }

    this.peerConnection.onicecandidate = (event) => {
      if (event.candidate && this.roomId) {
        console.log("[WebRTC] Sending ICE candidate:", event.candidate.candidate ? "has-candidate" : "null");
        this.socket.emit("ice-candidate", {
          roomId: this.roomId,
          candidate: event.candidate
        });
      }
    };

    this.peerConnection.ontrack = (event) => {
      console.log("[WebRTC] Remote track received!", event.track.kind);
      this.remoteStream = event.streams[0];
      this.onRemoteStream(this.remoteStream);
    };

    this.peerConnection.oniceconnectionstatechange = () => {
      console.log("[WebRTC] ICE connection state:", this.peerConnection.iceConnectionState);
    };

    this.peerConnection.onconnectionstatechange = () => {
      console.log("[WebRTC] Connection state:", this.peerConnection.connectionState);
    };

    return this.peerConnection;
  }

  async flushPendingIceCandidates() {
    if (this.pendingIceCandidates.length > 0 && this.peerConnection && this.peerConnection.remoteDescription) {
      console.log(`[WebRTC] Flushing ${this.pendingIceCandidates.length} buffered ICE candidates`);
      for (const candidate of this.pendingIceCandidates) {
        try {
          await this.peerConnection.addIceCandidate(candidate);
        } catch (err) {
          console.error("[WebRTC] Error adding buffered ICE candidate:", err.message);
        }
      }
      this.pendingIceCandidates = [];
    }
  }

  async createOffer() {
    try {
      const pc = await this.createPeerConnection();
      const offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      console.log("[WebRTC] Offer created and local description set");

      this.socket.emit("offer", {
        roomId: this.roomId,
        offer: offer
      });
    } catch (err) {
      console.error("[WebRTC] Error creating offer:", err);
    }
  }

  async handleOffer(offer) {
    try {
      const pc = await this.createPeerConnection();
      await pc.setRemoteDescription(new RTCSessionDescription(offer));
      console.log("[WebRTC] Remote description set from offer");

      // Flush any buffered ICE candidates
      await this.flushPendingIceCandidates();

      const answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      console.log("[WebRTC] Answer created and local description set");

      this.socket.emit("answer", {
        roomId: this.roomId,
        answer: answer
      });
    } catch (err) {
      console.error("[WebRTC] Error handling offer:", err);
    }
  }

  async handleAnswer(answer) {
    try {
      if (this.peerConnection) {
        await this.peerConnection.setRemoteDescription(new RTCSessionDescription(answer));
        console.log("[WebRTC] Remote description set from answer");

        // Flush any buffered ICE candidates
        await this.flushPendingIceCandidates();
      }
    } catch (err) {
      console.error("[WebRTC] Error handling answer:", err);
    }
  }

  cleanupPeerConnection() {
    if (this.peerConnection) {
      this.peerConnection.close();
      this.peerConnection = null;
      this.pendingIceCandidates = [];
      console.log("[WebRTC] Peer connection cleaned up");
    }
  }

  sendGesture(word, confidence) {
    if (this.socket && this.roomId) {
      console.log("[WebRTC] Sending gesture:", word);
      this.socket.emit("gesture-recognized", {
        roomId: this.roomId,
        word: word,
        confidence: confidence
      });
    }
  }

  sendSpeechTranscript(text, isFinal = true) {
    if (this.socket && this.roomId) {
      console.log("[WebRTC] Sending speech:", text);
      this.socket.emit("speech-transcript", {
        roomId: this.roomId,
        text: text,
        isFinal: isFinal
      });
    }
  }
}

if (typeof window !== "undefined") {
  window.SignConnectWebRTC = SignConnectWebRTC;
}

// ============================================================
// Flutter Web JS Bridge — global functions called by Dart via dart:js
// ============================================================

let _flutterSocket = null;
let _flutterOnConnected = null;
let _flutterOnGestureReceived = null;
let _flutterOnSpeechReceived = null;

function initSignConnectRTC(roomId, role, onConnected, onGestureReceived, onSpeechReceived) {
  console.log("[Flutter Bridge] initSignConnectRTC room:", roomId, "role:", role);

  _flutterOnConnected = onConnected;
  _flutterOnGestureReceived = onGestureReceived;
  _flutterOnSpeechReceived = onSpeechReceived;

  if (_flutterSocket) {
    _flutterSocket.disconnect();
    _flutterSocket = null;
  }

  _flutterSocket = io();

  _flutterSocket.on("connect", () => {
    console.log("[Flutter Bridge] Socket connected:", _flutterSocket.id);
    _flutterSocket.emit("join-room", { roomId, role });
    if (_flutterOnConnected) {
      try { _flutterOnConnected(true, role); } catch (e) { console.warn("[Flutter Bridge] onConnected callback error:", e); }
    }
  });

  _flutterSocket.on("connect_error", (err) => {
    console.error("[Flutter Bridge] Socket connection error:", err.message);
    if (_flutterOnConnected) {
      try { _flutterOnConnected(false, ""); } catch (e) { console.warn("[Flutter Bridge] onConnected callback error:", e); }
    }
  });

  _flutterSocket.on("disconnect", () => {
    console.log("[Flutter Bridge] Socket disconnected");
    if (_flutterOnConnected) {
      try { _flutterOnConnected(false, ""); } catch (e) { console.warn("[Flutter Bridge] onConnected callback error:", e); }
    }
  });

  _flutterSocket.on("room-participants", (participants) => {
    console.log("[Flutter Bridge] Room participants:", participants.length, "users");
  });

  _flutterSocket.on("user-joined", (data) => {
    console.log("[Flutter Bridge] Peer joined:", data.id, "role:", data.role);
  });

  _flutterSocket.on("user-left", (userId) => {
    console.log("[Flutter Bridge] Peer left:", userId);
  });

  _flutterSocket.on("gesture-recognized", (data) => {
    console.log("[Flutter Bridge] Gesture received:", data.word);
    if (_flutterOnGestureReceived) {
      try { _flutterOnGestureReceived(data.word, data.confidence); } catch (e) { console.warn("[Flutter Bridge] gesture callback error:", e); }
    }
  });

  _flutterSocket.on("speech-transcript", (data) => {
    console.log("[Flutter Bridge] Speech received:", data.text);
    if (_flutterOnSpeechReceived) {
      try { _flutterOnSpeechReceived(data.text); } catch (e) { console.warn("[Flutter Bridge] speech callback error:", e); }
    }
  });
}

function broadcastSignConnectGesture(roomId, word, confidence) {
  if (_flutterSocket && _flutterSocket.connected) {
    console.log("[Flutter Bridge] Sending gesture:", word);
    _flutterSocket.emit("gesture-recognized", {
      roomId: roomId,
      word: word,
      confidence: confidence
    });
  } else {
    console.warn("[Flutter Bridge] Cannot send gesture: socket not connected");
  }
}

function broadcastSignConnectSpeech(roomId, text) {
  if (_flutterSocket && _flutterSocket.connected) {
    console.log("[Flutter Bridge] Sending speech:", text);
    _flutterSocket.emit("speech-transcript", {
      roomId: roomId,
      text: text,
      isFinal: true
    });
  } else {
    console.warn("[Flutter Bridge] Cannot send speech: socket not connected");
  }
}

let _flutterSpeechRecognition = null;

function startSignConnectSpeechRecognition(onResult) {
  const SpeechRecognitionAPI = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SpeechRecognitionAPI) {
    console.warn("[Flutter Bridge] Web Speech API not supported in this browser");
    return;
  }

  if (_flutterSpeechRecognition) {
    try { _flutterSpeechRecognition.stop(); } catch (e) {}
  }

  _flutterSpeechRecognition = new SpeechRecognitionAPI();
  _flutterSpeechRecognition.continuous = true;
  _flutterSpeechRecognition.interimResults = true;
  _flutterSpeechRecognition.lang = "en-IN";

  _flutterSpeechRecognition.onresult = (event) => {
    for (let i = event.resultIndex; i < event.results.length; i++) {
      if (event.results[i].isFinal) {
        const text = event.results[i][0].transcript.trim();
        if (text && onResult) {
          try { onResult(text); } catch (e) { console.warn("[Flutter Bridge] speech result callback error:", e); }
        }
      }
    }
  };

  _flutterSpeechRecognition.onerror = (err) => {
    console.warn("[Flutter Bridge] Speech recognition error:", err.error);
    if (err.error === "no-speech" || err.error === "audio-capture") {
      setTimeout(() => {
        try { _flutterSpeechRecognition.start(); } catch (e) {}
      }, 1000);
    }
  };

  _flutterSpeechRecognition.onend = () => {
    console.log("[Flutter Bridge] Speech recognition ended, restarting...");
    setTimeout(() => {
      try { _flutterSpeechRecognition.start(); } catch (e) {}
    }, 500);
  };

  try {
    _flutterSpeechRecognition.start();
    console.log("[Flutter Bridge] Speech recognition started");
  } catch (e) {
    console.warn("[Flutter Bridge] Could not start speech recognition:", e.message);
  }
}

function leaveSignConnectCall() {
  console.log("[Flutter Bridge] Leaving call");
  if (_flutterSpeechRecognition) {
    try { _flutterSpeechRecognition.stop(); } catch (e) {}
    _flutterSpeechRecognition = null;
  }
  if (_flutterSocket) {
    _flutterSocket.disconnect();
    _flutterSocket = null;
  }
  _flutterOnConnected = null;
  _flutterOnGestureReceived = null;
  _flutterOnSpeechReceived = null;
}
