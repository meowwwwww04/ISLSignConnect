/**
 * SignConnect — ML-Powered ISL Gesture Classifier
 *
 * Wraps the Python inference server (inference_server.py) that serves the
 * 42-class MLP model. There is deliberately NO rule-based fallback: the old
 * one guessed words that are not in the model's vocabulary at all (and every
 * open hand came out as "Hello"), which is why recognition looked broken.
 *
 * A prediction is only broadcast when it is confident enough:
 *   confidence >= 0.45, and either >= 0.60 or at least 0.08 ahead of the
 *   runner-up returned by the server.
 */

class ISLGestureClassifier {
  constructor() {
    this.lastDetectedWord = null;
    this.lastDetectedTime = 0;
    this.sameSignCooldown = 900;
    this.differentSignCooldown = 350;

    // Minimum probability before a sign is accepted.
    this.minConfidence = 0.45;
    // Below confidentLevel the top guess must also beat the runner-up.
    this.minMargin = 0.08;
    this.confidentLevel = 0.60;

    // The host page can point the classifier at a remote server with
    // window.setInfServerUrl("http://192.168.1.10:5001").
    this.infServerUrl = window.__ISL_INF_SERVER_URL__
      || (window.location.hostname === "localhost" || window.location.hostname === "127.0.0.1"
        ? "http://localhost:5001"
        : `http://${window.location.hostname}:5001`);
    this.serverAvailable = true;
    this.pendingRequest = false;
    console.log("[ML Classifier] Inference server:", this.infServerUrl);
  }

  static setServerUrl(url) {
    if (!url) return;
    const inst = window.islGestureClassifier;
    if (inst) inst.infServerUrl = String(url).replace(/\/+$/, "");
    window.__ISL_INF_SERVER_URL__ = String(url).replace(/\/+$/, "");
    console.log("[ML Classifier] Inference server set to:", window.__ISL_INF_SERVER_URL__);
  }

  _accept(data) {
    const conf = Number(data.confidence) || 0;
    if (!data.word || conf < this.minConfidence) return false;
    if (conf >= this.confidentLevel) return true;
    const top5 = Array.isArray(data.top5) ? data.top5 : [];
    const second = top5.length > 1 ? Number(top5[1].confidence) || 0 : 0;
    return conf - second >= this.minMargin;
  }

  async classify(multiHandLandmarks) {
    if (!multiHandLandmarks || multiHandLandmarks.length === 0) return null;
    if (!this.serverAvailable || this.pendingRequest) return null;

    // 126-dim feature vector: hand1(63) + hand2(63, zero-padded).
    const featureVector = [];
    for (let h = 0; h < 2; h++) {
      if (h < multiHandLandmarks.length) {
        for (const pt of multiHandLandmarks[h]) {
          featureVector.push(pt.x, pt.y, pt.z || 0);
        }
      } else {
        for (let i = 0; i < 63; i++) featureVector.push(0);
      }
    }

    this.pendingRequest = true;
    try {
      const resp = await fetch(`${this.infServerUrl}/predict`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ landmarks: featureVector }),
        signal: AbortSignal.timeout(2500),
      });

      if (!resp.ok) throw new Error(`HTTP ${resp.status}`);
      const data = await resp.json();
      this.pendingRequest = false;
      this.serverAvailable = true;

      if (!this._accept(data)) return null;

      const now = Date.now();
      const cooldown = (data.word === this.lastDetectedWord)
        ? this.sameSignCooldown
        : this.differentSignCooldown;
      if (now - this.lastDetectedTime <= cooldown) return null;

      this.lastDetectedWord = data.word;
      this.lastDetectedTime = now;
      return {
        word: data.word,
        label: data.word,
        confidence: Math.round(Number(data.confidence) * 100),
      };
    } catch (err) {
      this.pendingRequest = false;
      if (this.serverAvailable) {
        console.warn("[ML Classifier] Server unreachable:", err.message,
          "— set the URL with window.setInfServerUrl(...)");
      }
      this.serverAvailable = false;
      // Probe again shortly instead of guessing silently.
      setTimeout(() => { this.serverAvailable = true; }, 5000);
      return null;
    }
  }
}

window.ISLGestureClassifier = ISLGestureClassifier;
window.setInfServerUrl = ISLGestureClassifier.setServerUrl;
if (!window.islGestureClassifier) {
  window.islGestureClassifier = new ISLGestureClassifier();
}
