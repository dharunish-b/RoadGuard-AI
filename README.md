<div align="center">
  <img src="road-guard-ai.png" alt="Road Guard AI Logo" width="500" height="500"/>
  <h1>Road Guard- AI 📱</h1>
  <p><em>AI-Powered Pothole Detection & Rider Safety Application</em></p>
</div>

---

## 🌟 Overview

**Road Guard AI** is a cutting-edge mobile application designed to enhance rider safety. By utilizing your device's GPS and connecting to our powerful backend, it provides real-time alerts for upcoming road hazards like potholes, calculating exactly when to warn you based on your speed and current weather conditions. 


---

## ✨ Features

- **🛡️ Real-Time Monitoring:** Continuously tracks your location and alerts you to upcoming road hazards.
- **🔋 Background Service:** Keeps monitoring active even when the app is minimized or the screen is off.
- **🚨 Dynamic Alerts:** Uses audio sirens, flashlight strobes, and vibration to ensure you notice critical warnings.
- **📸 Hazard Uploading:** Easily capture and upload photos of new potholes to improve the community database.
- **🧪 Simulation Mode:** Test out the alert system without having to ride towards a real pothole.
- **📊 Community Reports:** Keep track of the potholes you've reported. Once a pothole is repaired, you can mark it as fixed directly within the app.

---

## 🛠️ Tech Stack

- **Framework:** [Flutter](https://flutter.dev/) (Dart)
- **Location Services:** `geolocator`
- **Background Execution:** `flutter_background_service`
- **Hardware Integrations:** `torch_light`, `vibration`, `audioplayers`, `image_picker`
- **Network & State:** `http`, `shared_preferences`
- **Notifications:** `flutter_local_notifications`

---

## 🚀 Getting Started

### Prerequisites
- Flutter SDK (^3.12.2)
- Android Studio / VS Code
- A physical device is recommended for testing hardware features (GPS, flashlight, vibration).

### Installation

1. **Clone the repository:**
   ```bash
   git clone <your-repo-url>
   cd frontend
   ```

2. **Install dependencies:**
   ```bash
   flutter pub get
   ```

3. **Configure Backend Connection:**
   The app connects to the backend via an API. We are currently using **ngrok** to tunnel the local backend to the internet. Update the base URL configuration in the app to your active ngrok URL.

4. **Run the app:**
   ```bash
   flutter run
   ```

---

## 🔋 Battery Optimization Note
For uninterrupted monitoring, please ensure the app is allowed to run in the background without battery restrictions:
- **Android:** Settings → Apps → Road Guard AI → Battery → Set to "Unrestricted".

---
<p align="center">Built for safer roads. 🛣️</p>
