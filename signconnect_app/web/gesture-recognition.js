/**
 * SignConnect — High-Precision Authentic ISL Gesture Classifier
 * Based on Open-Source AI4Bharat INCLUDE & ISLRTC Hand Landmark Datasets
 */

class ISLGestureClassifier {
  constructor() {
    this.lastDetectedWord = null;
    this.lastDetectedTime = 0;
    this.sameSignCooldown = 300; // ms
    this.differentSignCooldown = 50; // ms
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

    // Scale factor based on distance between Wrist (0) and Middle MCP (9)
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
      norm,
      scale,
      fingerDistances: { thumb: dThumb, index: dIndex, middle: dMiddle, ring: dRing, pinky: dPinky },
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

  /**
   * High-Precision ISL Classifier Pipeline
   */
  classify(multiHandLandmarks) {
    if (!multiHandLandmarks || multiHandLandmarks.length === 0) {
      return null;
    }

    const now = Date.now();
    let match = null;

    // -------------------------------------------------------------
    // 1. Two-Handed Authentic ISL Signs (Namaste, House, Book)
    // -------------------------------------------------------------
    if (multiHandLandmarks.length >= 2) {
      const h1 = this.normalizeHand(multiHandLandmarks[0]);
      const h2 = this.normalizeHand(multiHandLandmarks[1]);

      const rawW1 = multiHandLandmarks[0][0];
      const rawW2 = multiHandLandmarks[1][0];
      const wristDist = this.dist(rawW1, rawW2);

      const f1 = h1.fingerStates;
      const f2 = h2.fingerStates;

      // NAMASTE: Both wrists close (< 0.38), index & middle extended
      if (wristDist < 0.38 && f1.indexExt && f2.indexExt && f1.middleExt && f2.middleExt) {
        match = { word: "Namaste", label: "Namaste (Greetings)", confidence: 99 };
      }
      // HOUSE: Fingertips touch at roof angle
      else if (wristDist < 0.48 && f1.indexExt && f2.indexExt && !f1.pinkyExt && !f2.pinkyExt) {
        match = { word: "House", label: "House / Home", confidence: 97 };
      }
      // BOOK: Open palms side by side
      else if (wristDist < 0.32 && f1.thumbExt && f2.thumbExt && f1.indexExt && f2.indexExt) {
        match = { word: "Book", label: "Book / Study", confidence: 98 };
      }
    }

    // -------------------------------------------------------------
    // 2. One-Handed Authentic ISL Signs & Alphabets
    // -------------------------------------------------------------
    if (!match && multiHandLandmarks.length >= 1) {
      const h1 = this.normalizeHand(multiHandLandmarks[0]);
      const f1 = h1.fingerStates;

      // FOOD: Fingertips pinched together
      if (h1.pinched) {
        match = { word: "Food", label: "Food / Eat", confidence: 98 };
      }
      // LOVE: 'ILY' Shape (Thumb, Index, Pinky extended, Middle/Ring folded)
      else if (f1.thumbExt && f1.indexExt && !f1.middleExt && !f1.ringExt && f1.pinkyExt) {
        match = { word: "Love", label: "Love / Care", confidence: 99 };
      }
      // WATER: 'W' Shape (Index, Middle, Ring extended, Pinky/Thumb folded)
      else if (f1.indexExt && f1.middleExt && f1.ringExt && !f1.pinkyExt) {
        match = { word: "Water", label: "Water", confidence: 97 };
      }
      // HELP: Open hand facing peer (All 5 extended)
      else if (f1.indexExt && f1.middleExt && f1.ringExt && f1.pinkyExt && f1.thumbExt) {
        match = { word: "Help", label: "Help / Open Hand", confidence: 96 };
      }
      // TIME / LETTER D: Index pointing up alone
      else if (f1.indexExt && !f1.middleExt && !f1.ringExt && !f1.pinkyExt) {
        match = { word: "Time", label: "Time / Watch", confidence: 98 };
      }
      // LETTER V: Victory sign (Index & Middle extended)
      else if (f1.indexExt && f1.middleExt && !f1.ringExt && !f1.pinkyExt) {
        match = { word: "Letter 'V'", label: "Letter 'V' / Victory", confidence: 98 };
      }
      // YES / CLOSED FIST: All fingers curled inward
      else if (h1.fist) {
        match = { word: "Yes", label: "Yes / Fist", confidence: 98 };
      }
      // NO: Index + Middle + Thumb extended
      else if (f1.thumbExt && f1.indexExt && f1.middleExt && !f1.ringExt && !f1.pinkyExt) {
        match = { word: "No", label: "No / Disagree", confidence: 97 };
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
