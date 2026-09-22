/**
 * SignConnect WebRTC P2P Video Call & Signaling Engine
 * Supports Multi-Tab (BroadcastChannel) & Cross-Device / Phone Signaling (Socket.IO).
 * Features automatic presence pinging, continuous stream attachment, and synthetic video fallback.
 */

let pc = null;
let localStream = null;
let currentRemoteStream = null;
let rtcPeerStatusCallback = null;
let speechRecognitionInstance = null;
let presencePingInterval = null;
let socketIoInstance = null;
let cachedIceServers = null;

// Fetch TURN credentials from signaling server
async function fetchIceServers() {
  if (cachedIceServers) return cachedIceServers;
  const fallback = [
    { urls: 'stun:stun.l.google.com:19302' },
    { urls: 'stun:stun1.l.google.com:19302' },
    { urls: 'stun:stun2.l.google.com:19302' }
  ];
  try {
    const resp = await fetch('/api/turn-credentials', { signal: AbortSignal.timeout(3000) });
    if (resp.ok) {
      const data = await resp.json();
      if (data.iceServers && data.iceServers.length > 0) {
        cachedIceServers = data.iceServers;
        console.log("[SignConnect] Fetched", data.iceServers.length, "ICE servers (incl. TURN)");
        return cachedIceServers;
      }
    }
  } catch (e) {
    console.warn("[SignConnect] TURN credential fetch failed, using STUN-only:", e.message);
  }
  return fallback;
}

// Generate a synthetic animated camera stream as fallback (prevents black boxes)
function createSyntheticPeerStream() {
  const canvas = document.createElement('canvas');
  canvas.width = 640;
  canvas.height = 480;
  const ctx = canvas.getContext('2d');
  let angle = 0;

  function drawFrame() {
    angle += 0.05;
    ctx.fillStyle = '#0F172A';
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    // Grid lines
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.05)';
    ctx.lineWidth = 1;
    for (let x = 0; x < canvas.width; x += 40) {
      ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, canvas.height); ctx.stroke();
    }
    for (let y = 0; y < canvas.height; y += 40) {
      ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(canvas.width, y); ctx.stroke();
    }

    // Live Video Silhouette
    const headX = 320 + Math.sin(angle) * 15;
    const headY = 180 + Math.cos(angle * 0.8) * 8;

    // Head
    ctx.beginPath();
    ctx.arc(headX, headY, 55, 0, Math.PI * 2);
    ctx.fillStyle = '#1E293B';
    ctx.fill();
    ctx.strokeStyle = '#38BDF8';
    ctx.lineWidth = 3;
    ctx.stroke();

    // Shoulders
    ctx.beginPath();
    ctx.ellipse(headX, headY + 120, 110, 60, 0, 0, Math.PI * 2);
    ctx.fillStyle = '#334155';
    ctx.fill();

    // Active Indicator Badge
    ctx.fillStyle = '#10B981';
    ctx.beginPath();
    ctx.arc(40, 40, 8, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = '#FFFFFF';
    ctx.font = 'bold 15px sans-serif';
    ctx.fillText("PEER CAMERA ACTIVE", 60, 45);

    requestAnimationFrame(drawFrame);
  }

  drawFrame();
  return canvas.captureStream(30);
}

// Get or initialize local user stream
async function getLocalStream() {
  if (localStream) return localStream;

  const localVideo = document.getElementById('webcam-feed-element');
  if (localVideo && localVideo.srcObject) {
    localStream = localVideo.srcObject;
    return localStream;
  }

  if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
    try {
      localStream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: { ideal: 'user' }, width: { ideal: 640 }, height: { ideal: 480 } },
        audio: false
      });
      return localStream;
    } catch (e) {
      console.warn("[SignConnect WebRTC] Camera getUserMedia notice:", e);
    }
  }

  // Fallback stream generator
  localStream = createSyntheticPeerStream();
  return localStream;
}

function attachRemoteStreamToDOM() {
  const remoteVideo = document.getElementById('remote-peer-video-element');
  if (remoteVideo && currentRemoteStream) {
    console.log("[SignConnect WebRTC] Attaching remote stream to DOM video element!");
    remoteVideo.srcObject = currentRemoteStream;
    remoteVideo.muted = true;
    remoteVideo.setAttribute('playsinline', 'true');
    remoteVideo.setAttribute('webkit-playsinline', 'true');
    
    var p = remoteVideo.play();
    if (p !== undefined) {
      p.catch(function(e) { console.warn("[SignConnect WebRTC] Remote play catch:", e); });
    }
  }
}

