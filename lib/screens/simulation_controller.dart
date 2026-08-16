import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/alert_service.dart';
import '../constants/simulation_coords.dart'; // kDemoPotholeIdKey, kPotholeIdFallback

// =====================================================
// SIMULATION CONSTANTS
//
// Step durations decrease per stage pair to keep the
// demo fast and engaging for a presentation:
//   Steps 1-2  (stage 1 — caution beep)    → 20s each
//   Steps 3-4  (stage 2 — horn + 3 flashes) → 15s each
//   Steps 5-6  (stage 3 — siren + torch)    → 10s each
//
// Total runtime = 20+20+15+15+10+10 = 90 seconds
// Post-simulation cooldown = 3 minutes (180s)
//
// kPotholeId is now sourced from constants/simulation_coords.dart
// so UploadPotholePage (demo mode) and SimulationController
// always point at the same seeded document.
// =====================================================
const int    kTotalSteps          = 6;
const int    kCooldownDurationSec = 180;

/// Duration in seconds for a given 1-based step index.
int stepDurationFor(int step) => switch (step) {
      1 || 2 => 20,
      3 || 4 => 15,
      _      => 10, // steps 5 & 6
    };

/// Forced alert level for a given 1-based step index.
/// Client-side mapping so demo always escalates regardless of DB severity.
AlertLevel levelForStep(int step) => switch (step) {
      1 || 2 => AlertLevel.stage1,
      3 || 4 => AlertLevel.stage2,
      _      => AlertLevel.stage3,
    };

/// Fallback status message when backend returns an empty message.
String fallbackMsg(AlertLevel level) => switch (level) {
      AlertLevel.stage1 => 'Pothole detected ahead — caution',
      AlertLevel.stage2 => 'Pothole approaching — slow down',
      AlertLevel.stage3 => 'SEVERE pothole — danger zone',
      _                 => 'All clear',
    };

