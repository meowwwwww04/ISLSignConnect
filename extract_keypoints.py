"""
extract_keypoints.py

Extracts real MediaPipe hand landmarks from the "images for phrases" ISL
dataset and saves them as one JSON file per image, organized by class
(word/phrase). This replaces the old fake/placeholder "keypoints" folder
with genuine extracted data.

USAGE:
    1. Save this file inside ~/Desktop/islProject  (same level as data/)
    2. Activate the project's venv:
           source ~/Desktop/islProject/.venv/bin/activate
    3. Run it:
           python extract_keypoints.py

OUTPUT:
    Creates ~/Desktop/islProject/data/real_keypoints/<word>/<image_name>.json
    for every image that had at least one hand detected. Images where no
    hand was detected are skipped and counted, not silently lost.
"""

import os
import json
import cv2
import mediapipe as mp

# --- CONFIG: adjust these two paths if your folders are named differently ---
INPUT_DIR = os.path.expanduser("~/Desktop/islProject/data/images for phrases")
OUTPUT_DIR = os.path.expanduser("~/Desktop/islProject/data/real_keypoints")

mp_hands = mp.solutions.hands


def extract_landmarks_from_image(image_path, hands):
    """Run MediaPipe Hands on one image, return landmark data or None."""
    image = cv2.imread(image_path)
    if image is None:
        return None

    image_rgb = cv2.cvtColor(image, cv2.COLOR_BGR2RGB)
    results = hands.process(image_rgb)

    if not results.multi_hand_landmarks:
        return None  # no hand detected in this image

    hands_data = []
    for hand_landmarks in results.multi_hand_landmarks:
        points = [
            {"x": lm.x, "y": lm.y, "z": lm.z}
            for lm in hand_landmarks.landmark
        ]
        hands_data.append(points)

    return hands_data


def main():
    if not os.path.isdir(INPUT_DIR):
        print(f"ERROR: input folder not found: {INPUT_DIR}")
        print("Double check the folder name/path and edit INPUT_DIR above.")
        return

    os.makedirs(OUTPUT_DIR, exist_ok=True)

    with mp_hands.Hands(
        static_image_mode=True,   # these are static photos, not video frames
        max_num_hands=2,
        min_detection_confidence=0.3,
    ) as hands:

        class_names = sorted(os.listdir(INPUT_DIR))
        total_processed = 0
        total_skipped = 0

        for class_name in class_names:
            class_input_dir = os.path.join(INPUT_DIR, class_name)
            if not os.path.isdir(class_input_dir):
                continue

            class_output_dir = os.path.join(OUTPUT_DIR, class_name)
            os.makedirs(class_output_dir, exist_ok=True)

            image_files = [
                f for f in os.listdir(class_input_dir)
                if f.lower().endswith((".png", ".jpg", ".jpeg"))
            ]

            class_processed = 0
            class_skipped = 0

            for image_file in image_files:
                image_path = os.path.join(class_input_dir, image_file)
                hands_data = extract_landmarks_from_image(image_path, hands)

                if hands_data is None:
                    class_skipped += 1
                    continue

                sample_id = os.path.splitext(image_file)[0]
                out_data = {
                    "gesture_word": class_name,
                    "sample_id": sample_id,
                    "num_hands_detected": len(hands_data),
                    "hands": hands_data,
                }

                out_path = os.path.join(class_output_dir, f"{sample_id}.json")
                with open(out_path, "w") as f:
                    json.dump(out_data, f)

                class_processed += 1

            print(f"[{class_name}] processed: {class_processed}, skipped: {class_skipped}")
            total_processed += class_processed
            total_skipped += class_skipped

        print(f"\nDONE. Total processed: {total_processed}  |  Total skipped (no hand found): {total_skipped}")
        print(f"Output saved to: {OUTPUT_DIR}")


if __name__ == "__main__":
    main()