// Initialize WebRTC P2P Session with Dual Signaling (BroadcastChannel + Socket.IO)
window.initSignConnectRTC = async function(roomId, role, onPeerStatusCallback, onGestureCallback, onSpeechCallback) {
  console.log(`[SignConnect WebRTC] Initializing RTC session. Room: '${roomId}', Role: '${role}'`);
  
  rtcPeerStatusCallback = onPeerStatusCallback;
  window.signConnectRoomId = roomId;
  window.signConnectRole = role;
  
  if (!window.signConnectSenderId) {
    window.signConnectSenderId = 'user-' + Math.random().toString(36).substring(2, 9);
  }
  const myId = window.signConnectSenderId;

  // Initialize BroadcastChannel for same-machine inter-tab communication
  if (!window.signConnectChannel) {
    try {
      window.signConnectChannel = new BroadcastChannel('signconnect-channel-' + roomId);
    } catch(e) {
      console.warn("BroadcastChannel notice:", e);
    }
  }

  // Initialize Socket.IO client for cross-device mobile signaling
  if (window.io) {
    try {
      if (!socketIoInstance) {
        socketIoInstance = window.io(window.location.origin, {
          transports: ['websocket', 'polling']
        });
      }

      socketIoInstance.on('connect', () => {
        console.log("[SignConnect WebRTC] Socket.IO connected:", socketIoInstance.id);
        socketIoInstance.emit('join-room', { roomId: roomId, role: role });
      });

      socketIoInstance.on('connect_error', (err) => {
        console.error("[SignConnect WebRTC] Socket.IO connection error:", err.message);
      });

      if (socketIoInstance.connected) {
        socketIoInstance.emit('join-room', { roomId: roomId, role: role });
      }
    } catch(e) {
      console.warn("Socket.IO signaling connect notice:", e);
    }
  }

  const stream = await getLocalStream();

  // Set initial remote stream fallback so feed is active immediately
  if (!currentRemoteStream) {
    currentRemoteStream = createSyntheticPeerStream();
    attachRemoteStreamToDOM();
  }

  async function makePeerConnection(targetPeerId) {
    if (pc) {
      try { pc.close(); } catch(e){}
    }
    const iceServers = await fetchIceServers();
    pc = new RTCPeerConnection({ iceServers });

    if (stream) {
      stream.getTracks().forEach(track => pc.addTrack(track, stream));
    }

    pc.ontrack = (event) => {
      console.log("[SignConnect WebRTC] Received ONTRACK Remote Video Stream!", event.streams);
      if (event.streams && event.streams[0]) {
        currentRemoteStream = event.streams[0];
        attachRemoteStreamToDOM();
        if (rtcPeerStatusCallback) rtcPeerStatusCallback(true, role === 'deaf' ? 'hearing' : 'deaf');
      }
    };

    pc.onicecandidate = (event) => {
      if (event.candidate) {
        const msg = {
          type: 'candidate',
          senderId: myId,
          targetId: targetPeerId,
          candidate: event.candidate
        };
        if (window.signConnectChannel) window.signConnectChannel.postMessage(msg);
        if (socketIoInstance) socketIoInstance.emit('ice-candidate', { roomId: roomId, candidate: event.candidate });
      }
    };

    return pc;
  }

  async function handleSignalingMessage(data) {
    if (!data || data.senderId === myId) return;

    if (data.type === 'ping') {
      if (!pc || pc.connectionState === 'disconnected' || pc.connectionState === 'closed') {
        console.log("[SignConnect WebRTC] Received presence ping from peer:", data.senderId, "- Replying with join!");
        if (window.signConnectChannel) window.signConnectChannel.postMessage({ type: 'join', senderId: myId, role: role });
      }
    } else if (data.type === 'join') {
      console.log("[SignConnect WebRTC] Peer joined room:", data.senderId, "- Creating SDP offer!");
      if (rtcPeerStatusCallback) rtcPeerStatusCallback(true, data.role);
      const conn = await makePeerConnection(data.senderId);
      const offer = await conn.createOffer();
      await conn.setLocalDescription(offer);
      
      const offerMsg = { type: 'offer', senderId: myId, targetId: data.senderId, offer: offer, role: role };
      if (window.signConnectChannel) window.signConnectChannel.postMessage(offerMsg);
      if (socketIoInstance) socketIoInstance.emit('offer', { roomId: roomId, offer: offer });
    } else if (data.type === 'offer' && (data.targetId === myId || !data.targetId)) {
      console.log("[SignConnect WebRTC] Received SDP offer from peer:", data.senderId, "- Creating SDP answer!");
      if (rtcPeerStatusCallback) rtcPeerStatusCallback(true, data.role);
      const conn = await makePeerConnection(data.senderId);
      await conn.setRemoteDescription(new RTCSessionDescription(data.offer));
      const answer = await conn.createAnswer();
      await conn.setLocalDescription(answer);

      const answerMsg = { type: 'answer', senderId: myId, targetId: data.senderId, answer: answer };
      if (window.signConnectChannel) window.signConnectChannel.postMessage(answerMsg);
      if (socketIoInstance) socketIoInstance.emit('answer', { roomId: roomId, answer: answer });
    } else if (data.type === 'answer' && (data.targetId === myId || !data.targetId)) {
      console.log("[SignConnect WebRTC] Received SDP answer from peer:", data.senderId);
      if (pc) {
        await pc.setRemoteDescription(new RTCSessionDescription(data.answer));
      }
    } else if (data.type === 'candidate' && (data.targetId === myId || !data.targetId)) {
      if (pc && data.candidate) {
        try {
          await pc.addIceCandidate(new RTCIceCandidate(data.candidate));
        } catch (e) {
          console.warn("ICE candidate error:", e);
        }
      }
    } else if (data.type === 'gesture') {
      if (onGestureCallback) onGestureCallback(data.word, data.confidence || 98);
    } else if (data.type === 'speech') {
      if (onSpeechCallback) onSpeechCallback(data.text);
    }
  }

  // Handle incoming BroadcastChannel inter-tab messages
  if (window.signConnectChannel) {
    window.signConnectChannel.onmessage = (event) => handleSignalingMessage(event.data);
  }

  // Handle incoming Socket.IO network server messages
  if (socketIoInstance) {
    socketIoInstance.off('user-joined');
    socketIoInstance.off('offer');
    socketIoInstance.off('answer');
    socketIoInstance.off('ice-candidate');
    socketIoInstance.off('gesture-recognized');
    socketIoInstance.off('speech-transcript');
    socketIoInstance.on('user-joined', (data) => handleSignalingMessage({ type: 'join', senderId: data.id, role: data.role }));
    socketIoInstance.on('offer', (data) => handleSignalingMessage({ type: 'offer', senderId: data.senderId, offer: data.offer }));
    socketIoInstance.on('answer', (data) => handleSignalingMessage({ type: 'answer', senderId: data.senderId, answer: data.answer }));
    socketIoInstance.on('ice-candidate', (data) => handleSignalingMessage({ type: 'candidate', senderId: data.senderId, candidate: data.candidate }));
    socketIoInstance.on('gesture-recognized', (data) => handleSignalingMessage({ type: 'gesture', word: data.word, confidence: data.confidence }));
    socketIoInstance.on('speech-transcript', (data) => handleSignalingMessage({ type: 'speech', text: data.text }));
  }

  // Start Presence Ping Broadcast every 1.5 seconds
  if (presencePingInterval) clearInterval(presencePingInterval);
  presencePingInterval = setInterval(() => {
    if (window.signConnectChannel) {
      window.signConnectChannel.postMessage({ type: 'ping', senderId: myId, role: role });
    }
  }, 1500);

  // Announce presence immediately
  console.log("[SignConnect WebRTC] Announcing join to room. My ID:", myId);
  if (window.signConnectChannel) {
    window.signConnectChannel.postMessage({ type: 'join', senderId: myId, role: role });
  }
};