/// Formats seconds as "M:SS" (e.g. 125 → "2:05").
String fmtCountdown(int totalSeconds) {
  final int m = totalSeconds ~/ 60;
  final int s = totalSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

// =====================================================
// SIMULATION CONTROLLER
//
// Owns ALL business logic — timers, API calls, state.
// Zero dependency on BuildContext or any Widget.
// The SimulationPage passes [onStateChanged] so the
// controller can call setState on the page after
// every mutation.
// =====================================================

class SimulationController {
  SimulationController({required this.onStateChanged});

  /// Triggers a setState in SimulationPage after any mutation.
  final VoidCallback onStateChanged;

  // ---- backend ----
  bool backendAlive = false;
  bool connecting   = false;

  // ---- config (mutated by UI selectors) ----
  double speedKmh = 20;
  String weather  = 'dry';

  // ---- simulation run ----
  bool      running          = false;
  bool      fetchingLocation = false;
  Position? position;
  PotholeAlert? lastAlert;
  AlertLevel    lastTriggeredLevel = AlertLevel.none;

  // The pothole ID used for this run. Resolved from SharedPreferences
  // at startSimulation() time so it always matches the last demo upload.
  String _activePotholeId = kPotholeIdFallback;

  int    currentStep       = 0;
  int    secondsRemaining  = 20;
  Timer? _tickTimer;

  // ---- post-simulation cooldown ----
  bool   inCooldown        = false;
  int    cooldownRemaining = 0;
  Timer? _cooldownTimer;

  // ---- status line ----
  String statusMsg = 'Configure and press Start Simulation';

  // =================================================
  // BACKEND
  // =================================================

  Future<void> checkBackend() async {
    final alive = await ApiService.instance.isBackendAlive();
    backendAlive = alive;
    onStateChanged();
  }

  /// Returns null on success, or an error string to show as a snack.
  Future<String?> connectBackend(String typed) async {
    final url = typed.trim();
    if (url.isEmpty) {
      return 'Enter a backend URL first (e.g. https://xxxx.ngrok-free.app)';
    }

    connecting = true;
    onStateChanged();

    final reachable = await ApiService.instance.isBackendAlive(overrideUrl: url);
    if (reachable) await ApiConfig.setBaseUrl(url);

    connecting    = false;
    backendAlive  = reachable;
    onStateChanged();

    return reachable
        ? null
        : 'Could not reach that URL — check it\'s running and the tunnel is up';
  }

  // =================================================
  // LOCATION
  // =================================================

  Future<Position?> getLocation(void Function(String) showSnack) async {
    fetchingLocation = true;
    statusMsg        = 'Getting your location…';
    onStateChanged();

    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        showSnack('Please enable Location on your device');
        return null;
      }

      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) {
          showSnack('Location permission denied');
          return null;
        }
      }
      if (perm == LocationPermission.deniedForever) {
        showSnack('Location permission permanently denied — enable in Settings');
        return null;
      }

      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } finally {
      fetchingLocation = false;
      onStateChanged();
    }
  }

  // =================================================
  // START SIMULATION
  // =================================================

  Future<void> startSimulation(void Function(String) showSnack) async {
    if (!backendAlive) {
      showSnack('Connect a working backend URL first');
      return;
    }

    // Cancel any leftover cooldown before a fresh run.
    _cooldownTimer?.cancel();
    _cooldownTimer = null;

    final pos = await getLocation(showSnack);
    if (pos == null) return;

    // Resolve which pothole ID to use for this run.
    // If a demo upload was done, its returned _id is in prefs.
    // Falls back to kPotholeIdFallback if prefs is empty.
    final prefs = await SharedPreferences.getInstance();
    _activePotholeId = prefs.getString(kDemoPotholeIdKey) ?? kPotholeIdFallback;

    position             = pos;
    running              = true;
    inCooldown           = false;
    cooldownRemaining    = 0;
    currentStep          = 0;
    secondsRemaining     = stepDurationFor(1);
    lastAlert            = null;
    lastTriggeredLevel   = AlertLevel.none;
    statusMsg            =
        'Simulating at ${speedKmh.toInt()} km/h · $weather weather';
    onStateChanged();

    // Fire step 1 immediately so the demo doesn't sit idle.
    await _runStep();

    // Tick every second; each step drains its own duration then advances.
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      secondsRemaining--;
      onStateChanged();

      if (secondsRemaining <= 0) {
        if (currentStep >= kTotalSteps) {
          _completeSimulation();
          return;
        }
        await _runStep();
        if (running) {
          secondsRemaining = stepDurationFor(currentStep);
          onStateChanged();
        }
      }
    });
  }

  // =================================================
  // RUN ONE STEP
  // =================================================

  Future<void> _runStep() async {
    currentStep++;

    // How long will the NEXT step last? (shown in status line)
    final bool isLast  = currentStep >= kTotalSteps;
    final int  nextDur = isLast ? 0 : stepDurationFor(currentStep + 1);

    statusMsg = 'Step $currentStep of $kTotalSteps — checking backend…';
    onStateChanged();

    await _poll();

    statusMsg = isLast
        ? 'Final step done — starting cooldown…'
        : 'Step $currentStep of $kTotalSteps complete · next in ${nextDur}s';
    onStateChanged();

    if (isLast) {
      await Future.delayed(const Duration(seconds: 1));
      _completeSimulation();
    }
  }

  // =================================================
  // POLL BACKEND
  //
  // Backend supplies distance + message metadata.
  // Alert level is forced client-side for reliable demo staging.
  // AlertService.trigger() is called ONLY when the level
  // changes — prevents the siren/torch from restarting
  // mid-step when steps 5 and 6 are both stage3.
  //
  // STAGE 1 SOUND NOTE:
  // audioplayers play() is fire-and-forget on Android.
  // The beep_soft.mp3 starts immediately in the audio thread;
  // we await here only to surface errors in the log.
  // If you hear nothing at stage 1, confirm the asset path in
  // pubspec.yaml: assets/sounds/beep_soft.mp3
  // =================================================

  Future<void> _poll() async {
    if (position == null) return;

    final alert = await ApiService.instance.simulateStep(
      potholeId: _activePotholeId,
      step:      currentStep - 1,
      condition: weather,
    );

    final AlertLevel level = levelForStep(currentStep);

    final stagedAlert = PotholeAlert(
      level:       level,
      message:     alert.message.isNotEmpty ? alert.message : fallbackMsg(level),
      distance:    alert.distance,
      severity:    alert.severity,
      weatherNote: alert.weatherNote,
    );

    lastAlert = stagedAlert;
    onStateChanged();

    if (level != lastTriggeredLevel) {
      lastTriggeredLevel = level;
      await AlertService.instance.trigger(stagedAlert);
    }
  }

  // =================================================
  // COMPLETE — 3-minute cooldown before ALL CLEAR
  // =================================================

  void _completeSimulation() {
    _tickTimer?.cancel();
    _tickTimer = null;
    AlertService.instance.stopAlert();

    running           = false;
    inCooldown        = true;
    cooldownRemaining = kCooldownDurationSec;
    statusMsg =
        'Simulation complete — pothole zone clearing in ${fmtCountdown(cooldownRemaining)}';
    onStateChanged();

    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      cooldownRemaining--;
      statusMsg = 'Pothole zone clearing in ${fmtCountdown(cooldownRemaining)}…';
      onStateChanged();

      if (cooldownRemaining <= 0) {
        timer.cancel();
        _cooldownTimer       = null;
        inCooldown           = false;
        lastAlert            = null;
        lastTriggeredLevel   = AlertLevel.none;
        statusMsg            = 'All clear — pothole zone passed ✅';
        onStateChanged();
      }
    });
  }

  // =================================================
  // STOP (manual)
  // =================================================

  void stopSimulation() {
    _tickTimer?.cancel();
    _tickTimer = null;
    _cooldownTimer?.cancel();
    _cooldownTimer = null;
    AlertService.instance.stopAlert();

    running            = false;
    inCooldown         = false;
    cooldownRemaining  = 0;
    lastAlert          = null;
    lastTriggeredLevel = AlertLevel.none;
    statusMsg          = 'Simulation stopped';
    onStateChanged();
  }

  // =================================================
  // DISPOSE
  // =================================================

  void dispose() {
    _tickTimer?.cancel();
    _cooldownTimer?.cancel();
  }
}