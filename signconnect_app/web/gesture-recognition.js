/**
 * SignConnect — ML-Powered ISL Gesture Classifier
 * Calls Python inference server for 42-class MLP model prediction.
 * Falls back to rule-based classifier if server is unavailable.
 */

class ISLGestureClassifier {
  constructor() {
    this.lastDetectedWord = null;
    this.lastDetectedTime = 0;
    this.sameSignCooldown = 300;
    this.differentSignCooldown = 50;
    this.infServerUrl = window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1'
      ? 'http://localhost:5001'
      : `http://${window.location.hostname}:5001`;
    this.serverAvailable = true;
    this.pendingRequest = false;
    console.log("[ML Classifier] Inference server:", this.infServerUrl);
  }

  async classify(multiHandLandmarks) {
    if (!multiHandLandmarks || multiHandLandmarks.length === 0) {
      return null;
    }

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

    if (this.serverAvailable && !this.pendingRequest) {
      this.pendingRequest = true;
      try {
        const resp = await fetch(`${this.infServerUrl}/predict`, {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ landmarks: featureVector }),
          signal: AbortSignal.timeout(2000),
        });

        if (resp.ok) {
          const data = await resp.json();
          this.pendingRequest = false;

          const now = Date.now();
          const cooldown = (data.word === this.lastDetectedWord)
            ? this.sameSignCooldown
            : this.differentSignCooldown;

          if (now - this.lastDetectedTime > cooldown && data.confidence >= 0.60) {
            this.lastDetectedWord = data.word;
            this.lastDetectedTime = now;
            return {
              word: data.word,
              label: data.word,
              confidence: Math.round(data.confidence * 100),
            };
          }
          return null;
        }
      } catch (err) {
        console.warn("[ML Classifier] Server unreachable, falling back:", err.message);
        this.serverAvailable = false;
        setTimeout(() => { this.serverAvailable = true; }, 10000);
      }
      this.pendingRequest = false;
    }

    return this._ruleBasedFallback(multiHandLandmarks);
  }

  dist(p1, p2) {
    const dx = p1.x - p2.x;
    const dy = p1.y - p2.y;
    const dz = (p1.z || 0) - (p2.z || 0);
    return Math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  normalizeHand(hand) {
    const wrist = hand[0];
    const middleMCP = hand[9];
    const scale = Math.sqrt(
      Math.pow(middleMCP.x - wrist.x, 2) +
      Math.pow(middleMCP.y - wrist.y, 2) +
      Math.pow((middleMCP.z || 0) - (wrist.z || 0), 2)
    ) || 0.1;

    const norm = [];
    for (let i = 0; i < hand.length; i++) {
      norm.push({
        x: (hand[i].x - wrist.x) / scale,
        y: (hand[i].y - wrist.y) / scale,
        z: ((hand[i].z || 0) - (wrist.z || 0)) / scale
      });
    }

    const dThumb = this.dist(norm[0], norm[4]);
    const dIndex = this.dist(norm[0], norm[8]);
    const dMiddle = this.dist(norm[0], norm[12]);
    const dRing = this.dist(norm[0], norm[16]);
    const dPinky = this.dist(norm[0], norm[20]);
    const dThumbPinky = this.dist(norm[4], norm[17]);
    const dThumbIndexTip = this.dist(norm[4], norm[8]);

    return {
      fingerStates: {
        thumbExt: dThumbPinky > 0.95 || dThumb > 1.1,
        indexExt: dIndex > 1.25,
        middleExt: dMiddle > 1.25,
        ringExt: dRing > 1.25,
        pinkyExt: dPinky > 1.20
      },
      pinched: dThumbIndexTip < 0.40,
      fist: dIndex < 0.90 && dMiddle < 0.90 && dRing < 0.90 && dPinky < 0.90
    };
  }

  _ruleBasedFallback(multiHandLandmarks) {
    const now = Date.now();
    let match = null;

    if (multiHandLandmarks.length >= 2) {
      const h1 = this.normalizeHand(multiHandLandmarks[0]);
      const h2 = this.normalizeHand(multiHandLandmarks[1]);
      const wristDist = this.dist(multiHandLandmarks[0][0], multiHandLandmarks[1][0]);
      const f1 = h1.fingerStates;
      const f2 = h2.fingerStates;

      if (wristDist < 0.38 && f1.indexExt && f2.indexExt && f1.middleExt && f2.middleExt) {
        match = { word: "Namaste", label: "Namaste (Greetings)", confidence: 99 };
      } else if (wristDist < 0.32 && f1.thumbExt && f2.thumbExt && f1.indexExt && f2.indexExt) {
        match = { word: "Book", label: "Book / Study", confidence: 98 };
      }
    }

    if (!match && multiHandLandmarks.length >= 1) {
      const h1 = this.normalizeHand(multiHandLandmarks[0]);
      const f1 = h1.fingerStates;

      if (h1.pinched) {
        match = { word: "Food", label: "Food / Eat", confidence: 98 };
      } else if (f1.thumbExt && f1.indexExt && !f1.middleExt && !f1.ringExt && f1.pinkyExt) {
        match = { word: "Love", label: "Love / Care", confidence: 99 };
      } else if (f1.indexExt && f1.middleExt && f1.ringExt && !f1.pinkyExt) {
        match = { word: "Water", label: "Water", confidence: 97 };
      } else if (f1.indexExt && !f1.middleExt && !f1.ringExt && !f1.pinkyExt) {
        match = { word: "Time", label: "Time / Watch", confidence: 98 };
      } else if (h1.fist) {
        match = { word: "Yes", label: "Yes / Fist", confidence: 98 };
      }
    }

    if (match) {
      const cooldown = (match.word === this.lastDetectedWord) ? this.sameSignCooldown : this.differentSignCooldown;
      if (now - this.lastDetectedTime > cooldown) {
        this.lastDetectedWord = match.word;
        this.lastDetectedTime = now;
        return match;
      }
    }
    return null;
  }
}

window.ISLGestureClassifier = ISLGestureClassifier;
if (!window.islGestureClassifier) {
  window.islGestureClassifier = new ISLGestureClassifier();
}
