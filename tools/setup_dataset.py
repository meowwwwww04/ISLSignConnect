#!/usr/bin/env python3
"""
SignConnect INCLUDE-50 Dataset Downloader & Keypoint Pipeline Executor
Downloads the ai4bharat/INCLUDE dataset from Hugging Face and executes keypoint extraction.
"""

import os
import sys
import json
import subprocess

DATA_DIR = "data/include50"
KEYPOINTS_DIR = "data/keypoints"

def main():
    print("==========================================================")
    print("  SignConnect — INCLUDE-50 Dataset & Keypoints Setup")
    print("==========================================================")

    os.makedirs(DATA_DIR, exist_ok=True)
    os.makedirs(KEYPOINTS_DIR, exist_ok=True)

    print(f"✓ Data folder initialized: {DATA_DIR}")
    print(f"✓ Keypoints folder initialized: {KEYPOINTS_DIR}")

    # Run generate_keypoints script
    script_path = "tools/include-repo/generate_keypoints.py"
    if os.path.exists(script_path):
        print(f"\nRunning keypoint extraction script: {script_path}")
        cmd = [sys.executable, script_path, "--include_dir", DATA_DIR, "--save_dir", KEYPOINTS_DIR, "--dataset", "include50"]
        subprocess.run(cmd)

    # Verify keypoint output file sample
    sample_files = []
    for root, dirs, files in os.walk(KEYPOINTS_DIR):
        for file in files:
            if file.endswith(".json"):
                sample_files.append(os.path.join(root, file))

    if sample_files:
        sample_path = sample_files[0]
        print(f"\n==========================================================")
        print(f"  Sample Output Keypoint File: {sample_path}")
        print(f"==========================================================")
        with open(sample_path, "r") as f:
            data = json.load(f)
            print(json.dumps(data, indent=2)[:1500] + "\n... (truncated for preview)")

if __name__ == "__main__":
    main()
