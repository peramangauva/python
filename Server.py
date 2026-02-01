import json
from threading import Thread
from flask import Flask, request, jsonify
from PIL import Image
from windows_capture import WindowsCapture

import numpy as np
from scipy.spatial import cKDTree

app = Flask(__name__)

# ===========================
#  LOAD PALETTE FROM JSON
# ===========================
with open("palette.json", "r", encoding="utf-8") as f:
    raw_palette = json.load(f)

# Convert emoji -> [r,g,b]  →  (r,g,b) -> emoji
PALETTE = {
    tuple(rgb): emoji
    for emoji, rgb in raw_palette.items()
}

# Prepare KD-Tree data
PALETTE_COLORS = np.array(list(PALETTE.keys()), dtype=np.int16)
PALETTE_EMOJIS = list(PALETTE.values())
KD_TREE = cKDTree(PALETTE_COLORS)

latest_frame = None
capture = WindowsCapture(
    cursor_capture=True,
    draw_border=False,
    monitor_index=1
)

@capture.event
def on_frame_arrived(frame, _):
    global latest_frame
    img = Image.frombuffer(
        "RGBA",
        (frame.width, frame.height),
        frame.frame_buffer,
        "raw",
        "BGRA",
        0,
        1
    )
    latest_frame = img.convert("RGB")

@capture.event
def on_closed():
    pass

def get_closest_emoji(pixel):
    _, idx = KD_TREE.query(pixel, k=1)
    return PALETTE_EMOJIS[idx]

@app.route("/emojis", methods=["POST"])
def process_to_emojis():
    if latest_frame is None:
        return jsonify({"text": "Waiting for capture...", "w": 0, "h": 0}), 503

    data = request.get_json() or {}
    scale_w = int(data.get("scale", 40))

    # Terminal aspect correction
    scale_h = int(scale_w * 9 / 16)

    # Resize
    img = latest_frame.resize(
        (scale_w, scale_h),
        resample=Image.Resampling.BOX
    )

    pixels = img.load()

    lines = []
    cache = {}  # per-frame cache

    for y in range(scale_h):
        row = []
        for x in range(scale_w):
            px = pixels[x, y]
            if px not in cache:
                cache[px] = get_closest_emoji(px)
            row.append(cache[px])
        lines.append("".join(row))

    return jsonify({
        "text": "\n".join(lines),
        "w": scale_w,
        "h": scale_h
    })

if __name__ == "__main__":
    Thread(target=capture.start, daemon=True).start()
    print("🚀 Server active on http://127.0.0.1:5000/emojis")
    app.run(debug=False, use_reloader=False, threaded=True)
