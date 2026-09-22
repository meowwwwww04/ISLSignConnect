import os
import pickle
import numpy as np
from flask import Flask, request, jsonify
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

MODEL_DIR = os.path.expanduser("~/Desktop/islProject/models")

# Load model artifacts once at startup
with open(os.path.join(MODEL_DIR, "isl_mlp_model.pkl"), "rb") as f:
    clf = pickle.load(f)
with open(os.path.join(MODEL_DIR, "isl_scaler.pkl"), "rb") as f:
    scaler = pickle.load(f)
with open(os.path.join(MODEL_DIR, "isl_label_encoder.pkl"), "rb") as f:
    le = pickle.load(f)

print(f"Loaded model with {len(le.classes_)} classes: {list(le.classes_)}")


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


@app.route("/predict", methods=["POST"])
def predict():
    data = request.get_json()
    if not data or "landmarks" not in data:
        return jsonify({"error": "Missing 'landmarks' field"}), 400

    landmarks = data["landmarks"]  # Expected: list of hands with landmark points

    # Handle both flat array and nested hands format
    hand1_pts = None
    if isinstance(landmarks[0], list):
        # Nested: [[hand1...], [hand2...]] or [[{x,y,z}...], ...]
        flat = []
        for i, hand in enumerate(landmarks):
            if i == 0:
                hand1_pts = hand  # Keep for engineered features
            for pt in hand:
                if isinstance(pt, dict):
                    flat.extend([pt["x"], pt["y"], pt["z"]])
                else:
                    flat.extend(pt)
        # Pad to 2 hands
        while len(flat) < 126:
            flat.append(0.0)
    else:
        flat = landmarks

    if len(flat) != 126:
        return jsonify({"error": f"Expected 126 raw features, got {len(flat)}"}), 400

    # Compute engineered features from hand1
    if hand1_pts and isinstance(hand1_pts[0], dict):
        eng = extract_engineered_features(hand1_pts)
    else:
        # Reconstruct dict format from flat array
        hand1_dict = []
        for i in range(21):
            idx = i * 3
            hand1_dict.append({"x": flat[idx], "y": flat[idx+1], "z": flat[idx+2]})
        eng = extract_engineered_features(hand1_dict)

    full_vec = np.array(flat + eng, dtype=np.float32).reshape(1, -1)
    scaled = scaler.transform(full_vec)
    probs = clf.predict_proba(scaled)[0]
    pred_idx = int(np.argmax(probs))
    confidence = float(probs[pred_idx])
    word = le.inverse_transform([pred_idx])[0]

    # Top-5 predictions
    top5_idx = np.argsort(probs)[::-1][:5]
    top5 = [
        {"word": le.inverse_transform([i])[0], "confidence": round(float(probs[i]), 4)}
        for i in top5_idx
    ]

    return jsonify({
        "word": word,
        "confidence": round(confidence, 4),
        "top5": top5,
    })


@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "classes": len(le.classes_)})


if __name__ == "__main__":
    print("Starting ISL Inference Server on port 5001...")
    app.run(host="0.0.0.0", port=5001, debug=False)
