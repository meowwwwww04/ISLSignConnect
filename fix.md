# SignConnect / ISL Communication App — Problems to Fix and Required Implementation

#
# App Name and Logo Requirements

## Official App Name

The application's name is:

> **SignConnect**

Please replace any existing references to **SignBridge** with **SignConnect** throughout the project, including where applicable:

- App title
- Landing page
- Navigation/header
- Dashboard
- Browser title
- Logo/branding text
- Documentation
- Any visible UI labels

## New Official Logo

The user has provided the desired logo image separately with this requirement.

**Please use the provided uploaded image as the official SignConnect app logo.**

Do not redesign, replace, or generate a different logo unless specifically requested later.

The logo should be integrated appropriately into:

- The landing/welcome page
- The app header or navigation area
- Other relevant branding locations

Please keep the logo:

- Clear and properly sized
- Proportional (do not stretch or distort it)
- Visually clean
- Consistent with the SignConnect branding

The logo should not interfere with the video call or dashboard functionality.


# Important Goal

Please **do not just create separate demo features**. The application needs to work as one integrated, real-life communication app.

The final app should allow:

- A **deaf/sign-language user** and a **hearing user** to join the same room.
- Both users to successfully connect in a live video call.
- The deaf user's **Indian Sign Language (ISL) gestures** to be detected from their live camera feed and translated into text.
- The hearing user's **speech** to be converted into text.
- The translated information to be displayed to the correct users in real time.

The implementation should be kept **simple, practical, and reliable**, rather than unnecessarily complicated.

---

# 1. Current Problems

## Problem 1: Live Video Call Does Not Work Properly

Currently, the app does not successfully create a working live video call between two different people.

For example:

1. Person A joins a room from one device.
2. Person B joins the **same room** from another device/mobile phone.
3. The users are expected to connect to each other.
4. However, the call does not properly connect.

### Required Fix

Please fix the room and signaling system so that:

- Two different devices can join the **same room ID**.
- Both users can establish a real peer-to-peer video/audio connection.
- Each user can see the other person's camera feed.
- The application should work when one person joins from a laptop and another joins from a mobile phone.
- The same room should connect the users instead of treating them as separate sessions.
- WebRTC signaling should correctly handle:
  - Room joining
  - Offers
  - Answers
  - ICE candidates
  - User connection/disconnection

Please check the existing signaling/server logic and fix any Socket.IO, WebSocket, WebRTC, CORS, room-ID, or network-related issues.

---

# 2. Hand Detection Is Currently a Separate Feature

At the moment, hand detection appears as a separate option/window.

When that option is opened:

- It opens the camera.
- It detects hands.
- It only shows **my own camera feed**.
- It is not integrated into the actual video call.

This is **not the required behavior**.

### Required Fix

Hand detection and ISL recognition must be integrated into the main communication experience.

The sign-language user should not have to:

1. Join a video call separately.
2. Open another window for hand detection.
3. Perform signs in a completely separate camera screen.

Instead:

- The sign-language user's normal live camera feed should be used for ISL detection.
- Hand detection should run while the user is participating in the communication session.
- The camera should not unnecessarily open multiple separate windows.
- The hand/sign detection should be part of the actual call/dashboard experience.

---

# 3. Current Hand Detection Only Detects Hands — It Does Not Properly Translate ISL

The current system appears to focus on detecting hand landmarks or hands.

However, the actual project requirement is:

> Detect Indian Sign Language and translate recognized signs into meaningful text.

Simply detecting that a hand exists is not enough.

### Required Implementation

The system should:

1. Capture the sign-language user's camera frames.
2. Detect hands/hand landmarks.
3. Process the landmarks or gesture information.
4. Recognize supported Indian Sign Language signs.
5. Convert the recognized sign into text.
6. Display the translated text in real time.

For the first working version, please keep the supported vocabulary practical and limited rather than trying to support every ISL sign.

For example, start with a manageable set such as:

- Hello
- Thank you
- Yes
- No
- Help
- Please
- Water
- Food
- Good
- Bad
- Stop
- How are you?

The architecture should allow more ISL signs to be added later.

### Important

Do not claim that the system translates ISL unless actual gesture/sign recognition is implemented.

Hand landmark detection alone is **not ISL translation**.

---

# 4. Required Communication Flow

The final application should work like this:

## Person A: Deaf / Sign-Language User

### Input

- Uses camera.
- Performs supported Indian Sign Language gestures.

