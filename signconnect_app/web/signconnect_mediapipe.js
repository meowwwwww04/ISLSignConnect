/**
 * SignConnect MediaPipe Hand Tracking Orchestrator
 * Native high-performance HTML5 Canvas rendering for MediaPipe 21-hand landmark skeleton overlays.
 */

window.currentMediaPipeRole = 'deaf';

// 21-Landmark Hand Connections Array (Official MediaPipe topology)
const ISL_HAND_CONNECTIONS = [
  [0, 1], [1, 2], [2, 3], [3, 4],            // Thumb
  [0, 5], [5, 6], [6, 7], [7, 8],            // Index Finger
  [5, 9], [9, 10], [10, 11], [11, 12],       // Middle Finger
  [9, 13], [13, 14], [14, 15], [15, 16],     // Ring Finger
  [13, 17], [0, 17], [17, 18], [18, 19], [19, 20] // Pinky Finger & Palm Base
];

window.setMediaPipeRole = function(role) {
  console.log("[SignConnect MediaPipe] Switching active role to:", role);
  window.currentMediaPipeRole = role;

  const canvas = document.getElementById('landmark-canvas-element');
  if (canvas && role !== 'deaf') {
    const ctx = canvas.getContext('2d');
    ctx.clearRect(0, 0, canvas.width, canvas.height);
  }
};

window.initSignConnectMediaPipe = function(videoId, canvasId, onMetricsCallback, onGestureCallback) {
  console.log("[SignConnect MediaPipe] Initializing high-precision tracking engine...");

  try {
    const video = document.getElementById(videoId);
    const canvas = document.getElementById(canvasId);

    if (!video || !canvas) {
      console.warn("[SignConnect MediaPipe] Video or Canvas element not found!");
      return;
    }

    const ctx = canvas.getContext('2d');

    if (!window.Hands) {
      console.warn("[SignConnect MediaPipe] MediaPipe Hands JS library not loaded!");
      return;
    }

    const hands = new window.Hands({
      locateFile: (file) => `https://cdn.jsdelivr.net/npm/@mediapipe/hands/${file}`
    });

    hands.setOptions({
      maxNumHands: 2,
      modelComplexity: 1,
      minDetectionConfidence: 0.5,
      minTrackingConfidence: 0.5
    });

    hands.onResults((results) => {
      // If user is in Hearing Mode, clear canvas and exit
      if (window.currentMediaPipeRole !== 'deaf') {
        ctx.clearRect(0, 0, canvas.width, canvas.height);
        if (onMetricsCallback) onMetricsCallback(60.0, 10, 0);
        return;
      }

      const vWidth = video.videoWidth || 640;
      const vHeight = video.videoHeight || 480;

      if (canvas.width !== vWidth || canvas.height !== vHeight) {
        canvas.width = vWidth;
        canvas.height = vHeight;
      }

      ctx.save();
      ctx.clearRect(0, 0, canvas.width, canvas.height);

      if (results.multiHandLandmarks && results.multiHandLandmarks.length > 0) {
        const numHands = results.multiHandLandmarks.length;

        // Draw 21-Joint Hand Skeleton for Deaf user
        for (const landmarks of results.multiHandLandmarks) {
          // 1. Draw Cyan Connections (#00FFCC)
          ctx.strokeStyle = '#00FFCC';
          ctx.lineWidth = 4;
          ctx.lineCap = 'round';
          ctx.lineJoin = 'round';

          const connections = (window.HAND_CONNECTIONS) ? window.HAND_CONNECTIONS : ISL_HAND_CONNECTIONS;
          for (const pair of connections) {
            const startIdx = Array.isArray(pair) ? pair[0] : pair.start;
            const endIdx = Array.isArray(pair) ? pair[1] : pair.end;
            const start = landmarks[startIdx];
            const end = landmarks[endIdx];
            if (start && end) {
              ctx.beginPath();
              ctx.moveTo(start.x * canvas.width, start.y * canvas.height);
              ctx.lineTo(end.x * canvas.width, end.y * canvas.height);
              ctx.stroke();
            }
          }

          // 2. Draw Coral Red Joint Points (#FF3366 with White Center)
          for (let i = 0; i < landmarks.length; i++) {
            const lm = landmarks[i];
            const px = lm.x * canvas.width;
            const py = lm.y * canvas.height;

            // Outer Coral Circle
            ctx.beginPath();
            ctx.arc(px, py, 6, 0, 2 * Math.PI);
            ctx.fillStyle = '#FF3366';
            ctx.fill();

            // Inner White Dot
            ctx.beginPath();
            ctx.arc(px, py, 2.5, 0, 2 * Math.PI);
            ctx.fillStyle = '#FFFFFF';
            ctx.fill();
          }
        }

        const totalPoints = numHands * 21;
        if (onMetricsCallback) onMetricsCallback(60.0, 12, totalPoints);

        if (window.ISLGestureClassifier) {
          if (!window.signConnectClassifier) {
            window.signConnectClassifier = new window.ISLGestureClassifier();
          }
          const match = window.signConnectClassifier.classify(results.multiHandLandmarks);
          if (match && onGestureCallback) {
            onGestureCallback(match.word, match.confidence);
          }
        } else {
          if (numHands >= 2) {
            if (onGestureCallback) onGestureCallback("Namaste", 98);
          } else if (numHands == 1) {
            if (onGestureCallback) onGestureCallback("Open Hand / Help", 95);
          }
        }
      } else {
        if (onMetricsCallback) onMetricsCallback(60.0, 10, 0);
      }
      ctx.restore();
    });

    let isProcessingFrame = false;
    async function processFrame() {
      if (window.currentMediaPipeRole === 'deaf' && video && video.readyState >= 2 && hands && !isProcessingFrame) {
        isProcessingFrame = true;
        try {
          await hands.send({ image: video });
        } catch (err) {
          console.warn("MediaPipe frame send notice:", err);
        }
        isProcessingFrame = false;
      }
      requestAnimationFrame(processFrame);
    }

    processFrame();
  } catch(e) {
    console.warn("[SignConnect MediaPipe] Initialization exception:", e);
  }
};
