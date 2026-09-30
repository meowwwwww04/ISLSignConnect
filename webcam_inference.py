"""Live ISL sign recognition on this machine's webcam.

Runs the exact same pipeline as the app: webcam -> MediaPipe hand landmarks ->
feature_utils.build_feature_vector -> trained MLP. Works with the current
MediaPipe (>= 1.0) Tasks API — the old `mp.solutions.hands` API no longer
exists, which made this tool silently unusable.

Usage:
    python3 webcam_inference.py                 # interactive window, press q
    python3 webcam_inference.py --frames 60     # headless smoke test + stats
    python3 webcam_inference.py --server       # send frames to inference_server.py
"""

import argparse
import json
import os
import pickle
import sys
import urllib.request
from collections import Counter, deque

import cv2
import numpy as np
import mediapipe as mp

from feature_utils import build_feature_vector

MODEL_DIR = os.path.expanduser("~/Desktop/islProject/models")
# Same model file the Android app ships (the pub package bundles it).
DEFAULT_TASK = os.path.expanduser(
    "~/.pub-cache/hosted/pub.dev/hand_landmarker-3.0.1/android/src/main/assets/hand_landmarker.task"
)
TASK_PATH = os.environ.get("HAND_LANDMARKER_TASK", DEFAULT_TASK)

# App-side acceptance rule (mirrors hand_detector_view_io.dart).
MIN_CONF = 0.45
MIN_MARGIN = 0.08
CONFIDENT_LEVEL = 0.60

with open(os.path.join(MODEL_DIR, "isl_mlp_model.pkl"), "rb") as f:
    clf = pickle.load(f)
with open(os.path.join(MODEL_DIR, "isl_scaler.pkl"), "rb") as f:
    scaler = pickle.load(f)
with open(os.path.join(MODEL_DIR, "isl_label_encoder.pkl"), "rb") as f:
    le = pickle.load(f)


def make_landmarker():
    from mediapipe.tasks import python as mp_python
    from mediapipe.tasks.python import vision
    if not os.path.exists(TASK_PATH):
        sys.exit(f"hand_landmarker.task not found: {TASK_PATH}\n"
                 f"Set HAND_LANDMARKER_TASK=/path/to/hand_landmarker.task")
    options = vision.HandLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=TASK_PATH),
        running_mode=vision.RunningMode.VIDEO,
        num_hands=2,
        min_hand_detection_confidence=0.5,
        min_tracking_confidence=0.5,
    )
    return vision.HandLandmarker.create_from_options(options)


def landmarks_to_features(result):
    """HandLandmarker result -> (2, 21, {x,y,z}) hands (second hand optional)."""
    if not result.hand_landmarks:
        return None
    hands = []
    for hand in result.hand_landmarks[:2]:
        hands.append([{"x": lm.x, "y": lm.y, "z": lm.z} for lm in hand])
    return hands


def predict(hands, use_server=False):
    """-> (word, confidence, accepted) using local model or inference_server."""
    if use_server:
        flat = []
        for hand in hands[:2]:
            for p in hand:
                flat += [p["x"], p["y"], p["z"]]
        if len(flat) < 126:
            flat += [0.0] * (126 - len(flat))
        req = urllib.request.Request(
            "http://127.0.0.1:5001/predict",
            data=json.dumps({"landmarks": flat[:126]}).encode(),
            headers={"Content-Type": "application/json"},
        )
        data = json.loads(urllib.request.urlopen(req, timeout=3).read())
        word, conf = data["word"], float(data["confidence"])
        second = float(data["top5"][1]["confidence"]) if len(data.get("top5", [])) > 1 else 0.0
    else:
        feats = build_feature_vector(hands).reshape(1, -1)
        probs = clf.predict_proba(scaler.transform(feats))[0]
        idx = int(np.argmax(probs))
        word, conf = str(le.inverse_transform([idx])[0]), float(probs[idx])
        second = float(np.sort(probs)[-2])
    accepted = conf >= MIN_CONF and (conf >= CONFIDENT_LEVEL or (conf - second) >= MIN_MARGIN)
    return word, conf, accepted


def smooth(buffer, label):
    buffer.append(label)
    if len(buffer) < 3:
        return label
    counts = Counter(buffer)
    return counts.most_common(1)[0][0]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--frames", type=int, default=0,
                        help="headless: process N frames, print stats, exit")
    parser.add_argument("--server", action="store_true",
                        help="classify through inference_server.py instead of the local model")
    args = parser.parse_args()

    cap = cv2.VideoCapture(0)
    if not cap.isOpened():
        sys.exit("Error: cannot open webcam")
    landmarker = make_landmarker()
    buffer = deque(maxlen=5)

    raw, accepted_counter, hand_frames, total = Counter(), Counter(), 0, 0
    t_prev = int(cv2.getTickCount() / cv2.getTickFrequency() * 1000)

    while True:
        ok, frame = cap.read()
        if not ok:
            break
        total += 1
        frame = cv2.flip(frame, 1)
        rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        t_prev += 33
        image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)
        result = landmarker.detect_for_video(image, t_prev)

        display, conf, is_ok = "", 0.0, False
        hands = landmarks_to_features(result)
        if hands:
            hand_frames += 1
            word, conf, is_ok = predict(hands, use_server=args.server)
            if is_ok:
                display = smooth(buffer, word)
            raw[word] += 1
            if is_ok:
                accepted_counter[word] += 1
            for lm_group in result.hand_landmarks:
                for pt in lm_group:
                    cv2.circle(frame, (int(pt.x * frame.shape[1]), int(pt.y * frame.shape[0])),
                               3, (0, 255, 0), -1)

        if not args.frames:
            color = (0, 255, 0) if is_ok else (0, 255, 255)
            text = display or ("No hands" if not hands else "uncertain…")
            if hands and not is_ok:
                text = f"{raw.most_common(1)[0][0]}? (uncertain)"
            cv2.putText(frame, f"{text} ({conf:.0%})", (10, 40),
                        cv2.FONT_HERSHEY_SIMPLEX, 1.1, color, 3)
            cv2.putText(frame, "q = quit", (10, frame.shape[0] - 15),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200, 200, 200), 2)
            cv2.imshow("ISL Gesture Recognition", frame)
            if cv2.waitKey(1) & 0xFF == ord("q"):
                break
        elif total >= args.frames:
            break

    cap.release()
    landmarker.close()
    if not args.frames:
        cv2.destroyAllWindows()
        return

    print(f"frames={total} hand_frames={hand_frames} "
          f"({'inference server' if args.server else 'local model'})")
    print("raw top-1 :", dict(raw.most_common(8)) or "no hands seen")
    print("accepted  :", dict(accepted_counter.most_common(8)) or "none")


if __name__ == "__main__":
    main()