### Processing

- Camera frames are processed for hand/sign detection.
- The recognized ISL gesture is translated into text.

### Output

The recognized text should be:

- Visible on the deaf user's dashboard as confirmation.
- Sent to and visible on the hearing user's dashboard.

Example:

**Deaf user signs:** "HELLO"

Both dashboards can show:

> Deaf User: HELLO

---

## Person B: Hearing User

### Input

- Speaks normally through the microphone.

### Processing

- Speech recognition converts the hearing person's speech into text.

### Output

The speech transcription should be:

- Visible on the hearing user's dashboard as confirmation.
- Sent to and visible on the deaf user's dashboard.

Example:

**Hearing user says:** "Hello, how are you?"

The deaf user's dashboard should show:

> Hearing User: Hello, how are you?

---

# 5. Required Dashboard Behavior

Please create a simple interface that clearly separates:

## Live Video Area

The users should be able to:

- See their own camera feed.
- See the other person's camera feed.

## Communication / Translation Area

Show the recognized messages clearly.

Example:

### Deaf / Sign User Messages

> HELLO

> THANK YOU

### Hearing User Speech

> Hello, how are you?

> I am fine.

The UI does not need to be overly advanced. A clean, functional layout is more important.

---

# 6. Important: Do Not Detect the Other Person's Hands Incorrectly

The system should clearly know whose camera feed is being processed for ISL recognition.

For the main implementation:

- ISL recognition should process the **sign-language user's local camera feed**.
- The hearing person's speech recognition should process the **hearing user's microphone**.

The remote video should primarily be used for the video call.

Avoid unnecessarily running hand detection on every video feed unless that is intentionally designed and required.

---

# 7. Recommended Simple Architecture

Please inspect the existing project first and reuse the existing structure where possible.

Avoid rebuilding the entire application unnecessarily.

A practical architecture could be:

## Frontend

- HTML/CSS/JavaScript or the framework already used in the project.
- WebRTC for video/audio.
- Socket.IO or the existing signaling mechanism for room communication.
- MediaPipe Hands or an appropriate hand-landmark solution.
- Browser speech recognition where supported, or another simple speech-to-text option.

## Backend

Use the existing backend if possible.

The backend/signaling server should handle:

- Room joining.
- User presence.
- WebRTC signaling.
- Offer forwarding.
- Answer forwarding.
- ICE candidate forwarding.
- Sending recognized text messages between users if needed.

## ISL Recognition

Keep the first version simple:

- Use MediaPipe to extract hand landmarks.
- Use a trained classifier/model or an existing suitable recognition approach to classify supported signs.
- Return the predicted sign as text.

If a complete ISL model is not currently available, implement a **small working vocabulary first** rather than pretending to support full ISL.

---

# 8. Speech-to-Text Requirements

The hearing user's speech should be converted to text in real time or near real time.

Requirements:

- Request microphone permission.
- Start speech recognition when appropriate.
- Continuously or repeatedly capture speech.
- Convert speech into text.
- Display the transcription on the hearing user's dashboard.
- Send/display the transcription on the deaf user's dashboard.

Please handle:

- Microphone permission errors.
- Unsupported browser speech recognition.
- Restarting recognition if it stops unexpectedly.

Keep the implementation simple and usable.

---

# 9. Real-Life Testing Requirements

The application must be tested in an actual two-device scenario.

Please do not consider the app complete if it only works with:

- Two tabs on the same browser.
- One local computer.
- Mock video.
- Dummy messages.

Test the following:

### Test 1: Two Devices

- Laptop joins Room A.
- Mobile phone joins Room A.
- Both users connect successfully.

### Test 2: Video

- Both users can see each other's camera feed.

### Test 3: Audio

- Both users can hear each other if audio calling is enabled.

### Test 4: ISL Recognition

- Sign-language user performs a supported sign.
- The system recognizes it.
- The text appears on both users' dashboards.

### Test 5: Speech Recognition

- Hearing user speaks.
- Speech is converted to text.
- The text appears on both users' dashboards, especially the deaf user's dashboard.

### Test 6: Room Isolation

- Users in Room A should not connect with users in Room B.

---

# 10. Networking Issue: Make It Work Beyond Localhost

Please investigate why the application does not connect when another person's mobile phone joins the same room.

Possible issues to check include:

