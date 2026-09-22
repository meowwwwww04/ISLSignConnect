/**
 * SignConnect — Authentic ISL Vector Sign Renderer
 */

class ISLSignRenderer {
  constructor(containerId) {
    this.container = document.getElementById(containerId);
    this.queue = [];
    this.isPlaying = false;
    this.currentSign = null;
    this.initDOM();
  }

  initDOM() {
    if (!this.container) return;

    this.container.innerHTML = `
      <div class="sign-player-card">
        <div class="sign-player-header">
          <div class="sign-player-title">
            <span class="live-dot"></span>
            <span>ISL Sign Translator (Indian Sign Language)</span>
          </div>
          <span id="signCategoryBadge" class="badge badge-primary">Idle</span>
        </div>

        <div class="sign-stage" id="signStage">
          <svg id="signSvgCanvas" viewBox="0 0 300 240" class="sign-svg">
            <defs>
              <linearGradient id="handGlow" x1="0%" y1="0%" x2="100%" y2="100%">
                <stop offset="0%" stop-color="#00f2fe" stop-opacity="0.85"/>
                <stop offset="100%" stop-color="#4facfe" stop-opacity="0.85"/>
              </linearGradient>
              <linearGradient id="leftHandGlow" x1="0%" y1="0%" x2="100%" y2="100%">
                <stop offset="0%" stop-color="#10b981" stop-opacity="0.85"/>
                <stop offset="100%" stop-color="#00f2fe" stop-opacity="0.85"/>
              </linearGradient>
              <filter id="neonGlow" x="-20%" y="-20%" width="140%" height="140%">
                <feGaussianBlur stdDeviation="3" result="blur" />
                <feComposite in="SourceGraphic" in2="blur" operator="over" />
              </filter>
            </defs>

            <!-- Backdrop lines -->
            <path d="M 0 120 L 300 120 M 150 0 L 150 240" stroke="rgba(255,255,255,0.05)" stroke-width="1" dasharray="4"/>

            <!-- Human Silhouette outline -->
            <path d="M 150 45 C 130 45 130 75 150 75 C 170 75 170 45 150 45 Z" fill="none" stroke="rgba(255,255,255,0.15)" stroke-width="2"/>
            <path d="M 100 160 C 100 110 130 90 150 90 C 170 90 200 110 200 160" fill="none" stroke="rgba(255,255,255,0.12)" stroke-width="2"/>

            <!-- Right Hand Group (Dominant) -->
            <g id="rightHandGroup" class="animated-hand">
              <path id="armPath" d="M 170 200 L 160 140" stroke="url(#handGlow)" stroke-width="6" stroke-linecap="round"/>
              <circle id="palmCircle" cx="160" cy="130" r="14" fill="url(#handGlow)" filter="url(#neonGlow)"/>
              <path id="fingerThumb" d="M 150 135 L 135 125" stroke="#00f2fe" stroke-width="4" stroke-linecap="round"/>
              <path id="fingerIndex" d="M 154 120 L 152 95" stroke="#00f2fe" stroke-width="4" stroke-linecap="round"/>
              <path id="fingerMiddle" d="M 160 118 L 160 90" stroke="#00f2fe" stroke-width="4" stroke-linecap="round"/>
              <path id="fingerRing" d="M 166 120 L 168 95" stroke="#00f2fe" stroke-width="4" stroke-linecap="round"/>
              <path id="fingerPinky" d="M 172 125 L 178 105" stroke="#00f2fe" stroke-width="4" stroke-linecap="round"/>
            </g>

            <!-- Left Hand Group (ISL Two-Handed Signs) -->
            <g id="leftHandGroup" class="animated-hand" style="opacity: 0;">
              <path id="leftArmPath" d="M 130 200 L 140 140" stroke="url(#leftHandGlow)" stroke-width="6" stroke-linecap="round"/>
              <circle id="leftPalmCircle" cx="140" cy="130" r="14" fill="url(#leftHandGlow)" filter="url(#neonGlow)"/>
              <path id="leftFingerThumb" d="M 150 135 L 165 125" stroke="#10b981" stroke-width="4" stroke-linecap="round"/>
              <path id="leftFingerIndex" d="M 146 120 L 148 95" stroke="#10b981" stroke-width="4" stroke-linecap="round"/>
              <path id="leftFingerMiddle" d="M 140 118 L 140 90" stroke="#10b981" stroke-width="4" stroke-linecap="round"/>
              <path id="leftFingerRing" d="M 134 120 L 132 95" stroke="#10b981" stroke-width="4" stroke-linecap="round"/>
              <path id="leftFingerPinky" d="M 128 125 L 122 105" stroke="#10b981" stroke-width="4" stroke-linecap="round"/>
            </g>
          </svg>

          <!-- Current Active Word Banner -->
          <div class="sign-active-word-box">
            <div id="signWordTitle" class="sign-word-title">Ready for ISL Input</div>
            <div id="signDescription" class="sign-word-desc">Spoken words convert to authentic Indian Sign Language (ISL)</div>
          </div>
        </div>

        <!-- Progress Indicator -->
        <div class="sign-progress-bar">
          <div id="signProgressFill" class="sign-progress-fill"></div>
        </div>
      </div>
    `;
  }

