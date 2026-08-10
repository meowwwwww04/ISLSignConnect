/**
 * SignConnect WebRTC P2P Video Call & Web Speech Recognition Engine
 * Handles 2-way WebRTC stream exchange, Web Speech-to-Text, and clean Call Termination.
 */

let pc = null;
let localStream = null;
let currentRemoteStream = null;
let rtcPeerStatusCallback = null;
let speechRecognitionInstance = null;

async function getLocalStream() {
  if (!localStream) {
    try {
      localStream = await navigator.mediaDevices.getUserMedia({ video: true, audio: true });
    } catch (e) {
      console.warn("[SignConnect WebRTC] Webcam access notice:", e);
    }
  }
  return localStream;
}

// Polling attached stream to ensure DOM element gets stream as soon as Flutter Web mounts it
function attachRemoteStreamToDOM() {
  const remoteVid = document.getElementById('remote-peer-video-element');
  if (remoteVid && currentRemoteStream) {
    if (remoteVid.srcObject !== currentRemoteStream) {
      console.log("[SignConnect WebRTC] Attaching Remote MediaStream to DOM element!");
      remoteVid.srcObject = currentRemoteStream;
      remoteVid.play().catch(e => console.warn("Remote video play notice:", e));
    }
  }
}

// Run polling every 300ms to catch Flutter Web element mounting
setInterval(attachRemoteStreamToDOM, 300);

window.initSignConnectWebRTC = async function(roomId, role, onPeerStatusCallback, onGestureCallback, onSpeechCallback) {
  console.log("[SignConnect WebRTC] Initializing 2-way call for room:", roomId, "role:", role);
  rtcPeerStatusCallback = onPeerStatusCallback;

  const myId = 'peer_' + Math.floor(Math.random() * 1000000);
  window.signConnectSenderId = myId;
  window.signConnectRoomId = roomId;

  if (window.signConnectChannel) {
    try { window.signConnectChannel.close(); } catch(e){}
  }
  window.signConnectChannel = new BroadcastChannel('signconnect_webrtc_' + roomId);

  const stream = await getLocalStream();

  // Set default fallback stream so view is never dark
  if (!currentRemoteStream) {
    currentRemoteStream = stream;
    attachRemoteStreamToDOM();
  }

  async function makePeerConnection(targetPeerId) {
    if (pc) {
      try { pc.close(); } catch(e){}
    }
    pc = new RTCPeerConnection({
      iceServers: [
        { urls: 'stun:stun.l.google.com:19302' },
        { urls: 'stun:stun1.l.google.com:19302' }
      ]
    });

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
        window.signConnectChannel.postMessage({
          type: 'candidate',
          senderId: myId,
          targetId: targetPeerId,
          candidate: event.candidate
        });
      }
    };

    return pc;
  }

  // Handle incoming signaling messages from other tabs/peers
  window.signConnectChannel.onmessage = async (event) => {
    const data = event.data;
    if (!data || data.senderId === myId) return;

    if (data.type === 'join') {
      console.log("[SignConnect WebRTC] Peer joined room:", data.senderId, "- Initiating offer!");
      if (rtcPeerStatusCallback) rtcPeerStatusCallback(true, data.role);
      const conn = await makePeerConnection(data.senderId);
      const offer = await conn.createOffer();
      await conn.setLocalDescription(offer);
      window.signConnectChannel.postMessage({
        type: 'offer',
        senderId: myId,
        targetId: data.senderId,
        offer: offer
      });
    } else if (data.type === 'offer' && data.targetId === myId) {
      console.log("[SignConnect WebRTC] Received SDP offer from peer:", data.senderId, "- Creating answer!");
      if (rtcPeerStatusCallback) rtcPeerStatusCallback(true, data.role);
      const conn = await makePeerConnection(data.senderId);
      await conn.setRemoteDescription(new RTCSessionDescription(data.offer));
      const answer = await conn.createAnswer();
      await conn.setLocalDescription(answer);
      window.signConnectChannel.postMessage({
        type: 'answer',
        senderId: myId,
        targetId: data.senderId,
        answer: answer
      });
    } else if (data.type === 'answer' && data.targetId === myId) {
      console.log("[SignConnect WebRTC] Received SDP answer from peer:", data.senderId);
      if (pc) {
        await pc.setRemoteDescription(new RTCSessionDescription(data.answer));
      }
    } else if (data.type === 'candidate' && data.targetId === myId) {
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
  };

  // Announce presence so existing tab initiates WebRTC offer
  console.log("[SignConnect WebRTC] Announcing join to room. My ID:", myId);
  window.signConnectChannel.postMessage({ type: 'join', senderId: myId, role: role });
};

window.broadcastSignConnectGesture = function(roomId, word, confidence) {
  if (window.signConnectChannel) {
    window.signConnectChannel.postMessage({
      type: 'gesture',
      senderId: window.signConnectSenderId,
      roomId: roomId,
      word: word,
      confidence: confidence
    });
  }
};

window.broadcastSignConnectSpeech = function(roomId, text) {
  if (window.signConnectChannel) {
    window.signConnectChannel.postMessage({
      type: 'speech',
      senderId: window.signConnectSenderId,
      roomId: roomId,
      text: text
    });
  }
};

// Web Speech API Integration for Hearing Person Voice Transcription
window.startSignConnectSpeechRecognition = function(onSpeechResultCallback) {
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SpeechRecognition) {
    console.warn("[SignConnect Speech] Web Speech API not supported natively in this browser.");
    return;
  }

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
    if (transcript.trim().length > 0 && onSpeechResultCallback) {
      onSpeechResultCallback(transcript);
    }
  };

  speechRecognitionInstance.onerror = (e) => {
    console.warn("[SignConnect Speech] Recognition notice:", e.error);
  };

  try {
    speechRecognitionInstance.start();
  } catch(e){}
};

// Clean Leave / End Call Handler
window.leaveSignConnectCall = function() {
  console.log("[SignConnect WebRTC] Terminating call session and releasing camera...");
  if (pc) {
    try { pc.close(); } catch(e){}
    pc = null;
  }
  if (localStream) {
    try {
      localStream.getTracks().forEach(t => t.stop());
    } catch(e){}
    localStream = null;
  }
  currentRemoteStream = null;
  if (window.signConnectChannel) {
    try { window.signConnectChannel.close(); } catch(e){}
  }
  if (speechRecognitionInstance) {
    try { speechRecognitionInstance.stop(); } catch(e){}
  }
};
