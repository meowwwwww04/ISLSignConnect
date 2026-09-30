"""Honest evaluation of the ISL sign model under live-camera conditions.

The clean test split only measures "can it re-read the training photos".
Real calls add framing changes (hand further away, tilted, mirrored, one hand
missing), so every condition below re-runs the *held-out* photos through a
deterministic transform and reports:

  acc          raw top-1 accuracy
  accepted     fraction of frames the app would accept
  acc|accepted accuracy among accepted frames
  false-accept accepted frames whose word was wrong

Usage:  python3 evaluate_model.py
"""

import json
import os
import pickle

import numpy as np
from sklearn.metrics import accuracy_score, f1_score

from feature_utils import build_feature_vector

MODEL_DIR = os.path.expanduser("~/Desktop/islProject/models")
DATA_DIR = os.path.expanduser("~/Desktop/islProject/data/real_keypoints")
TEST_SIZE = 0.15
SPLIT_SEED = 42
REPLICATES = 5

# App-side acceptance rule (mirrors hand_detector_view_io.dart).
MIN_CONF = 0.45
MIN_MARGIN = 0.08
CONFIDENT_LEVEL = 0.60


def load_samples():
    samples = []
    for cls in sorted(os.listdir(DATA_DIR)):
        cls_path = os.path.join(DATA_DIR, cls)
        if not os.path.isdir(cls_path):
            continue
        for fname in sorted(os.listdir(cls_path)):
            if not fname.endswith(".json"):
                continue
            with open(os.path.join(cls_path, fname)) as f:
                d = json.load(f)
            samples.append((d["hands"][:2], cls))
    return samples


def held_out_indices(n, labels):
    """Same stratified split train_model.py uses, so nothing is trained on."""
    from sklearn.model_selection import train_test_split
    idx = np.arange(n)
    _, test_idx = train_test_split(
        idx, test_size=TEST_SIZE, stratify=np.array(labels), random_state=SPLIT_SEED
    )
    return test_idx


def transform(hands, rng, max_rot, scale_lo, scale_hi, noise, drop2_prob, mirror_prob):
    out = []
    for hand in hands:
        p = np.array([[q["x"], q["y"], q.get("z", 0.0)] for q in hand], dtype=float)
        if rng.random() < mirror_prob:
            p[:, 0] *= -1.0
        theta = rng.uniform(-np.deg2rad(max_rot), np.deg2rad(max_rot))
        c, s = np.cos(theta), np.sin(theta)
        x, y = p[:, 0] - p[0, 0], p[:, 1] - p[0, 1]
        p[:, 0] = c * x - s * y
        p[:, 1] = s * x + c * y
        p *= rng.uniform(scale_lo, scale_hi)
        p += rng.normal(0.0, noise, p.shape)
        out.append(p)
    if len(out) > 1 and rng.random() < drop2_prob:
        out = out[:1]
    return out


CONDITIONS = {
    "clean (photos as shot)": dict(verts=1, max_rot=0, scale_lo=1, scale_hi=1,
                                   noise=0, drop2_prob=0, mirror_prob=0),
    "mild framing": dict(verts=REPLICATES, max_rot=15, scale_lo=0.9, scale_hi=1.1,
                         noise=0.005, drop2_prob=0.15, mirror_prob=0.2),
    "harsh framing": dict(verts=REPLICATES, max_rot=45, scale_lo=0.7, scale_hi=1.3,
                          noise=0.02, drop2_prob=0.5, mirror_prob=0.5),
    "one hand only": dict(verts=REPLICATES, max_rot=25, scale_lo=0.8, scale_hi=1.2,
                          noise=0.01, drop2_prob=1.0, mirror_prob=0.3),
}


def accepted(conf, second):
    if conf < MIN_CONF:
        return False
    if conf < CONFIDENT_LEVEL and (conf - second) < MIN_MARGIN:
        return False
    return True


def main():
    with open(os.path.join(MODEL_DIR, "isl_mlp_model.pkl"), "rb") as f:
        clf = pickle.load(f)
    with open(os.path.join(MODEL_DIR, "isl_scaler.pkl"), "rb") as f:
        scaler = pickle.load(f)
    with open(os.path.join(MODEL_DIR, "isl_label_encoder.pkl"), "rb") as f:
        le = pickle.load(f)
    with open(os.path.join(MODEL_DIR, "isl_feature_config.pkl"), "rb") as f:
        cfg = pickle.load(f)

    samples = load_samples()
    labels = [c for _, c in samples]
    test_idx = held_out_indices(len(samples), labels)
    print(f"Model pipeline v{cfg.get('version', 1)} | {len(le.classes_)} classes | "
          f"{len(samples)} photos | {len(test_idx)} held out\n")

    header = f"{'condition':24s} {'acc':>7s} {'accepted':>9s} {'acc|acc':>9s} {'false-acc':>10s}"
    print(header)
    print("-" * len(header))

    for name, params in CONDITIONS.items():
        accs, acc_rates, cond_accs, false_rates = [], [], [], []
        for rep in range(max(1, params["verts"])):
            rng = np.random.default_rng(1000 + rep)
            X, y = [], []
            for i in test_idx:
                hands, cls = samples[i]
                feats = build_feature_vector(
                    hands if params["verts"] == 1 and params["max_rot"] == 0
                    else transform(hands, rng, **{k: v for k, v in params.items() if k != "verts"})
                )
                X.append(feats)
                y.append(cls)
            X = scaler.transform(np.array(X, dtype=np.float32))
            proba = clf.predict_proba(X)
            pred = le.inverse_transform(np.argmax(proba, axis=1))
            conf = proba.max(axis=1)
            second = np.sort(proba, axis=1)[:, -2]
            mask = np.array([accepted(c, s) for c, s in zip(conf, second)])
            truth = np.array(y)

            accs.append(accuracy_score(truth, pred))
            acc_rates.append(mask.mean())
            if mask.any():
                cond_accs.append(accuracy_score(truth[mask], pred[mask]))
                false_rates.append((mask & (truth != pred)).sum() / mask.sum())
            else:
                cond_accs.append(0.0)
                false_rates.append(0.0)

        print(f"{name:24s} {np.mean(accs):7.3f} {np.mean(acc_rates):9.3f} "
              f"{np.mean(cond_accs):9.3f} {np.mean(false_rates):10.3f}")

    print("\nacc = top-1 accuracy | accepted = frames the app would broadcast | "
          "false-acc = accepted-but-wrong share.")


if __name__ == "__main__":
    main()
