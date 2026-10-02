/**
 * SignConnect — client-side ISL inference.
 *
 * Ports feature_utils.py (136-dim hand features) and the sklearn MLP
 * forward pass so sign recognition works in any browser without reaching
 * inference_server.py — identical weights (public/js/isl-model-data.js),
 * identical math, so results match the server to ~1e-6.
 *
 * Requires isl-model-data.js to be loaded first (sets window.__ISL_MODEL__).
 */
(function () {
  "use strict";

  const FINGER_LANDMARKS = {
    thumb: [1, 2, 3, 4],
    index: [5, 6, 7, 8],
    middle: [9, 10, 11, 12],
    ring: [13, 14, 15, 16],
    pinky: [17, 18, 19, 20],
  };
  const FINGER_ORDER = ["thumb", "index", "middle", "ring", "pinky"];

  function toXYZ(hand) {
    // hand:21 points as {x,y,z}, [x,y,z], or a flat63-list (server-style).
    if (hand.length === 63 && typeof hand[0] === "number") {
      const out = new Array(63);
      for (let i = 0; i < 63; i++) out[i] = +hand[i] || 0;
      return out;
    }
    const out = [];
    for (const p of hand) {
      if (Array.isArray(p)) out.push(+p[0] || 0, +p[1] || 0, +(p.length > 2 ? p[2] : 0) || 0);
      else out.push(+p.x || 0, +p.y || 0, +p.z || 0);
    }
    if (out.length !== 63) throw new Error("expected 21 landmarks, got " + out.length / 3);
    return out;
  }

  function canonicalise(pts) {
    // pts: flat [x,y,z]*21, already wrist-centred. Flip x when the
    // (index_mcp - wrist) x (pinky_mcp - wrist) cross product is negative.
    const w = [pts[0], pts[1]];
    const i = [pts[5 * 3], pts[5 * 3 + 1]];
    const pk = [pts[17 * 3], pts[17 * 3 + 1]];
    const cross = (i[0] - w[0]) * (pk[1] - w[1]) - (pk[0] - w[0]) * (i[1] - w[1]);
    if (cross < 0) {
      for (let k = 0; k < pts.length; k += 3) pts[k] = -pts[k];
    }
    return pts;
  }

  function normalizeHand(hand) {
    const pts = toXYZ(hand);
    // wrist (point0) to origin
    const wx = pts[0], wy = pts[1], wz = pts[2];
    for (let k = 0; k < pts.length; k += 3) {
      pts[k] -= wx; pts[k + 1] -= wy; pts[k + 2] -= wz;
    }
    // scale = wrist -> middle MCP (2D)
    let scale = Math.hypot(pts[9 * 3], pts[9 * 3 + 1]);
    if (scale < 1e-6) scale = Math.max(Math.hypot(pts[17 * 3], pts[17 * 3 + 1]), 1e-6);
    for (let k = 0; k < pts.length; k += 3) {
      pts[k] /= scale; pts[k + 1] /= scale; pts[k + 2] = 0;
    }
    return canonicalise(pts);
  }

  function norm3(x, y, z) {
    return Math.sqrt(x * x + y * y + z * z);
  }

  function engineeredFeatures(handNorm) {
    // handNorm: normalised flat [x,y,z]*21 ->10 features
    const feats = [];
    for (const name of FINGER_ORDER) {
      const [mcpI, pipI, dipI, tipI] = FINGER_LANDMARKS[name];
      const at = (i) => [handNorm[i * 3], handNorm[i * 3 + 1], handNorm[i * 3 + 2]];
      const [mcp, pip, dip, tip] = [at(mcpI), at(pipI), at(dipI), at(tipI)];
      const vm = [mcp[0] - pip[0], mcp[1] - pip[1], mcp[2] - pip[2]];
      const vd = [dip[0] - pip[0], dip[1] - pip[1], dip[2] - pip[2]];
      let cos = (vm[0] * vd[0] + vm[1] * vd[1] + vm[2] * vd[2]) /
        (norm3(...vm) * norm3(...vd) + 1e-8);
      cos = Math.min(1, Math.max(-1, cos));
      feats.push((Math.acos(cos) * 180) / Math.PI);
      const straight = norm3(tip[0] - mcp[0], tip[1] - mcp[1], tip[2] - mcp[2]);
      const segments =
        norm3(pip[0] - mcp[0], pip[1] - mcp[1], pip[2] - mcp[2]) +
        norm3(dip[0] - pip[0], dip[1] - pip[1], dip[2] - pip[2]) +
        norm3(tip[0] - dip[0], tip[1] - dip[1], tip[2] - dip[2]);
      feats.push(straight / (segments + 1e-8));
    }
    return feats;
  }

  function buildFeatureVector(hands) {
    // hands: array of raw landmark arrays (21 points each).
    // Mirrors feature_utils.build_feature_vector -> Float64Array(136),
    // with each value rounded to float32 like numpy's astype(np.float32).
    if (!hands || !hands.length) throw new Error("no hands supplied");
    const h1 = normalizeHand(hands[0]);
    let h2 = null;
    if (hands.length > 1) {
      h2 = normalizeHand(hands[1]);
      // Server leaves an all-zero second hand as zeros (single-hand payloads).
      if (!h2.some((v) => v !== 0)) h2 = null;
    }
    const raw = new Float64Array(136);
    for (let k = 0; k < 63; k++) raw[k] = Math.fround(h1[k]);
    if (h2) for (let k = 0; k < 63; k++) raw[63 + k] = Math.fround(h2[k]);
    const eng = engineeredFeatures(h1);
    for (let k = 0; k < 10; k++) raw[126 + k] = Math.fround(eng[k]);
    return raw;
  }

  function softmax(logits) {
    let max = -Infinity;
    for (const v of logits) if (v > max) max = v;
    let sum = 0;
    const out = new Float64Array(logits.length);
    for (let i = 0; i < logits.length; i++) {
      out[i] = Math.exp(logits[i] - max);
      sum += out[i];
    }
    for (let i = 0; i < out.length; i++) out[i] /= sum;
    return out;
  }

  function forward(x) {
    const M = window.__ISL_MODEL__;
    let a = Float64Array.from(x);
    // scaler
    const mean = M.scaler.mean, scale = M.scaler.scale;
    for (let i = 0; i < a.length; i++) a[i] = (a[i] - mean[i]) / scale[i];
    // hidden layers (relu) + output
    const L = M.layers;
    for (let li = 0; li < L.length; li++) {
      const { dim, w, b } = L[li];
      const [nIn, nOut] = dim;
      const out = new Float64Array(nOut);
      for (let o = 0; o < nOut; o++) {
        let s = b[o];
        for (let i = 0; i < nIn; i++) s += a[i] * w[i * nOut + o]; // w is (in,out)
        out[o] = li < L.length - 1 ? Math.max(0, s) : s;
      }
      a = out;
    }
    return M.outActivation === "softmax" ? softmax(a) : a;
  }

  function predictFromHands(hands) {
    const M = window.__ISL_MODEL__;
    if (!M) throw new Error("isl-model-data.js not loaded");
    const feats = buildFeatureVector(hands);
    const probs = forward(feats);
    let best = 0;
    for (let i = 1; i < probs.length; i++) if (probs[i] > probs[best]) best = i;
    const order = Array.from(probs.keys()).sort((a, b) => probs[b] - probs[a]).slice(0, 5);
    return {
      word: M.labels[best],
      confidence: Math.round(Number(probs[best]) * 1e4) / 1e4,
      top5: order.map((i) => ({
        word: M.labels[i],
        confidence: Math.round(Number(probs[i]) * 1e4) / 1e4,
      })),
      model_version: M.pipelineVersion,
    };
  }

  function predictFromFlat126(flat) {
    if (!flat || flat.length !== 126) throw new Error("expected126 raw values");
    const hands = [flat.slice(0, 63), flat.slice(63)];
    const anySecond = hands[1].some((v) => v !== 0);
    return predictFromHands(anySecond ? hands : [hands[0]]);
  }

  window.ISLLocalPredict = {
    ready: () => !!window.__ISL_MODEL__,
    buildFeatureVector,
    forward,
    predictFromHands,
    predictFromFlat126,
  };
})();
