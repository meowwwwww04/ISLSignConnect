# Backend Architecture & MediaPipe Pipeline

This document provides a technical specification of the **Backend Architecture** and the **MediaPipe Landmark Extraction Pipeline** used in the ISL (Indian Sign Language) SignConnect application.

---

## 1. Backend Architecture

The backend is built as a lightweight, event-driven Node.js server powered by Express, HTTP, and Socket.IO. It serves as both a static web server and a real-time WebSocket signaling relay for WebRTC connections and gesture/speech transmission.

### 1.1 Technology Stack

* **Runtime Environment:** Node.js
* **Web Framework:** Express.js
* **Real-time Engine:** Socket.IO (`v4.x`)
* **HTTP Server:** Node.js native `http.createServer`
* **Cross-Origin Resource Sharing (CORS):** Enabled for all origins (`*`) and methods (`GET`, `POST`)
* **Static File Serving:** Express static middleware targeting the `/public` directory

---

### 1.2 Core Components & Server Logic ([`server.js`](file:///home/yume26/Desktop/islProject/server.js))

The server entry point [`server.js`](file:///home/yume26/Desktop/islProject/server.js) initializes the Express app, attaches the HTTP server, and registers Socket.IO event listeners.

```
                    ┌─────────────────────────┐
                    │      Client Browser     │
                    └───────────┬─────────────┘
                                │ HTTP / WebSockets
                                ▼
         ┌──────────────────────────────────────────────┐
         │              Node.js HTTP Server             │
         ├──────────────────────┬───────────────────────┤
         │      Express.js      │       Socket.IO       │
         │ (Static Asset Hosting)│  (Signaling Relay)   │
         └──────────────────────┴───────────────────────┘
```

#### State Management
Room states are managed in-memory using a global dictionary object:

```javascript
const rooms = {}; 
// Structure: { roomId: [ { id: socketId, role: 'deaf' | 'hearing' }, ... ] }
```

---

### 1.3 Socket.IO Event & Signaling Protocol

The backend acts as an event router between connected peer clients (`deaf` mode and `hearing` mode).

#### Room & Connection Management
| Event Name | Direction | Payload | Description |
| :--- | :--- | :--- | :--- |
| `join-room` | Client ➔ Server | `{ roomId, role }` | Joins a room, registers user role, and broadcasts updated user list. |
| `room-participants` | Server ➔ Room | `[ { id, role }, ... ]` | Emits current participant array to all clients in the room. |
| `user-joined` | Server ➔ Room Peer | `{ id, role }` | Notifies existing room participants about the newly joined user. |
| `change-role` | Client ➔ Server | `{ roomId, role }` | Updates participant's role dynamically in room state. |
| `disconnecting` | Client ➔ Server | *(Automatic)* | Cleans up user from `rooms`, deletes empty rooms, and emits `user-left`. |
| `user-left` | Server ➔ Room | `socketId` | Alerts room participants that a peer has disconnected. |

#### WebRTC Peer-to-Peer Signaling Relay
| Event Name | Direction | Payload | Description |
| :--- | :--- | :--- | :--- |
| `offer` | Peer ➔ Server ➔ Peer | `{ roomId, offer }` | Relays WebRTC SDP offer from initiating peer to target room peer. |
| `answer` | Peer ➔ Server ➔ Peer | `{ roomId, answer }` | Relays WebRTC SDP answer back to offer sender. |
| `ice-candidate` | Peer ➔ Server ➔ Peer | `{ roomId, candidate }` | Relays ICE candidates to establish P2P media streaming. |

#### ISL & Speech Data Relay
| Event Name | Direction | Payload | Description |
| :--- | :--- | :--- | :--- |
| `gesture-recognized` | Deaf ➔ Server ➔ Hearing | `{ roomId, word, confidence }` | Relays recognized ISL sign word and confidence score to room peers. |
| `speech-transcript` | Hearing ➔ Server ➔ Deaf | `{ roomId, text, isFinal }` | Relays Speech-to-Text transcript to deaf users for real-time captions. |

---

### 1.4 Network Configuration

* **Default Port:** `5000` (configurable via environment variable `process.env.PORT`)
* **Endpoint URL:** `http://localhost:5000`

---

## 2. MediaPipe Pipeline Architecture

The application incorporates a dual MediaPipe processing architecture:
1. **Offline Python Keypoint Extraction Pipeline** for INCLUDE-50 dataset processing and model feature creation.
2. **Real-time Client-Side MediaPipe Engine** for live video feed landmark tracking and gesture classification.

```
       +-----------------------------------------------------------------+
       |                       Input Video Stream                        |
       +-----------------------------------------------------------------+
                                       |
                                       v
       +-----------------------------------------------------------------+
       |                    MediaPipe Detection Engine                   |
       |  +---------------------------+  +----------------------------+  |
       |  | Hands Detector (2 Hands)  |  | BlazePose Upper Body Pose  |  |
       |  |  21 Landmarks x 2 (x, y)  |  |   25 Landmarks (x, y)      |  |
       |  +---------------------------+  +----------------------------+  |
       +-----------------------------------------------------------------+
                                       |
                                       v
       +-----------------------------------------------------------------+
       |               Feature Vector Normalization Pipeline             |
       |           Hand1 (42)  +  Hand2 (42)  +  Pose (50)               |
       |                 --> 134-Dimensional Vector                      |
       +-----------------------------------------------------------------+
                                       |
                 +---------------------+---------------------+
                 |                                           |
                 v                                           v
  [Offline Python Dataset Processing]        [Real-time Client Classification]
     - JSON Keypoint Serialization             - Sliding Window Gesture Buffer
     - Sequence Frame Generation (30 FPS)      - Socket.IO Relay Emission
```

---

### 2.1 Python Offline Keypoint Extraction Pipeline ([`generate_keypoints.py`](file:///home/yume26/Desktop/islProject/tools/include-repo/generate_keypoints.py))

The Python pipeline extracts body and hand landmark coordinates from video files to generate normalized dataset features for model training and benchmark keypoint datasets.

#### Integrated Models & Parameters
* **Hand Detector:** `mediapipe.solutions.hands.Hands`
  * `min_detection_confidence`: `0.5`
  * `min_tracking_confidence`: `0.5`
  * Max hands tracked per frame: `2`
* **Pose Detector:** `mediapipe.solutions.pose.Pose`
  * `min_detection_confidence`: `0.5`
  * `min_tracking_confidence`: `0.5`
  * Body segment: Upper body pose landmarks (first 25 points)

#### Feature Vector Specification (134-Dimensional Vector)
Per video frame, keypoints are extracted, padded if missing, and compiled into a flat 134-element vector:

$$V_{\text{frame}} = [\text{Hand}_1 (42), \text{Hand}_2 (42), \text{Pose}_{\text{upper}} (50)]$$

| Feature Group | Landmark Count | Coordinates per Point | Vector Length | Default Padding Value |
| :--- | :--- | :--- | :--- | :--- |
| **Hand 1 Landmarks** | 21 points | $(x, y)$ normalized $[0.0, 1.0]$ | 42 | `0.0` |
| **Hand 2 Landmarks** | 21 points | $(x, y)$ normalized $[0.0, 1.0]$ | 42 | `0.0` |
| **Upper Body Pose** | 25 points | $(x, y)$ normalized $[0.0, 1.0]$ | 50 | `0.0` |
| **Total Vector** | **67 points** | **$(x, y)$ pairs** | **134** | — |

#### Processing Sequence
1. OpenCV opens video stream (`cv2.VideoCapture`).
2. Each BGR frame is converted to RGB (`cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)`).
3. Frame is passed concurrently to `hands_detector.process(rgb_frame)` and `pose_detector.process(rgb_frame)`.
4. Coordinates are extracted into standard JSON data structures and written to destination keypoint files in `data/keypoints/`.

---

### 2.2 Client-Side Real-Time MediaPipe Engine ([`app.js`](file:///home/yume26/Desktop/islProject/public/js/app.js))

The client application runs a real-time web-based MediaPipe Hands solution directly inside the browser using WebAssembly.

#### Library Configuration
* **JS Package:** `@mediapipe/hands`
* **Source CDN:** `https://cdn.jsdelivr.net/npm/@mediapipe/hands`
* **Options:**
  ```javascript
  mediaPipeHands.setOptions({
    maxNumHands: 2,
    modelComplexity: 1,
    minDetectionConfidence: 0.5,
    minTrackingConfidence: 0.5
  });
  ```

#### Real-Time Execution Loop
1. **Video Stream Input:** Local webcam stream ($640 \times 480$ @ 30 FPS) captured via `navigator.mediaDevices.getUserMedia`.
2. **Landmark Detection:** MediaPipe processes video frame and invokes `onResults(results)`.
3. **Canvas Drawing:** Landmarks and connections are rendered onto `#landmarkCanvas` using `@mediapipe/camera_utils` & `drawConnectors` / `drawLandmarks`.
4. **Gesture Classification:** Extracted 21 3D hand landmarks $(x, y, z)$ are passed into `ISLGestureClassifier.processLandmarks(landmarks)`.
5. **Real-time Socket Broadcast:** Upon recognizing a valid ISL sign with high confidence ($\ge 80\%$), the client emits the `gesture-recognized` event to the Node.js backend.
