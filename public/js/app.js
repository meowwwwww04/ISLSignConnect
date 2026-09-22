/**
 * SignConnect — Main Application Controller
 */

let currentRole = "deaf";
let currentRoomId = "signconnect-room";
let localStream = null;
let mediaPipeHands = null;

let isMicActive = true;
let isCamActive = true;
let isSkeletonActive = true;
let isSpeechActive = true;

let gestureClassifier = null;
let signRenderer = null;
let webrtcManager = null;
let speechRecognition = null;
let speechSynthesis = window.speechSynthesis;

let detectedSignsTickerList = [];

// -------------------------------------------------------------
// Initialization
// -------------------------------------------------------------
document.addEventListener("DOMContentLoaded", () => {
  console.log("[App] SignConnect initialized");
  gestureClassifier = new ISLGestureClassifier();
  signRenderer = new ISLSignRenderer("signPlayerContainer");
  initUIEventListeners();
});

function selectRole(role) {
  currentRole = role;
  const deafCard = document.getElementById("roleDeafCard");
  const hearingCard = document.getElementById("roleHearingCard");

  if (deafCard && hearingCard) {
    if (role === "deaf") {
      deafCard.classList.add("selected");
      hearingCard.classList.remove("selected");
    } else {
      hearingCard.classList.add("selected");
      deafCard.classList.remove("selected");
    }
  }
}

function initUIEventListeners() {
  const btnJoin = document.getElementById("btnJoinRoom");
  if (btnJoin) btnJoin.addEventListener("click", joinCallRoom);

  const btnMic = document.getElementById("btnMic");
  if (btnMic) btnMic.addEventListener("click", toggleMic);

  const btnCam = document.getElementById("btnCam");
  if (btnCam) btnCam.addEventListener("click", toggleCam);

  const btnSkeleton = document.getElementById("btnSkeleton");
  if (btnSkeleton) btnSkeleton.addEventListener("click", toggleSkeleton);

  const btnSpeech = document.getElementById("btnSpeech");
  if (btnSpeech) btnSpeech.addEventListener("click", toggleSpeechSTT);

  const btnSwitchRole = document.getElementById("btnSwitchRole");
  if (btnSwitchRole) btnSwitchRole.addEventListener("click", switchRole);

  const btnLeave = document.getElementById("btnLeave");
  if (btnLeave) btnLeave.addEventListener("click", leaveCall);
}

// -------------------------------------------------------------
// Mobile Drawer & Tab Switcher
// -------------------------------------------------------------
function switchMobileTab(tabName) {
  const practiceDrawer = document.getElementById("practiceDrawer");
  const logsDrawer = document.getElementById("logsDrawer");
  const renderDrawer = document.getElementById("renderDrawer");

  const tabMainBtn = document.getElementById("tabMainBtn");
  const tabPracticeBtn = document.getElementById("tabPracticeBtn");
  const tabLogsBtn = document.getElementById("tabLogsBtn");
  const tabRenderBtn = document.getElementById("tabRenderBtn");

  [tabMainBtn, tabPracticeBtn, tabLogsBtn, tabRenderBtn].forEach(b => b && b.classList.remove("active"));
  [practiceDrawer, logsDrawer, renderDrawer].forEach(d => d && d.classList.add("hidden"));

  if (tabName === "stage") {
    if (tabMainBtn) tabMainBtn.classList.add("active");
  } else if (tabName === "practice") {
    if (tabPracticeBtn) tabPracticeBtn.classList.add("active");
    if (practiceDrawer) practiceDrawer.classList.remove("hidden");
  } else if (tabName === "logs") {
    if (tabLogsBtn) tabLogsBtn.classList.add("active");
    if (logsDrawer) logsDrawer.classList.remove("hidden");
  } else if (tabName === "render") {
    if (tabRenderBtn) tabRenderBtn.classList.add("active");
    if (renderDrawer) renderDrawer.classList.remove("hidden");
  }
}

