"""
Road Guard AI — Local Test Backend
====================================
Run this on your machine to test the Flutter app
WITHOUT hosting. No YOLO, no MongoDB needed.

How to test:
1. Install:  pip install fastapi uvicorn python-multipart
2. Run:      uvicorn test_backend:app --reload --port 8000
3. Flutter:
   - Emulator:  baseUrl = 'http://10.0.2.2:8000'  (already set)
   - USB device: run `adb reverse tcp:8000 tcp:8000` then
                 baseUrl = 'http://localhost:8000'
   - WiFi device: baseUrl = 'http://<YOUR_PC_IP>:8000'
                  find IP: ipconfig (Windows) / ifconfig (Mac/Linux)

This stub cycles through alert stages so you can test
all 3 sound + flash behaviours without real potholes.
"""

from fastapi import FastAPI, File, UploadFile, Form
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import random
import time

app = FastAPI(title="Road Guard AI — Test Server")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------
# Cycle through stages to test all alert levels
# Change this to a fixed stage if you want to test one
# ---------------------------------------------------
_call_count = 0

def _get_test_stage() -> int:
    """Cycles 0 → 1 → 2 → 3 → 0 → ... every call"""
    global _call_count
    stage = _call_count % 4
    _call_count += 1
    return stage

# ---------------------------------------------------
# HEALTH CHECK
# ---------------------------------------------------

@app.get("/health")
def health():
    return {"status": "ok", "server": "Road Guard AI test stub"}

# ---------------------------------------------------
# CHECK NEARBY
# POST /api/check-nearby
# ---------------------------------------------------

class NearbyRequest(BaseModel):
    lat: float
    lng: float
    speed_kmh: float = 30.0
    weather: str = "dry"

_STAGE_MESSAGES = {
    0: "All clear — no hazards nearby",
    1: "Pothole detected ~80m ahead — slow down",
    2: "Multiple potholes — reduce speed immediately",
    3: "SEVERE HAZARD — large pothole/manhole ahead",
}

@app.post("/api/check-nearby")
def check_nearby(req: NearbyRequest):
    stage = _get_test_stage()

    # Simulate weather multiplier
    severity_base = [0.0, 0.25, 0.60, 0.90][stage]
    weather_mult = 1.3 if req.weather == "rain" else 1.0
    severity = min(severity_base * weather_mult, 1.0)

    return {
        "alert_stage": stage,
        "message": _STAGE_MESSAGES[stage],
        "distance_m": None if stage == 0 else round(30 + random.uniform(10, 80), 1),
        "severity": round(severity, 2),
        "weather_note": "Rain increases severity" if req.weather == "rain" and stage > 0 else None,
        "lat": req.lat,
        "lng": req.lng,
        "speed_kmh": req.speed_kmh,
    }

# ---------------------------------------------------
# UPLOAD POTHOLE
# POST /api/upload
# ---------------------------------------------------

@app.post("/api/upload")
async def upload_pothole(
    image: UploadFile = File(...),
    lat: float = Form(...),
    lng: float = Form(...),
):
    contents = await image.read()
    size_kb = len(contents) / 1024

    # Simulate YOLO detection (random for testing)
    detected = random.choice(["pothole", "pothole", "pothole", "manhole", "no_defect"])
    severity = round(random.uniform(0.3, 0.95), 2) if detected != "no_defect" else 0.0
    alert_stage = (
        0 if detected == "no_defect"
        else 1 if severity < 0.4
        else 2 if severity < 0.7
        else 3
    )

    return {
        "success": True,
        "message": (
            f"Detected: {detected} at ({lat:.4f}, {lng:.4f})"
            if detected != "no_defect"
            else "No road defect detected"
        ),
        "label": detected,
        "severity": severity,
        "alert_stage": alert_stage,
        "image_size_kb": round(size_kb, 1),
        "coords": {"lat": lat, "lng": lng},
    }


# ---------------------------------------------------
# FORCE SPECIFIC STAGE — useful for targeted testing
# GET /api/set-stage/{stage}
# ---------------------------------------------------

@app.get("/api/set-stage/{stage}")
def set_stage(stage: int):
    global _call_count
    if stage not in (0, 1, 2, 3):
        return {"error": "stage must be 0-3"}
    _call_count = stage
    return {"message": f"Next check-nearby will return stage {stage}"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