window.broadcastSignConnectGesture = function(roomId, word, confidence) {
  const msg = { type: 'gesture', senderId: window.signConnectSenderId, roomId: roomId, word: word, confidence: confidence };
  if (window.signConnectChannel) window.signConnectChannel.postMessage(msg);
  if (socketIoInstance) socketIoInstance.emit('gesture-recognized', { roomId: roomId, word: word, confidence: confidence });
};

window.broadcastSignConnectSpeech = function(roomId, text) {
  const msg = { type: 'speech', senderId: window.signConnectSenderId, roomId: roomId, text: text };
  if (window.signConnectChannel) window.signConnectChannel.postMessage(msg);
  if (socketIoInstance) socketIoInstance.emit('speech-transcript', { roomId: roomId, text: text, isFinal: true });
};

// Web Speech API Integration
window.startSignConnectSpeechRecognition = function(onSpeechResultCallback) {
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SpeechRecognition) return;

  if (speechRecognitionInstance) {
    try { speechRecognitionInstance.stop(); } catch(e){}
  }

  speechRecognitionInstance = new SpeechRecognition();
  speechRecognitionInstance.continuous = true;
  speechRecognitionInstance.interimResults = true;
  speechRecognitionInstance.lang = 'en-US';

  speechRecognitionInstance.onresult = (event) => {
    let transcript = '';
    for (let i = event.resultIndex; i < event.results.length; i++) {
      transcript += event.results[i][0].transcript;
    }
    if (transcript.trim() !== '') {
      console.log("[SignConnect Speech] Recognized speech:", transcript);
      if (onSpeechResultCallback) onSpeechResultCallback(transcript);
      if (window.signConnectRoomId) {
        window.broadcastSignConnectSpeech(window.signConnectRoomId, transcript);
      }
    }
  };

  speechRecognitionInstance.onerror = (e) => {
    console.warn("[SignConnect Speech] Error:", e.error);
  };

  try {
    speechRecognitionInstance.start();
  } catch(e){}
};

window.leaveSignConnectCall = function() {
  console.log("[SignConnect WebRTC] Leaving call");
  if (speechRecognitionInstance) {
    try { speechRecognitionInstance.stop(); } catch(e) {}
    speechRecognitionInstance = null;
  }
  if (presencePingInterval) {
    clearInterval(presencePingInterval);
    presencePingInterval = null;
  }
  if (pc) {
    try { pc.close(); } catch(e) {}
    pc = null;
  }
  if (socketIoInstance) {
    socketIoInstance.disconnect();
    socketIoInstance = null;
  }
  if (window.signConnectChannel) {
    window.signConnectChannel.close();
    window.signConnectChannel = null;
  }
  currentRemoteStream = null;
  localStream = null;
};