// -------------------------------------------------------------
// Join Call Room
// -------------------------------------------------------------
async function joinCallRoom() {
  const roomIdInput = document.getElementById("inputRoomId").value.trim();
  if (roomIdInput) currentRoomId = roomIdInput;

  console.log("[App] Joining room:", currentRoomId, "as", currentRole);

  const modal = document.getElementById("joinModal");
  if (modal) modal.style.display = "none";

  const roomBadgeText = document.getElementById("roomBadgeText");
  if (roomBadgeText) roomBadgeText.textContent = currentRoomId;

  const roleBadge = document.getElementById("roleBadge");
  if (roleBadge) roleBadge.textContent = currentRole === 'deaf' ? 'Deaf User' : 'Hearing User';

  const localUserName = document.getElementById("localUserName");
  if (localUserName) localUserName.textContent = `You (${currentRole === 'deaf' ? 'Deaf Mode' : 'Hearing Mode'})`;

  // Start Camera & Microphone
  try {
    console.log("[App] Requesting camera and microphone access...");
    localStream = await navigator.mediaDevices.getUserMedia({
      video: { width: { ideal: 640 }, height: { ideal: 480 }, facingMode: "user" },
      audio: true
    });
    console.log("[App] Camera and microphone access granted");
    const localVideo = document.getElementById("localVideo");
    if (localVideo) {
      localVideo.srcObject = localStream;
    }
  } catch (err) {
    console.error("[App] Camera/Mic access error:", err.message);
    addTranscriptEntry("System", `Camera/microphone access denied: ${err.message}`);
    // Try video-only as fallback
    try {
      localStream = await navigator.mediaDevices.getUserMedia({ video: true });
      const localVideo = document.getElementById("localVideo");
      if (localVideo) localVideo.srcObject = localStream;
    } catch (e) {
      console.error("[App] Video-only fallback also failed:", e.message);
    }
  }

  // Initialize WebRTC Signaling Manager
  webrtcManager = new SignConnectWebRTC({
    role: currentRole,
    onRemoteStream: (stream) => {
      console.log("[App] Remote stream connected!");
      const remoteVideo = document.getElementById("remoteVideo");
      const placeholder = document.getElementById("remotePlaceholder");
      if (remoteVideo) {
        remoteVideo.srcObject = stream;
        remoteVideo.classList.remove("hidden");
        // Ensure audio plays for remote stream
        remoteVideo.volume = 1.0;
        remoteVideo.muted = false;
      }
      if (placeholder) placeholder.style.display = "none";
    },
    onUserJoined: (user) => {
      addTranscriptEntry("System", `Peer joined room as ${user.role}`);
      const remoteUserName = document.getElementById("remoteUserName");
      if (remoteUserName) remoteUserName.textContent = `Peer (${user.role === 'deaf' ? 'Deaf' : 'Hearing'})`;
      const placeholder = document.getElementById("remotePlaceholder");
      if (placeholder) placeholder.style.display = "none";
    },
    onUserLeft: (userId) => {
      addTranscriptEntry("System", `Peer left call`);
      const remoteVideo = document.getElementById("remoteVideo");
      if (remoteVideo) remoteVideo.srcObject = null;
      const remoteUserName = document.getElementById("remoteUserName");
      if (remoteUserName) remoteUserName.textContent = "Peer (Disconnected)";
      const placeholder = document.getElementById("remotePlaceholder");
      if (placeholder && !isSimulatedPeerActive) placeholder.style.display = "flex";
    },
    onGestureReceived: (data) => {
      addTranscriptEntry("Deaf Peer (ISL Sign)", `${data.word.toUpperCase()} (${data.confidence}%)`, "deaf");
      showGestureBanner(data.word, data.confidence);
      addSignToTicker(data.word);
      speakTTS(`Recognized sign: ${data.word}`);
    },
    onSpeechReceived: (data) => {
      updateDeafSubtitleBox(data.text);
      if (data.isFinal) {
        addTranscriptEntry("Hearing Peer (Speech)", data.text, "hearing");
        if (signRenderer) signRenderer.processSpeechText(data.text);
      }
    }
  });

  await webrtcManager.joinRoom(currentRoomId, currentRole, localStream);

  // Initialize MediaPipe Hands for ISL detection
  initMediaPipeHands();

  // Initialize Speech Recognition for hearing user
  initSpeechRecognition();

  addTranscriptEntry("System", `Joined room "${currentRoomId}" as ${currentRole}`);
}

