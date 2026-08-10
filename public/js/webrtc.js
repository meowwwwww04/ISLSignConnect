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
    this.role = options.role || "hearing"; // 'deaf' or 'hearing'

    this.onRemoteStream = options.onRemoteStream || (() => {});
    this.onUserJoined = options.onUserJoined || (() => {});
    this.onUserLeft = options.onUserLeft || (() => {});
    this.onGestureReceived = options.onGestureReceived || (() => {});
    this.onSpeechReceived = options.onSpeechReceived || (() => {});
    this.onParticipantsUpdate = options.onParticipantsUpdate || (() => {});

    this.iceServers = [
      { urls: "stun:stun.l.google.com:19302" },
      { urls: "stun:stun1.l.google.com:19302" }
    ];

    this.initSocket();
  }

  initSocket() {
    this.socket = io();

    this.socket.on("connect", () => {
      console.log("[WebRTC] Connected to signaling server with socket ID:", this.socket.id);
    });

    this.socket.on("room-participants", (participants) => {
      console.log("[WebRTC] Room participants update:", participants);
      this.onParticipantsUpdate(participants);
    });

    this.socket.on("user-joined", async (data) => {
      console.log("[WebRTC] User joined room:", data);
      this.onUserJoined(data);
      // Initiator creates WebRTC Offer
      await this.createOffer();
    });

    this.socket.on("offer", async (data) => {
      console.log("[WebRTC] Offer received from:", data.senderId);
      await this.handleOffer(data.offer);
    });

    this.socket.on("answer", async (data) => {
      console.log("[WebRTC] Answer received from:", data.senderId);
      await this.handleAnswer(data.answer);
    });

    this.socket.on("ice-candidate", async (data) => {
      if (data.candidate && this.peerConnection) {
        try {
          await this.peerConnection.addIceCandidate(data.candidate);
        } catch (err) {
          console.error("[WebRTC] Error adding ICE candidate:", err);
        }
      }
    });

    this.socket.on("user-left", (userId) => {
      console.log("[WebRTC] User left room:", userId);
      this.onUserLeft(userId);
      if (this.peerConnection) {
        this.peerConnection.close();
        this.peerConnection = null;
      }
    });

    // Sign Gesture relay (Deaf -> Hearing)
    this.socket.on("gesture-recognized", (data) => {
      console.log("[WebRTC] Gesture received:", data);
      this.onGestureReceived(data);
    });

    // Speech Transcript relay (Hearing -> Deaf)
    this.socket.on("speech-transcript", (data) => {
      console.log("[WebRTC] Speech transcript received:", data);
      this.onSpeechReceived(data);
    });
  }

  async joinRoom(roomId, role, localStream) {
    this.roomId = roomId;
    this.role = role;
    this.localStream = localStream;

    this.socket.emit("join-room", { roomId, role });
  }

  createPeerConnection() {
    if (this.peerConnection) return this.peerConnection;

    this.peerConnection = new RTCPeerConnection({ iceServers: this.iceServers });

    // Attach local media tracks if available
    if (this.localStream) {
      this.localStream.getTracks().forEach(track => {
        this.peerConnection.addTrack(track, this.localStream);
      });
    }

    // ICE Candidate handler
    this.peerConnection.onicecandidate = (event) => {
      if (event.candidate && this.roomId) {
        this.socket.emit("ice-candidate", {
          roomId: this.roomId,
          candidate: event.candidate
        });
      }
    };

    // Remote Track handler
    this.peerConnection.ontrack = (event) => {
      console.log("[WebRTC] Remote media track received!", event.streams[0]);
      this.remoteStream = event.streams[0];
      this.onRemoteStream(this.remoteStream);
    };

    return this.peerConnection;
  }

  async createOffer() {
    const pc = this.createPeerConnection();
    const offer = await pc.createOffer();
    await pc.setLocalDescription(offer);

    this.socket.emit("offer", {
      roomId: this.roomId,
      offer: offer
    });
  }

  async handleOffer(offer) {
    const pc = this.createPeerConnection();
    await pc.setRemoteDescription(new RTCSessionDescription(offer));

    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);

    this.socket.emit("answer", {
      roomId: this.roomId,
      answer: answer
    });
  }

  async handleAnswer(answer) {
    if (this.peerConnection) {
      await this.peerConnection.setRemoteDescription(new RTCSessionDescription(answer));
    }
  }

  sendGesture(word, confidence) {
    if (this.socket && this.roomId) {
      this.socket.emit("gesture-recognized", {
        roomId: this.roomId,
        word: word,
        confidence: confidence
      });
    }
  }

  sendSpeechTranscript(text, isFinal = true) {
    if (this.socket && this.roomId) {
      this.socket.emit("speech-transcript", {
        roomId: this.roomId,
        text: text,
        isFinal: isFinal
      });
    }
  }
}

if (typeof window !== "undefined") {
  window.SignBridgeWebRTC = SignBridgeWebRTC;
}
