import os
import cv2
import pickle
import numpy as np
import mediapipe as mp
from collections import deque

MODEL_DIR = os.path.expanduser("~/Desktop/islProject/models")

# --- Load saved model, scaler, label encoder ---
with open(os.path.join(MODEL_DIR, "isl_mlp_model.pkl"), "rb") as f:
    clf = pickle.load(f)
with open(os.path.join(MODEL_DIR, "isl_scaler.pkl"), "rb") as f:
    scaler = pickle.load(f)
with open(os.path.join(MODEL_DIR, "isl_label_encoder.pkl"), "rb") as f:
    le = pickle.load(f)

# --- MediaPipe Hands setup ---
mp_hands = mp.solutions.hands
mp_draw = mp.solutions.drawing_utils
hands = mp_hands.Hands(
    static_image_mode=False,
    max_num_hands=2,
    min_detection_confidence=0.7,
    min_tracking_confidence=0.5,
)

# --- Smoothing buffer ---
PRED_BUFFER_SIZE = 5
pred_buffer = deque(maxlen=PRED_BUFFER_SIZE)


FINGER_LANDMARKS = {
    "thumb":  (1, 2, 3, 4), "index":  (5, 6, 7, 8),
    "middle": (9, 10, 11, 12), "ring":   (13, 14, 15, 16),
    "pinky":  (17, 18, 19, 20),
}

def extract_engineered_features(pts):
    features = []
    for name in ["thumb", "index", "middle", "ring", "pinky"]:
        mcp_i, pip_i, dip_i, tip_i = FINGER_LANDMARKS[name]
        mcp = np.array([pts[mcp_i]["x"], pts[mcp_i]["y"], pts[mcp_i]["z"]])
        pip = np.array([pts[pip_i]["x"], pts[pip_i]["y"], pts[pip_i]["z"]])
        dip = np.array([pts[dip_i]["x"], pts[dip_i]["y"], pts[dip_i]["z"]])
        tip = np.array([pts[tip_i]["x"], pts[tip_i]["y"], pts[tip_i]["z"]])
        v_mcp, v_dip = mcp - pip, dip - pip
        cos_a = np.clip(np.dot(v_mcp, v_dip) / (np.linalg.norm(v_mcp) * np.linalg.norm(v_dip) + 1e-8), -1, 1)
        features.append(np.degrees(np.arccos(cos_a)))
        features.append(np.linalg.norm(tip - mcp) / (np.linalg.norm(pip-mcp) + np.linalg.norm(dip-pip) + np.linalg.norm(tip-dip) + 1e-8))
    return features


def extract_landmarks(results):
    if not results.multi_hand_landmarks:
        return None

    hand_raw = []
    hand_pts_for_eng = []
    for hand_lm in results.multi_hand_landmarks:
        pts = []
        for lm in hand_lm.landmark:
            pts.extend([lm.x, lm.y, lm.z])
        hand_raw.append(pts)
        # Also keep dict format for engineered features
        hand_pts_for_eng.append([{"x": lm.x, "y": lm.y, "z": lm.z} for lm in hand_lm.landmark])

    # Pad to 2 hands
    while len(hand_raw) < 2:
        hand_raw.append([0.0] * 63)
        hand_pts_for_eng.append([{"x": 0.0, "y": 0.0, "z": 0.0}] * 21)

    # Engineered features from hand1 only
    eng = extract_engineered_features(hand_pts_for_eng[0])

    feature_vec = np.array(hand_raw[0] + hand_raw[1] + eng, dtype=np.float32).reshape(1, -1)
    return feature_vec


def smooth_prediction(label):
    pred_buffer.append(label)
    if len(pred_buffer) < 3:
        return label
    counts = {}
    for p in pred_buffer:
        counts[p] = counts.get(p, 0) + 1
    return max(counts, key=counts.get)


# --- Main loop ---
cap = cv2.VideoCapture(0)
if not cap.isOpened():
    print("Error: Cannot open webcam")
    exit(1)

print("Press 'q' to quit.")
while True:
    ret, frame = cap.read()
    if not ret:
        break

    frame = cv2.flip(frame, 1)
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    results = hands.process(rgb)

    display_text = ""
    confidence = 0.0

    if results.multi_hand_landmarks:
        feature_vec = extract_landmarks(results)
        if feature_vec is not None:
            scaled = scaler.transform(feature_vec)
            probs = clf.predict_proba(scaled)[0]
            pred_idx = np.argmax(probs)
            confidence = probs[pred_idx]
            raw_label = le.inverse_transform([pred_idx])[0]
            display_text = smooth_prediction(raw_label)

            # Draw hand landmarks
            for hand_lms in results.multi_hand_landmarks:
                mp_draw.draw_landmarks(frame, hand_lms, mp_hands.HAND_CONNECTIONS)

    # Display
    color = (0, 255, 0) if confidence > 0.7 else (0, 255, 255)
    if display_text:
        cv2.putText(frame, f"{display_text} ({confidence:.0%})", (10, 40),
                    cv2.FONT_HERSHEY_SIMPLEX, 1.2, color, 3)
    else:
        cv2.putText(frame, "No hands detected", (10, 40),
                    cv2.FONT_HERSHEY_SIMPLEX, 1.0, (0, 0, 255), 2)

    cv2.putText(frame, "Press 'q' to quit", (10, frame.shape[0] - 15),
                cv2.FONT_HERSHEY_SIMPLEX, 0.6, (200, 200, 200), 1)

    cv2.imshow("ISL Gesture Recognition", frame)
    if cv2.waitKey(1) & 0xFF == ord("q"):
        break

cap.release()
cv2.destroyAllWindows()
hands.close()