// -------------------------------------------------------------
// MediaPipe Hands Landmark Engine
// -------------------------------------------------------------
function initMediaPipeHands() {
  const videoElement = document.getElementById("localVideo");
  const canvasElement = document.getElementById("landmarkCanvas");
  if (!canvasElement || !videoElement) return;

  const canvasCtx = canvasElement.getContext("2d");

  // Match canvas to video dimensions
  function resizeCanvas() {
    if (videoElement.videoWidth > 0) {
      canvasElement.width = videoElement.videoWidth;
      canvasElement.height = videoElement.videoHeight;
    }
  }
  videoElement.addEventListener("loadedmetadata", resizeCanvas);

  try {
    mediaPipeHands = new Hands({
      locateFile: (file) => `https://cdn.jsdelivr.net/npm/@mediapipe/hands/${file}`
    });

    mediaPipeHands.setOptions({
      maxNumHands: 2,
      modelComplexity: 1,
      minDetectionConfidence: 0.6,
      minTrackingConfidence: 0.5
    });

    mediaPipeHands.onResults(async (results) => {
      canvasCtx.save();
      canvasCtx.clearRect(0, 0, canvasElement.width, canvasElement.height);

      if (isSkeletonActive && results.multiHandLandmarks) {
        for (const landmarks of results.multiHandLandmarks) {
          drawConnectors(canvasCtx, landmarks, HAND_CONNECTIONS, { color: "#38bdf8", lineWidth: 2 });
          drawLandmarks(canvasCtx, landmarks, { color: "#f43f5e", lineWidth: 1, radius: 3 });
        }
      }
      canvasCtx.restore();

      // ISL classification on detected hands
      if (results.multiHandLandmarks && results.multiHandLandmarks.length > 0) {
        const gestureResult = await gestureClassifier.classify(results.multiHandLandmarks);

        if (gestureResult) {
          console.log("[App] ISL Gesture recognized:", gestureResult.label);
          showGestureBanner(gestureResult.label, gestureResult.confidence);
          addSignToTicker(gestureResult.label);
          addTranscriptEntry("You (ISL Sign)", `${gestureResult.label} (${gestureResult.confidence}%)`, "deaf");

          // Send to peer
          if (webrtcManager) {
            webrtcManager.sendGesture(gestureResult.word, gestureResult.confidence);
          }
        }
      }
    });

    console.log("[App] MediaPipe Hands initialized successfully");
  } catch (err) {
    console.error("[App] MediaPipe Hands initialization error:", err);
  }

  let isProcessingFrame = false;
  async function processNativeCameraFrame() {
    if (videoElement && videoElement.readyState >= 2 && mediaPipeHands && !isProcessingFrame) {
      isProcessingFrame = true;
      try {
        await mediaPipeHands.send({ image: videoElement });
      } catch (err) {
        console.warn("[App] MediaPipe frame error:", err.message);
      }
      isProcessingFrame = false;
    }
    requestAnimationFrame(processNativeCameraFrame);
  }

  requestAnimationFrame(processNativeCameraFrame);
}

