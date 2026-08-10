/**
 * SignConnect — Authentic Indian Sign Language (ISLRTC Standard) Database
 */

const ISL_DATABASE = {
  // Official ISLRTC Two-Handed Manual Alphabet Definitions (A - Z)
  alphabet: {
    "a": "ISL 'A': Dominant index finger touching non-dominant THUMB tip",
    "b": "ISL 'B': Both open hands with fingertips touching forming a heart/loop",
    "c": "ISL 'C': Dominant hand curved in C-shape against horizontal non-dominant hand",
    "d": "ISL 'D': Dominant index up while non-dominant hand forms loop touching it",
    "e": "ISL 'E': Dominant index finger touching non-dominant INDEX fingertip",
    "f": "ISL 'F': Two fingers of dominant hand placed across non-dominant index",
    "g": "ISL 'G': Both fists placed together with thumbs pointing up",
    "h": "ISL 'H': Dominant open palm wiping across non-dominant open palm",
    "i": "ISL 'I': Dominant index finger touching non-dominant MIDDLE fingertip",
    "j": "ISL 'J': Dominant index tracing letter J on non-dominant palm",
    "k": "ISL 'K': Hooked dominant index finger over non-dominant index",
    "l": "ISL 'L': Dominant L-shape resting flat on non-dominant open palm",
    "m": "ISL 'M': Three fingers of dominant hand resting on non-dominant palm",
    "n": "ISL 'N': Two fingers of dominant hand resting on non-dominant palm",
    "o": "ISL 'O': Dominant index finger touching non-dominant RING fingertip",
    "p": "ISL 'P': Dominant index & thumb forming loop around upright non-dominant index",
    "q": "ISL 'Q': Dominant index & thumb forming circle placed on non-dominant palm",
    "r": "ISL 'R': Dominant index finger hooked flat across non-dominant palm",
    "s": "ISL 'S': Interlocking pinky fingers of both hands",
    "t": "ISL 'T': Dominant index finger touching inner edge of non-dominant palm",
    "u": "ISL 'U': Dominant index finger touching non-dominant PINKY fingertip",
    "v": "ISL 'V': Two index fingers crossed in V-shape",
    "w": "ISL 'W': Fingers of both hands interlocked facing each other to form W",
    "x": "ISL 'X': Index fingers of both hands crossed forming an X shape",
    "y": "ISL 'Y': Dominant index finger pointing to V-space of non-dominant hand",
    "z": "ISL 'Z': Both open palms held sideways at right angles to each other"
  },

  // Official ISL Vocabulary & Sentences
  vocabulary: {
    "namaste": {
      label: "Namaste / Hello (ISL)",
      category: "Greetings",
      description: "Both palms pressed vertically together at chest level (Anjali Mudra)",
      handCount: 2,
      vectorAnimation: "namaste"
    },
    "hello": {
      label: "Hello / Namaste (ISL)",
      category: "Greetings",
      description: "Both palms pressed together vertically near chest (Anjali Mudra)",
      handCount: 2,
      vectorAnimation: "namaste"
    },
    "thank you": {
      label: "Thank You / Dhanyawad (ISL)",
      category: "Polite Expressions",
      description: "Dominant hand touches chin/forehead and moves to non-dominant open palm",
      handCount: 2,
      vectorAnimation: "thank_you"
    },
    "thanks": {
      label: "Thank You (ISL)",
      category: "Polite Expressions",
      description: "Dominant hand touches chin and moves to non-dominant open palm",
      handCount: 2,
      vectorAnimation: "thank_you"
    },
    "help": {
      label: "Help / Sahayata (ISL)",
      category: "Assistance",
      description: "Dominant fist (or thumb up) resting on horizontal flat non-dominant palm",
      handCount: 2,
      vectorAnimation: "help"
    },
    "house": {
      label: "House / Home (ISL)",
      category: "Nouns",
      description: "Both hands form a roof shape (inverted V) with fingertips touching",
      handCount: 2,
      vectorAnimation: "house"
    },
    "home": {
      label: "House / Home (ISL)",
      category: "Nouns",
      description: "Both hands form a roof shape with fingertips touching",
      handCount: 2,
      vectorAnimation: "house"
    },
    "book": {
      label: "Book / Study (ISL)",
      category: "Education",
      description: "Palms pressed together opening outwards like a book",
      handCount: 2,
      vectorAnimation: "book"
    },
    "read": {
      label: "Read / Book (ISL)",
      category: "Education",
      description: "Palms pressed together opening like a book",
      handCount: 2,
      vectorAnimation: "book"
    },
    "food": {
      label: "Food / Eat (ISL)",
      category: "Needs",
      description: "Bunched fingertips of dominant hand tapping near mouth",
      handCount: 1,
      vectorAnimation: "eat"
    },
    "eat": {
      label: "Food / Eat (ISL)",
      category: "Needs",
      description: "Bunched fingertips tapping near mouth",
      handCount: 1,
      vectorAnimation: "eat"
    },
    "water": {
      label: "Water / Pani (ISL)",
      category: "Needs",
      description: "Cupped hand moved towards mouth",
      handCount: 1,
      vectorAnimation: "water"
    },
    "love": {
      label: "Love / Respect (ISL)",
      category: "Expressions",
      description: "Both arms crossed over chest forming an X shape",
      handCount: 2,
      vectorAnimation: "love"
    },
    "time": {
      label: "Time / Samay (ISL)",
      category: "General",
      description: "Dominant index finger tapping non-dominant wrist",
      handCount: 2,
      vectorAnimation: "time"
    },
    "yes": {
      label: "Yes / Haan (ISL)",
      category: "Responses",
      description: "Fist nodding forward or thumbs up with non-dominant palm support",
      handCount: 1,
      vectorAnimation: "yes"
    },
    "no": {
      label: "No / Nahi (ISL)",
      category: "Responses",
      description: "Index finger waving side-to-side horizontally",
      handCount: 1,
      vectorAnimation: "no"
    },
    "stop": {
      label: "Stop / Ruko (ISL)",
      category: "Commands",
      description: "Flat open palm facing forward towards recipient",
      handCount: 1,
      vectorAnimation: "stop"
    },
    "please": {
      label: "Please / Kripya (ISL)",
      category: "Polite Expressions",
      description: "Flat open palm resting over chest area",
      handCount: 1,
      vectorAnimation: "please"
    }
  }
};

if (typeof window !== "undefined") {
  window.ISL_DATABASE = ISL_DATABASE;
}
