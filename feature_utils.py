"""
Shared ISL feature pipeline.

Every consumer (training, HTTP inference server, webcam tool) must build the
exact same 136-dimension vector from raw MediaPipe landmarks:

    63  raw features  - hand 1 (21 landmarks x/y/z), normalised
    63  raw features  - hand 2 (zero padded when only one hand is present)
    10  engineered    - 5 finger PIP angles + 5 MCP->TIP straightness ratios

Why normalisation matters
-------------------------
The dataset is extracted from photographs (data/real_keypoints), where the hand
occupies an arbitrary part of the frame, at an arbitrary size, mirrored, etc.
Live camera frames differ in exactly those ways. Feeding raw absolute landmark
coordinates to the classifier makes it memorise framing instead of hand shape:
measured accuracy on held-out photos was ~97%, but only ~3% once the same
photos were re-framed like a webcam feed.

`normalize_hand` removes position and scale, and `canonicalise` removes the
mirror/palm-side ambiguity, so the model only ever sees hand shape.
"""

import numpy as np

FINGER_LANDMARKS = {
    "thumb":  (1, 2, 3, 4),
    "index":  (5, 6, 7, 8),
    "middle": (9, 10, 11, 12),
    "ring":   (13, 14, 15, 16),
    "pinky":  (17, 18, 19, 20),
}

RAW_FEATURES = 126
ENGINEERED_FEATURES = 10
TOTAL_FEATURES = RAW_FEATURES + ENGINEERED_FEATURES


def to_xyz(hand):
    """Accept [[x,y,z], ...], [{x,y,z}, ...] or a flat 63-list -> (21, 3) float array."""
    pts = []
    for p in hand:
        if isinstance(p, dict):
            pts.append([p.get("x", 0.0), p.get("y", 0.0), p.get("z", 0.0)])
        else:
            vals = list(p)
            pts.append([vals[0], vals[1], vals[2] if len(vals) > 2 else 0.0])
    arr = np.asarray(pts, dtype=np.float64)
    if arr.shape != (21, 3):
        raise ValueError(f"expected 21 landmarks, got shape {arr.shape}")
    return arr


def normalize_hand(hand):
    """(21, 3) raw landmarks -> wrist-centred, scale-free, depth-free hand."""
    pts = to_xyz(hand)
    pts = pts - pts[0]                                   # wrist to origin
    scale = float(np.linalg.norm(pts[9][:2]))            # wrist -> middle MCP (2D)
    if scale < 1e-6:
        scale = max(float(np.linalg.norm(pts[17][:2])), 1e-6)
    pts = pts / scale
    pts[:, 2] = 0.0                                      # MediaPipe z is not comparable
    return canonicalise(pts)


def canonicalise(pts):
    """Flip x so every hand uses the same palm-side/chirality convention.

    The sign of (index_mcp - wrist) x (pinky_mcp - wrist) flips when a hand is
    mirrored (other hand, mirrored camera, palm vs back of hand). Flipping x
    until the sign is positive maps every sample onto one configuration, which
    removes a large amount of otherwise meaningless variation.
    """
    w, i, pk = pts[0], pts[5], pts[17]
    cross = (i[0] - w[0]) * (pk[1] - w[1]) - (pk[0] - w[0]) * (i[1] - w[1])
    if cross < 0:
        pts = pts.copy()
        pts[:, 0] *= -1.0
    return pts


def extract_engineered_features(hand):
    """10 shape features: 5 finger PIP angles (degrees) + 5 straightness ratios."""
    pts = normalize_hand(hand)
    features = []
    for name in ["thumb", "index", "middle", "ring", "pinky"]:
        mcp_i, pip_i, dip_i, tip_i = FINGER_LANDMARKS[name]
        mcp, pip, dip, tip = pts[mcp_i], pts[pip_i], pts[dip_i], pts[tip_i]
        v_mcp, v_dip = mcp - pip, dip - pip
        cos_a = np.clip(
            np.dot(v_mcp, v_dip) / (np.linalg.norm(v_mcp) * np.linalg.norm(v_dip) + 1e-8),
            -1.0, 1.0,
        )
        features.append(float(np.degrees(np.arccos(cos_a))))
        straight = np.linalg.norm(tip - mcp)
        segments = (np.linalg.norm(pip - mcp) + np.linalg.norm(dip - pip)
                    + np.linalg.norm(tip - dip))
        features.append(float(straight / (segments + 1e-8)))
    return features


def build_feature_vector(hands):
    """hands: list of raw hands (each 21 landmarks). Returns (136,) float32."""
    hands = list(hands or [])
    if not hands:
        raise ValueError("no hands supplied")

    h1 = normalize_hand(hands[0])
    h2 = normalize_hand(hands[1]) if len(hands) > 1 else np.zeros((21, 3))
    if len(hands) > 2:
        # More than two detections are noise — keep the two most relevant.
        h2 = normalize_hand(max(hands[1:], key=len))

    raw = np.concatenate([h1.ravel(), h2.ravel()])
    eng = np.asarray(extract_engineered_features(hands[0]), dtype=np.float64)
    return np.concatenate([raw, eng]).astype(np.float32)


def vector_from_flat_126(flat):
    """Convenience for clients that POST {landmarks: [126 raw values]}."""
    arr = np.asarray(flat, dtype=np.float64).ravel()
    if arr.size != RAW_FEATURES:
        raise ValueError(f"expected {RAW_FEATURES} raw features, got {arr.size}")
    hands = [arr[:63].reshape(21, 3), arr[63:].reshape(21, 3)]
    if not np.any(hands[1]):
        hands = hands[:1]
    return build_feature_vector(hands)
