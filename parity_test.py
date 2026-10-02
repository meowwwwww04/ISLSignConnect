"""Generate parity cases: python pipeline output -> /tmp/opencode/parity_cases.json"""
import json
import os
import pickle
import random
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, ROOT)
from feature_utils import build_feature_vector  # noqa: E402

with open(os.path.join(ROOT, "models", "isl_mlp_model.pkl"), "rb") as f:
    clf = pickle.load(f)
with open(os.path.join(ROOT, "models", "isl_scaler.pkl"), "rb") as f:
    scaler = pickle.load(f)
with open(os.path.join(ROOT, "models", "isl_label_encoder.pkl"), "rb") as f:
    le = pickle.load(f)

rng = random.Random(42)


def rand_hand():
    return [
        [rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-0.1, 0.1)]
        for _ in range(21)
    ]


def run(hands, flat126):
    feats = build_feature_vector(hands).reshape(1, -1)
    scaled = scaler.transform(feats)
    probs = clf.predict_proba(scaled)[0]
    top5 = probs.argsort()[::-1][:5]
    return {
        "flat126": flat126,
        "pyFeatures": [float(v) for v in feats.ravel().tolist()],
        "pyWord": str(le.inverse_transform([int(probs.argmax())])[0]),
        "pyConf": round(float(probs.max()), 4),
        "pyTop5": [str(le.inverse_transform([int(i)])[0]) for i in top5],
        "pyProbs": [float(v) for v in probs.tolist()],
    }


cases = []
for i in range(30):
    h1 = rand_hand()
    two = i % 3 != 0
    h2 = rand_hand() if two else [0.0] * 63
    flat = [v for p in h1 for v in p] + ([v for p in h2 for v in p] if two else [0.0] * 63)
    hands = [h1] + ([h2] if two else [])
    # Also cover the exact server path for single-hand payloads:
    # parse_hands keeps the zero-padded second hand; build normalises it to zeros.
    cases.append(run(hands, flat))
    if not two:
        cases.append(run([h1, [ [0.0, 0.0, 0.0] ] * 21], flat))

# Real samples from the photo dataset — these produce non-saturated,
# discriminating probabilities (random OOD hands all collapse to conf=1).
import glob

real_files = sorted(glob.glob(os.path.join(ROOT, "data", "real_keypoints", "*", "*.json")))
rng.shuffle(real_files)
for path in real_files[:15]:
    d = json.load(open(path))
    hands = d["hands"]
    flat = []
    for hi in range(2):
        if hi < len(hands):
            flat += [v for pt in hands[hi] for v in (pt["x"], pt["y"], pt.get("z", 0.0))]
        else:
            flat += [0.0] * 63
    use = hands[:2]
    if len(use) == 2 and not any(flat[63:]):
        use = use[:1]
    cases.append(run(use, flat))

out = "/tmp/opencode/parity_cases.json"
with open(out, "w") as f:
    json.dump(cases, f)
print(f"Wrote {len(cases)} cases to {out}")