// -------------------------------------------------------------
// Simulate ISL Sign (for testing / practice drawer)
// -------------------------------------------------------------
function simulateISLSign(word, label) {
  const displayLabel = label || word.toUpperCase();
  console.log("[App] Simulating ISL Sign:", word);

  showGestureBanner(displayLabel, 98);
  addSignToTicker(displayLabel);
  addTranscriptEntry("You (ISL Test)", `${displayLabel} (98%)`, "deaf");

  if (webrtcManager) {
    webrtcManager.sendGesture(word, 98);
  }

  if (signRenderer) {
    signRenderer.processSpeechText(word);
  }
}

// -------------------------------------------------------------
// Speech Recognition (Hearing Speech -> Text)
// -------------------------------------------------------------
function initSpeechRecognition() {
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (!SpeechRecognition) {
    console.warn("[App] Web Speech API not supported in this browser");
    addTranscriptEntry("System", "Speech recognition not supported in this browser. Try Chrome.");
    return;
  }

  function startRecognition() {
    if (speechRecognition) {
      try { speechRecognition.stop(); } catch(e) {}
    }

    speechRecognition = new SpeechRecognition();
    speechRecognition.continuous = true;
    speechRecognition.interimResults = true;
    speechRecognition.lang = "en-IN";

    speechRecognition.onresult = (event) => {
      let interimText = "";
      let finalText = "";

      for (let i = event.resultIndex; i < event.results.length; ++i) {
        if (event.results[i].isFinal) {
          finalText += event.results[i][0].transcript;
        } else {
          interimText += event.results[i][0].transcript;
        }
      }

      if (interimText.trim()) {
        updateDeafSubtitleBox(interimText);
        if (webrtcManager) {
          webrtcManager.sendSpeechTranscript(interimText, false);
        }
      }

      if (finalText.trim()) {
        updateDeafSubtitleBox(finalText);
        addTranscriptEntry("You (Speech)", finalText, "hearing");
        if (signRenderer) signRenderer.processSpeechText(finalText);

        if (webrtcManager) {
          webrtcManager.sendSpeechTranscript(finalText, true);
        }
      }
    };

    speechRecognition.onerror = (err) => {
      console.warn("[App] Speech recognition error:", err.error);
      if (err.error === "no-speech" || err.error === "audio-capture") {
        // Restart recognition after a brief pause
        setTimeout(() => {
          if (isSpeechActive) startRecognition();
        }, 1000);
      }
    };

    speechRecognition.onend = () => {
      console.log("[App] Speech recognition ended, restarting...");
      if (isSpeechActive) {
        setTimeout(() => startRecognition(), 500);
      }
    };

    try {
      speechRecognition.start();
      console.log("[App] Speech recognition started");
    } catch (e) {
      console.warn("[App] Could not start speech recognition:", e.message);
    }
  }

  startRecognition();
}

function updateDeafSubtitleBox(text) {
  const box = document.getElementById("deafLiveSubtitles");
  const elem = document.getElementById("subtitleText");

  if (elem) elem.textContent = `"${text}"`;
  if (box) {
    box.classList.remove("hidden");
    clearTimeout(window.subtitleTimeout);
    window.subtitleTimeout = setTimeout(() => {
      box.classList.add("hidden");
    }, 6000);
  }
}

function addSignToTicker(signLabel) {
  const container = document.getElementById("signTickerContainer");
  if (!container) return;

  detectedSignsTickerList.unshift(signLabel);
  if (detectedSignsTickerList.length > 8) detectedSignsTickerList.pop();

  container.innerHTML = detectedSignsTickerList
    .map(s => `<span class="ribbon-chip">${s}</span>`)
    .join("");
}

function speakTTS(text) {
  if (!speechSynthesis || !isSpeechActive) return;
  const utterance = new SpeechSynthesisUtterance(text);
  utterance.rate = 1.0;
  speechSynthesis.speak(utterance);
}

