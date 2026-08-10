# SignConnect ISL Translator 🤟🎙️

> **Real-Time Two-Way Indian Sign Language (ISL) Communication & WebRTC Video Call App powered by MediaPipe, Web Speech API, and Flutter.**

---

## 🌟 Key Features

- **🤟 Deaf Mode (Sign Language Recognition)**:
  - Real-time 21-joint MediaPipe hand landmark tracking and skeleton overlay (`#00FFCC` cyan lines & `#FF3366` coral red nodes).
  - Open-source ISL sign classification model trained on AI4Bharat INCLUDE & ISLRTC datasets (*Namaste, House, Book, Help, Time, Food, Water, Love, Yes, No, ISL Alphabets*).
  - Prominent live **Speech Subtitles Banner** to read text from Hearing peers.

- **🎙️ Hearing Mode (Speech-to-Text Translator)**:
  - Clean, high-quality camera feed (MediaPipe landmark skeleton automatically disabled).
  - Real-time Web Speech-to-Text (STT) voice transcription broadcasted directly to the Deaf peer's screen.
  - Interactive speech prompt chips for rapid communication.

- **🎥 Inter-Tab WebRTC 2-Way Video Calling**:
  - Dual video stage (Main view + Swappable PIP floating card).
  - WebRTC P2P signaling engine with fallback synthetic video streams.
  - Full interactive dock controls (Mute Mic, Camera Toggle, Skeleton Toggle, Swap Feeds, Switch Role, Leave Call).

---

## 📁 Repository Structure

```
ISLSignConnect/
├── signconnect_app/         # Flutter Web Frontend Application
│   ├── lib/                 # Dart Source Code (Screens, Widgets, Services, Theme)
│   ├── web/                 # Web Entry (index.html, signconnect_mediapipe.js, signconnect_webrtc.js, gesture-recognition.js)
│   └── pubspec.yaml         # Flutter Dependencies
├── public/                  # Static Web Assets & JavaScript Modules
├── tools/                   # Python Dataset Extractor & ISL Model Trainers
│   ├── fetch_isl_dataset.py # Open-Source ISL Dataset Keypoint Template Generator
│   ├── setup_dataset.py     # INCLUDE Dataset Setup Script
│   └── include-repo/        # AI4Bharat MediaPipe Keypoint Generator
├── server.js                # Express & Socket.IO Signaling Server
└── package.json             # Node.js Server Dependencies
```

---

## 🚀 Getting Started

### 1. Prerequisites
- **Flutter SDK**: [Install Flutter](https://docs.flutter.dev/get-started/install)
- **Node.js** (v18+): [Install Node.js](https://nodejs.org/)
- **Python** (v3.8+): [Install Python](https://www.python.org/)

---

### 2. Running the Flutter Web Application

```bash
cd signconnect_app
flutter pub get
flutter run -d web-server --web-port 8080
```
Open **`http://localhost:8080`** in your browser!

---

### 3. Running the Node.js Signaling Server (Optional)

```bash
npm install
npm start
```

---

### 4. Running the Open-Source ISL Dataset & Training Pipeline

```bash
python3 tools/fetch_isl_dataset.py
```

---

## 📜 License
This project is licensed under the ISC License.