  /**
   * Process speech text into ISL signs and two-handed alphabet fallback
   */
  processSpeechText(text) {
    if (!text || text.trim() === "") return;

    const cleaned = text.toLowerCase().replace(/[^a-z0-9\s]/g, "").trim();
    if (!cleaned) return;

    const words = cleaned.split(/\s+/).filter(Boolean);

    // Match multi-word phrases (e.g. "thank you") before per-word lookup
    for (let i = 0; i < words.length - 1; i++) {
      const phrase = `${words[i]} ${words[i + 1]}`;
      if (ISL_DATABASE.vocabulary[phrase]) {
        this.queue.push({
          type: "vocabulary",
          key: phrase,
          data: ISL_DATABASE.vocabulary[phrase]
        });
        words.splice(i, 2, null);
        break;
      }
    }

    for (const word of words) {
      if (!word) continue;

      if (ISL_DATABASE.vocabulary[word]) {
        this.queue.push({
          type: "vocabulary",
          key: word,
          data: ISL_DATABASE.vocabulary[word]
        });
      } else {
        // Fallback: Authentic ISL Two-Handed Alphabet
        for (const char of word) {
          if (ISL_DATABASE.alphabet[char]) {
            this.queue.push({
              type: "fingerspell",
              key: char.toUpperCase(),
              desc: ISL_DATABASE.alphabet[char]
            });
          }
        }
      }
    }

    if (!this.isPlaying) {
      this.playNextInQueue();
    }
  }

  playNextInQueue() {
    if (this.queue.length === 0) {
      this.isPlaying = false;
      this.resetStage();
      return;
    }

    this.isPlaying = true;
    const item = this.queue.shift();
    this.currentSign = item;

    const wordTitle = document.getElementById("signWordTitle");
    const wordDesc = document.getElementById("signDescription");
    const categoryBadge = document.getElementById("signCategoryBadge");

    if (item.type === "vocabulary") {
      const data = item.data;
      if (wordTitle) wordTitle.textContent = data.label;
      if (wordDesc) wordDesc.textContent = data.description;
      if (categoryBadge) {
        categoryBadge.textContent = data.category;
        categoryBadge.className = "badge badge-primary";
      }

      this.animateISLVectorSign(data.vectorAnimation, 2200, () => {
        this.playNextInQueue();
      });
    } else if (item.type === "fingerspell") {
      if (wordTitle) wordTitle.textContent = `ISL Letter: ${item.key}`;
      if (wordDesc) wordDesc.textContent = item.desc;
      if (categoryBadge) {
        categoryBadge.textContent = "ISL Alphabet";
        categoryBadge.className = "badge badge-emerald";
      }

      this.animateISLFingerspell(item.key, 1400, () => {
        this.playNextInQueue();
      });
    }
  }