- Using `localhost` incorrectly.
- Mobile phone being unable to access the signaling server.
- Incorrect server IP address.
- HTTP/HTTPS restrictions.
- Secure-context requirements for camera/microphone.
- CORS configuration.
- Socket.IO connection URL.
- Firewall issues.
- WebRTC ICE/STUN/TURN configuration.
- NAT/network restrictions.

### Important

If the app is intended to work between different physical devices, `localhost` on one device cannot automatically represent the server on another device.

Please configure the application properly for testing across devices.

For local Wi-Fi testing:

- Both devices should be able to reach the signaling server using the computer's LAN IP address.

For real deployment:

- Use a publicly accessible HTTPS server.
- Configure appropriate STUN/TURN servers if required for reliable WebRTC connections across different networks.

Please make the simplest practical setup work first.

---

# 11. Keep the Project Simple

This is a student project, so please do not over-engineer it.

Priorities should be:

1. A working two-person connection.
2. Real video communication.
3. A small but real ISL recognition vocabulary.
4. Working speech-to-text.
5. Correct text sharing between dashboards.
6. A clean and understandable interface.

Do not add unnecessary features that make the project harder to run.

---

# 12. Debugging Requirements

Please thoroughly inspect the existing code and identify why the current implementation fails.

Specifically check:

- Console errors in the browser.
- Backend/server terminal errors.
- Socket.IO connection events.
- Room join events.
- WebRTC offer/answer flow.
- ICE candidate exchange.
- Camera permissions.
- Microphone permissions.
- MediaPipe errors.
- Model loading errors.
- Speech recognition errors.

Please fix the actual errors rather than adding placeholder UI elements.

Add useful console logs where necessary, such as:

- User joined room.
- Second user joined room.
- Creating offer.
- Received offer.
- Creating answer.
- Received answer.
- ICE candidate received.
- Remote stream connected.
- ISL sign recognized.
- Speech transcription received.

These logs will make future debugging easier.

---

# 13. Expected Final Result

The completed application should behave approximately like this:

### Step 1

Person A opens the app and enters:

> Room: `123`

### Step 2

Person B opens the app from another device and enters:

> Room: `123`

### Step 3

Both users successfully connect.

### Step 4

Both users can see each other in the live video call.

### Step 5

The deaf/sign-language user performs a supported ISL sign.

The application detects the sign and translates it into text.

Example:

> "THANK YOU"

This text appears on:

- Deaf user's dashboard.
- Hearing user's dashboard.

### Step 6

The hearing user speaks:

> "You are welcome."

Speech recognition converts it to:

> You are welcome.

This text appears on:

- Hearing user's dashboard.
- Deaf user's dashboard.

---


## Branding Requirement

Before considering the project complete, make sure the application branding has been updated to **SignConnect** and the **user-provided logo** is being used in the application.


# 14. Final Instruction

Please work with the existing project and **make the current application genuinely functional**.

Do not only provide:

- Separate hand-detection demos.
- Fake translations.
- Placeholder messages.
- Mock video calls.
- A system that only works in one browser/tab.

The goal is a **real, working prototype** where two people can join the same room from different devices and communicate using:

- Live video.
- Indian Sign Language recognition → text.
- Hearing person's speech → text.
- Real-time sharing of the translated/transcribed text.

Please implement the simplest reliable version first, test it properly, and clearly explain any limitations (for example, the number of ISL signs supported in the first version).

## Success Criteria

The project should be considered successful when:

- [ ] Two different devices can join the same room.
- [ ] The video call connects successfully.
- [ ] Both users can see each other.
- [ ] ISL recognition is integrated into the communication flow.
- [ ] Supported ISL signs are translated into actual text.
- [ ] The sign translation appears on both dashboards.
- [ ] Hearing-user speech is converted into text.
- [ ] Speech transcription appears on the deaf user's dashboard.
- [ ] The app works in a realistic two-person test.
- [ ] The implementation remains simple enough for a student project.

---

## Please Start by Doing This

1. Inspect the entire existing codebase.
2. Identify the exact causes of the current call/room connection failure.
3. Fix the two-device room connection first.
4. Integrate the existing hand detection into the main app instead of keeping it as a separate feature.
5. Implement actual supported-sign recognition and text output.
6. Implement speech-to-text for the hearing user.
7. Synchronize the recognized/transcribed messages between both users.
8. Test the complete flow with two different devices.
9. Fix all errors found during testing.
10. Provide clear instructions for running and testing the final application.
