import json
import os
import pickle
from collections import Counter

import numpy as np
from sklearn.metrics import accuracy_score, classification_report, confusion_matrix
from sklearn.model_selection import train_test_split
from sklearn.neural_network import MLPClassifier
from sklearn.preprocessing import LabelEncoder, StandardScaler

from feature_utils import build_feature_vector, to_xyz

DATA_DIR = os.path.expanduser("~/Desktop/islProject/data/real_keypoints")
MODEL_DIR = os.path.expanduser("~/Desktop/islProject/models")
os.makedirs(MODEL_DIR, exist_ok=True)

# --- Training-time augmentation -------------------------------------------------
# The model has to survive webcam framing: mirrored feed, hand at any position,
# size, tilt and with jittery landmarks. These transforms are applied to RAW
# landmarks before normalisation, so the classifier learns hand shape rather
# than the framing of the training photographs.
AUG_COPIES = 4          # extra samples per photo
AUG_DROP_SECOND_HAND = 0.30   # live frames often show a single hand
AUG_MAX_ROTATION_DEG = 45.0
AUG_NOISE = 0.01        # in raw (normalised-image) landmark units
RNG = np.random.default_rng(7)


def augment_hands(hands, rng):
    """Random mirror / rotation / scale / noise, applied to every hand alike."""
    flip_roll = rng.random()
    out = []
    for hand in hands:
        p = to_xyz(hand).copy()
        if flip_roll < 0.35:              # mirror + flip depth (palm <-> back)
            p[:, 0] *= -1.0
            p[:, 2] *= -1.0
        elif flip_roll < 0.60:            # mirror only (mirrored camera)
            p[:, 0] *= -1.0

        theta = rng.uniform(-np.deg2rad(AUG_MAX_ROTATION_DEG),
                            np.deg2rad(AUG_MAX_ROTATION_DEG))
        c, s = np.cos(theta), np.sin(theta)
        x, y = p[:, 0] - p[0, 0], p[:, 1] - p[0, 1]
        p[:, 0] = c * x - s * y
        p[:, 1] = s * x + c * y

        p *= rng.uniform(0.8, 1.25)
        p += rng.normal(0.0, AUG_NOISE, p.shape)
        out.append(p)
    return out


def load_samples():
    samples = []
    classes = sorted(os.listdir(DATA_DIR))
    for cls in classes:
        cls_path = os.path.join(DATA_DIR, cls)
        if not os.path.isdir(cls_path):
            continue
        for fname in sorted(os.listdir(cls_path)):
            if not fname.endswith(".json"):
                continue
            with open(os.path.join(cls_path, fname)) as f:
                d = json.load(f)
            hands = d["hands"][:2]       # hand1 + optional hand2
            samples.append((hands, cls))
    return samples


def main():
    samples = load_samples()
    print(f"Found {len(set(s[1] for s in samples))} classes, {len(samples)} samples")

    print(f"Class distribution: {dict(Counter(cls for _, cls in samples))}")

    le = LabelEncoder()
    y_encoded = le.fit_transform([cls for _, cls in samples])
    num_classes = len(le.classes_)
    print(f"Number of classes: {num_classes}")

    # Augmented copies of one photo must never straddle train and test, so the
    # split is done on the original samples first.
    photo_idx = np.arange(len(samples))
    photo_labels = y_encoded
    trainval_idx, test_idx = train_test_split(
        photo_idx, test_size=0.15, stratify=photo_labels, random_state=42
    )
    train_idx, val_idx = train_test_split(
        trainval_idx, test_size=0.176, stratify=photo_labels[trainval_idx], random_state=42
    )

    def rows_for(indices, with_aug):
        rows, labels = [], []
        for i in indices:
            hands, cls = samples[i]
            rows.append(build_feature_vector(hands))
            labels.append(cls)
            if with_aug:
                for _ in range(AUG_COPIES):
                    aug = hands
                    if len(hands) > 1 and RNG.random() < AUG_DROP_SECOND_HAND:
                        aug = hands[:1]
                    rows.append(build_feature_vector(augment_hands(aug, RNG)))
                    labels.append(cls)
        return np.array(rows, dtype=np.float32), np.array(labels)

    X_train, y_train_str = rows_for(train_idx, with_aug=True)
    X_val, y_val_str = rows_for(val_idx, with_aug=False)
    X_test, y_test_str = rows_for(test_idx, with_aug=False)
    y_train = le.transform(y_train_str)
    y_val = le.transform(y_val_str)
    y_test = le.transform(y_test_str)
    print(f"Train: {len(X_train)}, Val: {len(X_val)}, Test: {len(X_test)}")
    print(f"Feature dim: {X_train.shape[1]}")

    scaler = StandardScaler()
    X_train = scaler.fit_transform(X_train)
    X_val = scaler.transform(X_val)
    X_test = scaler.transform(X_test)

    class_counts = np.bincount(y_train)
    class_weights = len(y_train) / (num_classes * class_counts)
    sample_weights = class_weights[y_train]

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

    y_pred = clf.predict(X_test)
    acc = accuracy_score(y_test, y_pred)
    print(f"\n{'='*60}")
    print(f"TEST ACCURACY (held-out photos): {acc:.4f} ({acc*100:.2f}%)")
    print(f"{'='*60}")

    target_names = [str(c) for c in le.classes_]
    print("\nPer-class classification report:")
    print(classification_report(y_test, y_pred, target_names=target_names, digits=3))

    report_dict = classification_report(y_test, y_pred, target_names=target_names,
                                        output_dict=True)
    macro_f1 = report_dict["macro avg"]["f1-score"]
    print(f"Macro-average F1: {macro_f1:.3f}")
    print("\n--- Classes with F1 < macro_avg - 0.10 (flagged as underperforming) ---")
    flagged = False
    for cls_name in target_names:
        f1 = report_dict[cls_name]["f1-score"]
        if f1 < macro_f1 - 0.10:
            print(f"  {cls_name:25s}  F1={f1:.3f}  "
                  f"(support={int(report_dict[cls_name]['support'])})")
            flagged = True
    if not flagged:
        print("  None flagged.")
    print(f"\nConfusion matrix shape: {confusion_matrix(y_test, y_pred).shape}")

    with open(os.path.join(MODEL_DIR, "isl_mlp_model.pkl"), "wb") as f:
        pickle.dump(clf, f)
    with open(os.path.join(MODEL_DIR, "isl_scaler.pkl"), "wb") as f:
        pickle.dump(scaler, f)
    with open(os.path.join(MODEL_DIR, "isl_label_encoder.pkl"), "wb") as f:
        pickle.dump(le, f)

    feature_config = {
        "version": 2,
        "pipeline": "feature_utils.build_feature_vector",
        "raw_features": 126,
        "engineered_features": 10,
        "total_features": int(X_train.shape[1]),
        "normalise": True,
        "zero_z": True,
        "canonicalise": True,
        "augmentation": {
            "copies": AUG_COPIES,
            "drop_second_hand": AUG_DROP_SECOND_HAND,
            "max_rotation_deg": AUG_MAX_ROTATION_DEG,
            "noise": AUG_NOISE,
        },
        "classes": target_names,
    }
    with open(os.path.join(MODEL_DIR, "isl_feature_config.pkl"), "wb") as f:
        pickle.dump(feature_config, f)

    print(f"\nSaved model -> {os.path.join(MODEL_DIR, 'isl_mlp_model.pkl')}")
    print("Done.")


if __name__ == "__main__":
    main()
