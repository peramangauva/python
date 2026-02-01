import time
import threading
import cv2
import mediapipe as mp
from flask import Flask, jsonify

# -----------------------------
# Flask app
# -----------------------------
app = Flask(__name__)

# -----------------------------
# MediaPipe setup
# -----------------------------
BaseOptions = mp.tasks.BaseOptions
HandLandmarker = mp.tasks.vision.HandLandmarker
HandLandmarkerOptions = mp.tasks.vision.HandLandmarkerOptions
VisionRunningMode = mp.tasks.vision.RunningMode

options = HandLandmarkerOptions(
    base_options=BaseOptions(model_asset_path="c:/Users/T-GAMER/Desktop/Python/hand_landmarker.task"),
    running_mode=VisionRunningMode.VIDEO,
    num_hands=1,
)

# -----------------------------
# Shared state
# -----------------------------
cap = cv2.VideoCapture(0)
landmarker = HandLandmarker.create_from_options(options)

latest_data = None
last_calc_time = 0.0
lock = threading.Lock()

MAX_FPS = 30
MIN_INTERVAL = 1.0 / MAX_FPS

# -----------------------------
# Landmark index mapping
# -----------------------------
FINGER_MAP = {
    "Finger1": [1, 2, 3, 4],      # Thumb
    "Finger2": [5, 6, 7, 8],      # Index
    "Finger3": [9, 10, 11, 12],   # Middle
    "Finger4": [13, 14, 15, 16],  # Ring
    "Finger5": [17, 18, 19, 20],  # Pinky
}

WRIST_INDEX = 0

# -----------------------------
# Core logic (on-demand, rate-limited)
# -----------------------------
def get_hand_data_if_needed():
    global latest_data, last_calc_time

    now = time.time()

    with lock:
        if now - last_calc_time < MIN_INTERVAL:
            return latest_data

        ret, frame = cap.read()
        if not ret:
            return None

        mp_image = mp.Image(
            image_format=mp.ImageFormat.SRGB,
            data=frame
        )

        timestamp = int(now * 1000)
        result = landmarker.detect_for_video(mp_image, timestamp)

        if not result.hand_landmarks:
            latest_data = None
            last_calc_time = now
            return None

        hand = result.hand_landmarks[0]

        # Wrist
        wrist = hand[WRIST_INDEX]
        data = {
            "Wrist": {
                "x": wrist.x,
                "y": wrist.y,
                "z": wrist.z
            }
        }

        # Fingers
        for finger_name, indices in FINGER_MAP.items():
            data[finger_name] = [
                {
                    "x": hand[i].x,
                    "y": hand[i].y,
                    "z": hand[i].z
                }
                for i in indices
            ]

        latest_data = data
        last_calc_time = now
        return latest_data

# -----------------------------
# API endpoint
# -----------------------------
@app.route("/webcam", methods=["GET"])
def webcam():
    data = get_hand_data_if_needed()
    return jsonify({"data": data})

# -----------------------------
# Run server
# -----------------------------
if __name__ == "__main__":
    app.run(
        debug=True,
        use_reloader=False,
        threaded=True
    )
