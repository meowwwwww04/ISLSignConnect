import json
import os
import pickle
import numpy as np
from collections import Counter
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.neural_network import MLPClassifier
from sklearn.metrics import classification_report, accuracy_score, confusion_matrix

DATA_DIR = os.path.expanduser("~/Desktop/islProject/data/real_keypoints")
MODEL_DIR = os.path.expanduser("~/Desktop/islProject/models")
os.makedirs(MODEL_DIR, exist_ok=True)

# MediaPipe hand landmark indices for each finger's MCP, PIP, DIP, TIP
FINGER_LANDMARKS = {
    "thumb":  (1, 2, 3, 4),
    "index":  (5, 6, 7, 8),
    "middle": (9, 10, 11, 12),
    "ring":   (13, 14, 15, 16),
    "pinky":  (17, 18, 19, 20),
}

def extract_engineered_features(pts):
    """Compute per-finger PIP angle and MCP-to-TIP distance ratio.
    Returns 10 features: 5 angles + 5 ratios."""
    features = []
    for name in ["thumb", "index", "middle", "ring", "pinky"]:
        mcp_i, pip_i, dip_i, tip_i = FINGER_LANDMARKS[name]
        mcp = np.array([pts[mcp_i]["x"], pts[mcp_i]["y"], pts[mcp_i]["z"]])
        pip = np.array([pts[pip_i]["x"], pts[pip_i]["y"], pts[pip_i]["z"]])
        dip = np.array([pts[dip_i]["x"], pts[dip_i]["y"], pts[dip_i]["z"]])
        tip = np.array([pts[tip_i]["x"], pts[tip_i]["y"], pts[tip_i]["z"]])

        # PIP angle: angle at PIP joint between MCP->PIP and DIP->PIP vectors
        v_mcp = mcp - pip
        v_dip = dip - pip
        cos_a = np.clip(
            np.dot(v_mcp, v_dip) / (np.linalg.norm(v_mcp) * np.linalg.norm(v_dip) + 1e-8),
            -1.0, 1.0
        )
        pip_angle = np.degrees(np.arccos(cos_a))

        # Distance ratio: straight-line MCP->TIP / sum of segment lengths
        straight_dist = np.linalg.norm(tip - mcp)
        segment_sum = np.linalg.norm(pip - mcp) + np.linalg.norm(dip - pip) + np.linalg.norm(tip - dip)
        dist_ratio = straight_dist / (segment_sum + 1e-8)

        features.extend([pip_angle, dist_ratio])
    return features

DATA_DIR = os.path.expanduser("~/Desktop/islProject/data/real_keypoints")
MODEL_DIR = os.path.expanduser("~/Desktop/islProject/models")
os.makedirs(MODEL_DIR, exist_ok=True)

# --- 1. Load data ---
X_raw = []
y_raw = []

classes = sorted(os.listdir(DATA_DIR))
print(f"Found {len(classes)} classes")

for cls in classes:
    cls_path = os.path.join(DATA_DIR, cls)
    if not os.path.isdir(cls_path):
        continue
    for fname in os.listdir(cls_path):
        if not fname.endswith(".json"):
            continue
        with open(os.path.join(cls_path, fname)) as f:
            d = json.load(f)

        # Flatten: hand1 (63) + hand2 (63) = 126 raw landmark features
        hand1 = []
        for pt in d["hands"][0]:
            hand1.extend([pt["x"], pt["y"], pt["z"]])

        hand2 = [0.0] * 63
        if d["num_hands_detected"] == 2 and len(d["hands"]) > 1:
            hand2 = []
            for pt in d["hands"][1]:
                hand2.extend([pt["x"], pt["y"], pt["z"]])

        # Engineered features: 5 PIP angles + 5 distance ratios = 10 features
        eng = extract_engineered_features(d["hands"][0])

        X_raw.append(hand1 + hand2 + eng)
        y_raw.append(cls)

X = np.array(X_raw, dtype=np.float32)
y = np.array(y_raw)