// -------------------------------------------------------------
// UI Controls
// -------------------------------------------------------------
function showGestureBanner(word, confidence) {
  const banner = document.getElementById("gestureBanner");
  const wordElem = document.getElementById("gestureWord");
  const confElem = document.getElementById("gestureConfidence");

  if (wordElem) wordElem.textContent = word;
  if (confElem) confElem.textContent = `${confidence}%`;
  if (banner) {
    banner.classList.remove("hidden");
    clearTimeout(window.bannerTimeout);
    window.bannerTimeout = setTimeout(() => {
      banner.classList.add("hidden");
    }, 3000);
  }
}

function addTranscriptEntry(sender, text, type = "normal") {
  const box = document.getElementById("transcriptBox");
  if (!box) return;

  const entry = document.createElement("div");
  entry.className = `transcript-entry ${type}`;

  const timeStr = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
  entry.innerHTML = `
    <div class="entry-sender">
      <span>${sender}</span>
      <span>${timeStr}</span>
    </div>
    <div class="entry-text">${text}</div>
  `;

  box.appendChild(entry);
  box.scrollTop = box.scrollHeight;
}

function toggleMic() {
  if (!localStream) return;
  isMicActive = !isMicActive;
  localStream.getAudioTracks().forEach(t => t.enabled = isMicActive);
  const btn = document.getElementById("btnMic");
  if (btn) {
    btn.classList.toggle("active", isMicActive);
    btn.innerHTML = isMicActive ? "🎙️" : "🔇";
  }
}

function toggleCam() {
  if (!localStream) return;
  isCamActive = !isCamActive;
  localStream.getVideoTracks().forEach(t => t.enabled = isCamActive);
  const btn = document.getElementById("btnCam");
  if (btn) {
    btn.classList.toggle("active", isCamActive);
    btn.innerHTML = isCamActive ? "📹" : "📷";
  }
}

function toggleSkeleton() {
  isSkeletonActive = !isSkeletonActive;
  const btn = document.getElementById("btnSkeleton");
  if (btn) btn.classList.toggle("active", isSkeletonActive);
}

function toggleSpeechSTT() {
  isSpeechActive = !isSpeechActive;
  const btn = document.getElementById("btnSpeech");
  if (btn) btn.classList.toggle("active", isSpeechActive);

  if (speechRecognition) {
    if (isSpeechActive) {
      try { speechRecognition.start(); } catch(e){}
    } else {
      try { speechRecognition.stop(); } catch(e){}
    }
  }
}

function switchRole() {
  currentRole = currentRole === "deaf" ? "hearing" : "deaf";
  selectRole(currentRole);

  const roleBadge = document.getElementById("roleBadge");
  if (roleBadge) roleBadge.textContent = currentRole === 'deaf' ? 'Deaf User' : 'Hearing User';

  const localUserName = document.getElementById("localUserName");
  if (localUserName) localUserName.textContent = `You (${currentRole === 'deaf' ? 'Deaf Mode' : 'Hearing Mode'})`;

  addTranscriptEntry("System", `Switched role to ${currentRole.toUpperCase()}`);
}

function leaveCall() {
  if (confirm("Are you sure you want to leave SignConnect?")) {
    window.location.reload();
  }
}

// -------------------------------------------------------------
// Dual Camera Layout & Feed Controls
// -------------------------------------------------------------
let isGridMode = false;
let isFeedsSwapped = false;
let isSimulatedPeerActive = false;
let peerAnimFrame = null;

function toggleLayoutMode() {
  const stage = document.getElementById("stageContainer");
  const icon = document.getElementById("layoutModeIcon");
  const label = document.getElementById("layoutModeLabel");

  if (!stage) return;
  isGridMode = !isGridMode;

  if (isGridMode) {
    stage.classList.remove("mode-pip");
    stage.classList.add("mode-grid");
    if (icon) icon.textContent = "🔲";
    if (label) label.textContent = "PIP Float View";
  } else {
    stage.classList.remove("mode-grid");
    stage.classList.add("mode-pip");
    if (icon) icon.textContent = "🖼️";
    if (label) label.textContent = "Split Grid View";
  }
}

