import os
import pickle

import numpy as np
from flask import Flask, request, jsonify
from flask_cors import CORS

from feature_utils import build_feature_vector

app = Flask(__name__)
CORS(app)

MODEL_DIR = os.path.expanduser("~/Desktop/islProject/models")

with open(os.path.join(MODEL_DIR, "isl_mlp_model.pkl"), "rb") as f:
    clf = pickle.load(f)
with open(os.path.join(MODEL_DIR, "isl_scaler.pkl"), "rb") as f:
    scaler = pickle.load(f)
with open(os.path.join(MODEL_DIR, "isl_label_encoder.pkl"), "rb") as f:
    le = pickle.load(f)
with open(os.path.join(MODEL_DIR, "isl_feature_config.pkl"), "rb") as f:
    feature_config = pickle.load(f)

CLASSES = [str(c) for c in le.classes_]
PIPELINE_VERSION = feature_config.get("version", 1) if isinstance(feature_config, dict) else 1
print(f"Loaded model v{PIPELINE_VERSION} with {len(CLASSES)} classes: {CLASSES}")


def _as_hand(obj):
    """One hand -> list of 21 points ({x,y,z} or [x,y,z]). Accepts a flat 63-list."""
    if not isinstance(obj, (list, tuple)):
        raise ValueError("hand must be a list of landmarks")
    if obj and all(isinstance(v, (int, float)) for v in obj):
        if len(obj) != 63:
            raise ValueError(f"flat hand must have 63 values, got {len(obj)}")
        return [{"x": obj[i], "y": obj[i + 1], "z": obj[i + 2]}
                for i in range(0, 63, 3)]
    if len(obj) != 21:
        raise ValueError(f"hand must have 21 landmarks, got {len(obj)}")
    return obj


def parse_hands(raw):
    """Accepted payload shapes for `landmarks`:
      - [126 numbers] or [63 numbers]                 (mobile + web clients)
      - [[{x,y,z} x21], ...]                          (explicit hands)
      - [[[x,y,z] x21], ...]
      - [[63 numbers], [63 numbers]]
    """
    if not isinstance(raw, list) or not raw:
        raise ValueError("'landmarks' must be a non-empty list")

    if isinstance(raw[0], (int, float)):
        flat = [float(v) for v in raw]
        if len(flat) % 63:
            raise ValueError(f"flat landmark list must be a multiple of 63, got {len(flat)}")
        return [_as_hand(flat[i:i + 63]) for i in range(0, len(flat), 63)]

    if isinstance(raw[0], dict):
        return [_as_hand(raw)]

    # List of something: either points of ONE hand, or a list of hands.
    if len(raw[0]) == 3 and all(isinstance(v, (int, float)) for v in raw[0]):
        return [_as_hand(raw)]
    return [_as_hand(h) for h in raw]


@app.route("/predict", methods=["POST"])
def predict():
    data = request.get_json(silent=True)
    if not data or "landmarks" not in data:
        return jsonify({"error": "Missing 'landmarks' field"}), 400

    try:
        hands = parse_hands(data["landmarks"])
        features = build_feature_vector(hands).reshape(1, -1)
    except ValueError as exc:
        return jsonify({"error": str(exc)}), 400

    scaled = scaler.transform(features)
    probs = clf.predict_proba(scaled)[0]
    pred_idx = int(np.argmax(probs))
    confidence = float(probs[pred_idx])
    word = le.inverse_transform([pred_idx])[0]

    top5_idx = np.argsort(probs)[::-1][:5]
    top5 = [
        {"word": le.inverse_transform([i])[0], "confidence": round(float(probs[i]), 4)}
        for i in top5_idx
    ]

    return jsonify({
        "word": word,
        "confidence": round(confidence, 4),
        "top5": top5,
        "model_version": PIPELINE_VERSION,
    })


@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "status": "ok",
        "classes": len(CLASSES),
        "words": CLASSES,
        "model_version": PIPELINE_VERSION,
    })


if __name__ == "__main__":
    print("Starting ISL Inference Server on port 5001...")
    app.run(host="0.0.0.0", port=5001, debug=False)