print(f"Total samples: {len(X)}, feature dim: {X.shape[1]} (126 raw + 10 engineered)")
print(f"Class distribution: {dict(Counter(y))}")

# --- 2. Encode labels ---
le = LabelEncoder()
y_encoded = le.fit_transform(y)
num_classes = len(le.classes_)
print(f"Number of classes: {num_classes}")

# --- 3. Stratified train/val/test split ---
X_trainval, X_test, y_trainval, y_test = train_test_split(
    X, y_encoded, test_size=0.15, stratify=y_encoded, random_state=42
)
X_train, X_val, y_train, y_val = train_test_split(
    X_trainval, y_trainval, test_size=0.176, stratify=y_trainval, random_state=42
)  # 0.176 of 0.85 ≈ 0.15 of total

print(f"Train: {len(X_train)}, Val: {len(X_val)}, Test: {len(X_test)}")

# --- 4. Scale features ---
scaler = StandardScaler()
X_train = scaler.fit_transform(X_train)
X_val = scaler.transform(X_val)
X_test = scaler.transform(X_test)

# --- 5. Compute class weights for imbalanced data ---
class_counts = np.bincount(y_train)
class_weights = len(y_train) / (num_classes * class_counts)
sample_weights = class_weights[y_train]

# --- 6. Train MLPClassifier (feedforward NN) ---
print("\nTraining MLPClassifier...")
clf = MLPClassifier(
    hidden_layer_sizes=(256, 128, 64),
    activation="relu",
    solver="adam",
    alpha=0.001,
    batch_size=32,
    learning_rate="adaptive",
    learning_rate_init=0.001,
    max_iter=500,
    early_stopping=True,
    validation_fraction=0.15,
    n_iter_no_change=20,
    random_state=42,
    verbose=True,
)

clf.fit(X_train, y_train, sample_weight=sample_weights)

# --- 7. Evaluate ---
y_pred = clf.predict(X_test)
acc = accuracy_score(y_test, y_pred)
print(f"\n{'='*60}")
print(f"TEST ACCURACY: {acc:.4f} ({acc*100:.2f}%)")
print(f"{'='*60}")

target_names = le.classes_
print("\nPer-class classification report:")
print(classification_report(y_test, y_pred, target_names=target_names, digits=3))

# Flag underperforming classes
report_dict = classification_report(y_test, y_pred, target_names=target_names, output_dict=True)
macro_f1 = report_dict["macro avg"]["f1-score"]
print(f"Macro-average F1: {macro_f1:.3f}")
print("\n--- Classes with F1 < macro_avg - 0.10 (flagged as underperforming) ---")
flagged = False
for cls_name in target_names:
    f1 = report_dict[cls_name]["f1-score"]
    if f1 < macro_f1 - 0.10:
        support = report_dict[cls_name]["support"]
        print(f"  {cls_name:25s}  F1={f1:.3f}  (support={int(support)})")
        flagged = True
if not flagged:
    print("  None flagged.")

# --- 8. Save model + scaler + label encoder ---
model_path = os.path.join(MODEL_DIR, "isl_mlp_model.pkl")
with open(model_path, "wb") as f:
    pickle.dump(clf, f)

scaler_path = os.path.join(MODEL_DIR, "isl_scaler.pkl")
with open(scaler_path, "wb") as f:
    pickle.dump(scaler, f)

le_path = os.path.join(MODEL_DIR, "isl_label_encoder.pkl")
with open(le_path, "wb") as f:
    pickle.dump(le, f)

# Save feature engineering config so inference can reproduce the same features
feature_config = {
    "finger_landmarks": FINGER_LANDMARKS,
    "raw_features": 126,
    "engineered_features": 10,
    "total_features": X.shape[1],
}
config_path = os.path.join(MODEL_DIR, "isl_feature_config.pkl")
with open(config_path, "wb") as f:
    pickle.dump(feature_config, f)

print(f"\nSaved model -> {model_path}")
print(f"Saved scaler -> {scaler_path}")
print(f"Saved label encoder -> {le_path}")
print(f"Saved feature config -> {config_path}")
print("Done.")