function swapVideoFeeds() {
  const localCard = document.getElementById("localVideoCard");
  const remoteCard = document.getElementById("remoteVideoCard");
  if (!localCard || !remoteCard) return;

  isFeedsSwapped = !isFeedsSwapped;

  if (isFeedsSwapped) {
    localCard.classList.remove("primary-feed");
    localCard.classList.add("pip-feed");
    remoteCard.classList.remove("pip-feed");
    remoteCard.classList.add("primary-feed");
  } else {
    localCard.classList.remove("pip-feed");
    localCard.classList.add("primary-feed");
    remoteCard.classList.remove("primary-feed");
    remoteCard.classList.add("pip-feed");
  }
}

function toggleSimulatedPeer() {
  const simCanvas = document.getElementById("simulatedPeerCanvas");
  const placeholder = document.getElementById("remotePlaceholder");
  const remoteUserName = document.getElementById("remoteUserName");
  const label = document.getElementById("simulatePeerLabel");

  isSimulatedPeerActive = !isSimulatedPeerActive;

  if (isSimulatedPeerActive) {
    if (simCanvas) simCanvas.classList.remove("hidden");
    if (placeholder) placeholder.style.display = "none";
    if (remoteUserName) remoteUserName.textContent = "Demo Peer (2nd Camera)";
    if (label) label.textContent = "Stop Demo";
    startSimulatedPeerCanvas();
  } else {
    if (simCanvas) simCanvas.classList.add("hidden");
    if (placeholder && !webrtcManager?.remoteStream) placeholder.style.display = "flex";
    if (remoteUserName) remoteUserName.textContent = "Peer (Waiting...)";
    if (label) label.textContent = "Demo 2nd Camera";
    if (peerAnimFrame) cancelAnimationFrame(peerAnimFrame);
  }
}

function startSimulatedPeerCanvas() {
  const canvas = document.getElementById("simulatedPeerCanvas");
  if (!canvas) return;
  const ctx = canvas.getContext("2d");
  canvas.width = 400;
  canvas.height = 300;

  let angle = 0;
  function renderPeerFrame() {
    if (!isSimulatedPeerActive) return;
    angle += 0.04;

    const grad = ctx.createLinearGradient(0, 0, canvas.width, canvas.height);
    grad.addColorStop(0, "#0f172a");
    grad.addColorStop(1, "#1e293b");
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, canvas.width, canvas.height);

    ctx.strokeStyle = "rgba(56, 189, 248, 0.1)";
    ctx.lineWidth = 1;
    for (let x = 0; x < canvas.width; x += 30) {
      ctx.beginPath();
      ctx.moveTo(x, 0);
      ctx.lineTo(x, canvas.height);
      ctx.stroke();
    }

    const centerX = canvas.width / 2;
    const centerY = canvas.height / 2 + 30;

    ctx.fillStyle = "#334155";
    ctx.beginPath();
    ctx.arc(centerX, centerY + 80, 70, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = "#475569";
    ctx.beginPath();
    ctx.arc(centerX, centerY - 20, 35, 0, Math.PI * 2);
    ctx.fill();

    const hand1X = centerX - 50 + Math.sin(angle * 2) * 20;
    const hand1Y = centerY - 10 + Math.cos(angle * 2) * 15;
    const hand2X = centerX + 50 - Math.sin(angle * 2) * 20;
    const hand2Y = centerY - 10 - Math.cos(angle * 2) * 15;

    ctx.fillStyle = "#38bdf8";
    ctx.beginPath();
    ctx.arc(hand1X, hand1Y, 14, 0, Math.PI * 2);
    ctx.arc(hand2X, hand2Y, 14, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = "#f8fafc";
    ctx.font = "bold 13px sans-serif";
    ctx.textAlign = "center";
    ctx.fillText("DEMO PEER VIDEO (ISL)", centerX, 30);

    peerAnimFrame = requestAnimationFrame(renderPeerFrame);
  }

  renderPeerFrame();
}