  /**
   * Animate Vector Graphic for authentic ISL Gestures
   */
  animateISLVectorSign(animType, duration, callback) {
    const rightHand = document.getElementById("rightHandGroup");
    const leftHand = document.getElementById("leftHandGroup");
    const progressFill = document.getElementById("signProgressFill");

    if (progressFill) {
      progressFill.style.transition = "none";
      progressFill.style.width = "0%";
      setTimeout(() => {
        progressFill.style.transition = `width ${duration}ms linear`;
        progressFill.style.width = "100%";
      }, 50);
    }

    if (rightHand) rightHand.style.transition = "transform 0.4s ease-in-out";
    if (leftHand) leftHand.style.transition = "transform 0.4s ease-in-out, opacity 0.4s ease-in-out";

    switch (animType) {
      case "namaste":
        // ISL Namaste: Both palms pressed together near chest
        rightHand.style.transform = "translate(-10px, -25px) rotate(-15deg)";
        if (leftHand) {
          leftHand.style.opacity = "1";
          leftHand.style.transform = "translate(10px, -25px) rotate(15deg)";
        }
        break;

      case "house":
        // ISL House: Roof shape (fingertips touching at angle /\)
        rightHand.style.transform = "translate(-15px, -50px) rotate(45deg)";
        if (leftHand) {
          leftHand.style.opacity = "1";
          leftHand.style.transform = "translate(15px, -50px) rotate(-45deg)";
        }
        break;

      case "book":
        // ISL Book: Flat palms opening like a book
        rightHand.style.transform = "translate(20px, -20px) rotate(30deg)";
        if (leftHand) {
          leftHand.style.opacity = "1";
          leftHand.style.transform = "translate(-20px, -20px) rotate(-30deg)";
        }
        break;

      case "love":
        // ISL Love: Arms crossed over chest in X shape
        rightHand.style.transform = "translate(-45px, -30px) rotate(-40deg)";
        if (leftHand) {
          leftHand.style.opacity = "1";
          leftHand.style.transform = "translate(45px, -30px) rotate(40deg)";
        }
        break;

      case "help":
        // ISL Help: Right fist resting on flat left palm
        rightHand.style.transform = "translate(-10px, -35px) scale(0.95)";
        if (leftHand) {
          leftHand.style.opacity = "1";
          leftHand.style.transform = "translate(0px, 0px) rotate(90deg)";
        }
        break;

      case "eat":
        // ISL Food/Eat: Bunched fingertips at mouth
        rightHand.style.transform = "translate(-10px, -60px) scale(0.9)";
        if (leftHand) leftHand.style.opacity = "0";
        break;

      case "thank_you":
        // ISL Thank You: Touch chin then move forward to left open palm
        rightHand.style.transform = "translate(0px, -55px)";
        if (leftHand) {
          leftHand.style.opacity = "1";
          leftHand.style.transform = "translate(0px, 10px)";
        }
        setTimeout(() => {
          rightHand.style.transform = "translate(0px, 0px)";
        }, 800);
        break;

      default:
        rightHand.style.transform = "translate(0px, -25px)";
        if (leftHand) leftHand.style.opacity = "0";
        break;
    }

    setTimeout(() => {
      callback();
    }, duration);
  }

  animateISLFingerspell(letter, duration, callback) {
    const rightHand = document.getElementById("rightHandGroup");
    const leftHand = document.getElementById("leftHandGroup");
    const progressFill = document.getElementById("signProgressFill");

    if (progressFill) {
      progressFill.style.transition = "none";
      progressFill.style.width = "0%";
      setTimeout(() => {
        progressFill.style.transition = `width ${duration}ms linear`;
        progressFill.style.width = "100%";
      }, 50);
    }

    // ISL Two-Handed Vowels (A, E, I, O, U)
    if (["A", "E", "I", "O", "U"].includes(letter)) {
      rightHand.style.transform = "translate(-20px, -30px)";
      if (leftHand) {
        leftHand.style.opacity = "1";
        leftHand.style.transform = "translate(20px, -30px)";
      }
    } else {
      rightHand.style.transform = "translate(0px, -20px)";
      if (leftHand) {
        leftHand.style.opacity = "1";
        leftHand.style.transform = "translate(0px, -20px) rotate(15deg)";
      }
    }

    setTimeout(() => {
      callback();
    }, duration);
  }

  resetStage() {
    const wordTitle = document.getElementById("signWordTitle");
    const wordDesc = document.getElementById("signDescription");
    const categoryBadge = document.getElementById("signCategoryBadge");
    const rightHand = document.getElementById("rightHandGroup");
    const leftHand = document.getElementById("leftHandGroup");
    const progressFill = document.getElementById("signProgressFill");

    if (wordTitle) wordTitle.textContent = "Ready for ISL Input";
    if (wordDesc) wordDesc.textContent = "Spoken words convert to authentic Indian Sign Language (ISL)";
    if (categoryBadge) {
      categoryBadge.textContent = "Idle";
      categoryBadge.className = "badge badge-primary";
    }
    if (rightHand) rightHand.style.transform = "none";
    if (leftHand) leftHand.style.opacity = "0";
    if (progressFill) progressFill.style.width = "0%";
  }
}

if (typeof window !== "undefined") {
  window.ISLSignRenderer = ISLSignRenderer;
}
