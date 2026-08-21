import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../services/alert_service.dart';
import '../constants/simulation_coords.dart';

// =====================================================
// SIMULATION CONFIGURATION
//
// 6 simulation steps
//
// Step 1 -> 10 seconds
// Step 2 -> 10 seconds
// Step 3 -> 8 seconds
// Step 4 -> 8 seconds
// Step 5 -> 7 seconds
// Step 6 -> 7 seconds
//
// TOTAL = 50 SECONDS
//
// Destination:
//     kSimLat = 9.9252
//     kSimLng = 78.1198
//
// The simulation gradually moves toward the destination.
// =====================================================

const int kTotalSteps = 6;

const int kCooldownDurationSec = 180;

/// Duration of each simulation step.
int stepDurationFor(int step) => switch (step) {
      1 => 10,
      2 => 10,
      3 => 8,
      4 => 8,
      5 => 7,
      _ => 7,
    };

/// Alert level for each simulation step.
///
/// Step 1-2:
///     Stage 1 = early caution / light buzzer
///
/// Step 3-4:
///     Stage 2 = warning / buzzer
///
/// Step 5-6:
///     Stage 3 = danger / siren
AlertLevel levelForStep(int step) => switch (step) {
      1 || 2 => AlertLevel.stage1,
      3 || 4 => AlertLevel.stage2,
      _ => AlertLevel.stage3,
    };

/// Fallback message when backend returns an empty message.
String fallbackMsg(AlertLevel level) => switch (level) {
      AlertLevel.stage1 =>
        'Pothole detected ahead — caution',
      AlertLevel.stage2 =>
        'Pothole approaching — slow down',
      AlertLevel.stage3 =>
        'SEVERE pothole — danger zone',
      _ =>
        'All clear',
    };

/// Formats seconds as M:SS.
String fmtCountdown(int totalSeconds) {
  final int m = totalSeconds ~/ 60;
  final int s = totalSeconds % 60;

  return '$m:${s.toString().padLeft(2, '0')}';
}

// =====================================================
// SIMULATION COORDINATES
// =====================================================

class SimulationPoint {
  const SimulationPoint({
    required this.latitude,
    required this.longitude,
  });

  final double latitude;
  final double longitude;
}

/// Demo route.
///
/// Step 1 = far from pothole
/// Step 2 = getting closer
/// Step 3 = warning begins
/// Step 4 = close
/// Step 5 = very close
/// Step 6 = destination
///
/// The final point ALWAYS uses kSimLat/kSimLng.
List<SimulationPoint> get simulationRoute {
  return [
    SimulationPoint(
      latitude: kSimLat - 0.0015,
      longitude: kSimLng - 0.0015,
    ),
    SimulationPoint(
      latitude: kSimLat - 0.0012,
      longitude: kSimLng - 0.0012,
    ),
    SimulationPoint(
      latitude: kSimLat - 0.0008,
      longitude: kSimLng - 0.0008,
    ),
    SimulationPoint(
      latitude: kSimLat - 0.0005,
      longitude: kSimLng - 0.0005,
    ),
    SimulationPoint(
      latitude: kSimLat - 0.0002,
      longitude: kSimLng - 0.0002,
    ),
    SimulationPoint(
      latitude: kSimLat,
      longitude: kSimLng,
    ),
  ];
}

// =====================================================
// SIMULATION CONTROLLER
// =====================================================

class SimulationController {
  SimulationController({
    required this.onStateChanged,
  });

  /// Triggers setState() in SimulationPage.
  final VoidCallback onStateChanged;

  // ===================================================
  // BACKEND
  // ===================================================

  bool backendAlive = false;
  bool connecting = false;

  // ===================================================
  // CONFIGURATION
  // ===================================================

  double speedKmh = 20;

  String weather = 'dry';

  // ===================================================
  // SIMULATION
  // ===================================================

  bool running = false;

  bool fetchingLocation = false;

  /// Current simulated position.
  ///
  /// IMPORTANT:
  /// During demo simulation this is NOT replaced by
  /// the phone's real GPS position.
  Position? position;

  PotholeAlert? lastAlert;

  AlertLevel lastTriggeredLevel = AlertLevel.none;

  /// Pothole used for this simulation.
  String _activePotholeId = kPotholeIdFallback;

  int currentStep = 0;

  int secondsRemaining = 10;

  Timer? _tickTimer;

  // ===================================================
  // REAL GPS
  // ===================================================

  StreamSubscription<Position>? _positionStream;

  /// Whether continuous GPS tracking is active.
  bool get isTrackingLocation => _positionStream != null;

  // ===================================================
  // COOLDOWN
  // ===================================================

  bool inCooldown = false;

  int cooldownRemaining = 0;

  Timer? _cooldownTimer;

  // ===================================================
  // STATUS
  // ===================================================

  String statusMsg =
      'Configure and press Start Simulation';

  // ===================================================
  // BACKEND
  // ===================================================

  Future<void> checkBackend() async {
    final bool alive =
        await ApiService.instance.isBackendAlive();

    backendAlive = alive;

    onStateChanged();
  }

  /// Connect to backend.
  Future<String?> connectBackend(String typed) async {
    final String url = typed.trim();

    if (url.isEmpty) {
      return 'Enter a backend URL first '
          '(e.g. https://xxxx.ngrok-free.app)';
    }

    connecting = true;

    onStateChanged();

    final bool reachable =
        await ApiService.instance.isBackendAlive(
      overrideUrl: url,
    );

    if (reachable) {
      await ApiConfig.setBaseUrl(url);
    }

    connecting = false;

    backendAlive = reachable;

    onStateChanged();

    return reachable
        ? null
        : 'Could not reach that URL — '
            'check it is running and the tunnel is up';
  }

  // ===================================================
  // LOCATION PERMISSION
  // ===================================================

  Future<bool> _checkLocationPermission(
    void Function(String) showSnack,
  ) async {
    try {
      final bool serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        showSnack(
          'Please enable Location/GPS on your phone.',
        );

        return false;
      }

      LocationPermission permission =
          await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission =
            await Geolocator.requestPermission();

        if (permission == LocationPermission.denied) {
          showSnack(
            'Location permission denied.',
          );

          return false;
        }
      }

      if (permission ==
          LocationPermission.deniedForever) {
        showSnack(
          'Location permission permanently denied. '
          'Open Android Settings and allow location permission.',
        );

        return false;
      }

      return true;
    } catch (e) {
      showSnack(
        'Unable to check GPS permission: $e',
      );

      return false;
    }
  }

  // ===================================================
  // GET REAL CURRENT LOCATION
  //
  // Used only to verify that GPS permission is
  // available.
  //
  // DEMO SIMULATION DOES NOT USE THIS LOCATION
  // as the moving simulation coordinate.
  // ===================================================

  Future<Position?> getLocation(
    void Function(String) showSnack,
  ) async {
    fetchingLocation = true;

    statusMsg =
        'Checking GPS permission…';

    onStateChanged();

    try {
      final bool allowed =
          await _checkLocationPermission(
        showSnack,
      );

      if (!allowed) {
        return null;
      }

      final Position currentPosition =
          await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      statusMsg =
          'GPS available — starting demo simulation';

      onStateChanged();

      return currentPosition;
    } catch (e) {
      showSnack(
        'Unable to get GPS location: $e',
      );

      return null;
    } finally {
      fetchingLocation = false;

      onStateChanged();
    }
  }

  // ===================================================
  // START REAL GPS TRACKING
  //
  // NOT USED FOR DEMO MOVEMENT.
  //
  // We keep this method so the existing architecture
  // remains compatible.
  // ===================================================

  Future<void> startLocationTracking(
    void Function(String) showSnack,
  ) async {
    await stopLocationTracking();

    final bool allowed =
        await _checkLocationPermission(
      showSnack,
    );

    if (!allowed) {
      return;
    }

    const LocationSettings locationSettings =
        LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 3,
    );

    _positionStream =
        Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen(
      (Position newPosition) {
        // IMPORTANT:
        //
        // DO NOT replace `position` here.
        //
        // The simulation needs to control position
        // itself.
        //
        // Real GPS is intentionally ignored during
        // demo simulation.

        debugPrint(
          'REAL GPS -> '
          '${newPosition.latitude}, '
          '${newPosition.longitude}',
        );
      },
      onError: (Object error) {
        debugPrint(
          'GPS stream error: $error',
        );
      },
    );

    onStateChanged();
  }

  // ===================================================
  // STOP GPS TRACKING
  // ===================================================

  Future<void> stopLocationTracking() async {
    await _positionStream?.cancel();

    _positionStream = null;

    onStateChanged();
  }

  // ===================================================
  // CREATE SIMULATED POSITION
  // ===================================================

  Position _createSimulationPosition(
    SimulationPoint point,
  ) {
    return Position(
      latitude: point.latitude,
      longitude: point.longitude,
      timestamp: DateTime.now(),
      accuracy: 3.0,
      altitude: 0.0,
      altitudeAccuracy: 3.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: speedKmh / 3.6,
      speedAccuracy: 0.5,
      floor: null,
      isMocked: true,
    );
  }

  // ===================================================
  // UPDATE SIMULATION POSITION
  // ===================================================

  void _updateSimulationPosition() {
    if (currentStep < 1 ||
        currentStep > kTotalSteps) {
      return;
    }

    final List<SimulationPoint> route =
        simulationRoute;

    final SimulationPoint point =
        route[currentStep - 1];

    position =
        _createSimulationPosition(point);

    debugPrint(
      'SIMULATION GPS -> '
      'Step: $currentStep/$kTotalSteps | '
      'Latitude: ${point.latitude} | '
      'Longitude: ${point.longitude}',
    );
  }

  // ===================================================
  // START SIMULATION
  // ===================================================

  Future<void> startSimulation(
    void Function(String) showSnack,
  ) async {
    if (!backendAlive) {
      showSnack(
        'Connect a working backend URL first',
      );

      return;
    }

    // Cancel leftover cooldown.
    _cooldownTimer?.cancel();

    _cooldownTimer = null;

    // Verify GPS permission.
    //
    // We still require GPS permission because this
    // application uses GPS in its normal operation.
    //
    // The actual demo movement uses simulated
    // coordinates.

    final Position? realGps =
        await getLocation(showSnack);

    if (realGps == null) {
      return;
    }

    // =================================================
    // GET SAVED DEMO POTHOLE ID
    // =================================================

    final SharedPreferences prefs =
        await SharedPreferences.getInstance();

    _activePotholeId =
        prefs.getString(
          kDemoPotholeIdKey,
        ) ??
        kPotholeIdFallback;

    // =================================================
    // RESET SIMULATION
    // =================================================

    running = true;

    inCooldown = false;

    cooldownRemaining = 0;

    currentStep = 0;

    secondsRemaining =
        stepDurationFor(1);

    lastAlert = null;

    lastTriggeredLevel =
        AlertLevel.none;

    statusMsg =
        'Starting demo route…';

    onStateChanged();

    // =================================================
    // GPS STREAM
    // =================================================

    await startLocationTracking(
      showSnack,
    );

    // =================================================
    // STEP 1
    // =================================================

    await _runStep();

    if (!running) {
      return;
    }

    // =================================================
    // TIMER
    // =================================================

    _tickTimer =
        Timer.periodic(
      const Duration(seconds: 1),
      (_) async {
        if (!running) {
          return;
        }

        secondsRemaining--;

        onStateChanged();

        if (secondsRemaining <= 0) {
          if (currentStep >= kTotalSteps) {
            await _completeSimulation();

            return;
          }

          await _runStep();

          if (running) {
            secondsRemaining =
                stepDurationFor(
              currentStep,
            );

            onStateChanged();
          }
        }
      },
    );
  }

  // ===================================================
  // RUN ONE STEP
  // ===================================================

  Future<void> _runStep() async {
    if (!running &&
        currentStep != 0) {
      return;
    }

    currentStep++;

    // =================================================
    // UPDATE SIMULATED GPS
    // =================================================

    _updateSimulationPosition();

    final bool isLast =
        currentStep >= kTotalSteps;

    final int nextDur =
        isLast
            ? 0
            : stepDurationFor(
                currentStep + 1,
              );

    // =================================================
    // STATUS
    // =================================================

    if (currentStep == 1) {
      statusMsg =
          'Step 1 of 6 — approaching pothole';
    } else if (currentStep == 2) {
      statusMsg =
          'Step 2 of 6 — pothole getting closer';
    } else if (currentStep == 3) {
      statusMsg =
          'Step 3 of 6 — WARNING BUZZER ACTIVE';
    } else if (currentStep == 4) {
      statusMsg =
          'Step 4 of 6 — pothole very close';
    } else if (currentStep == 5) {
      statusMsg =
          'Step 5 of 6 — DANGER WARNING';
    } else {
      statusMsg =
          'Step 6 of 6 — DESTINATION REACHED';
    }

    onStateChanged();

    // =================================================
    // CALL BACKEND
    // =================================================

    await _poll();

    // =================================================
    // AFTER POLL
    // =================================================

    statusMsg = isLast
        ? 'Destination reached — starting cooldown…'
        : 'Step $currentStep of $kTotalSteps complete '
            '· next in ${nextDur}s';

    // Make buzzer status visible in UI.
    if (currentStep == 3) {
      statusMsg =
          '⚠ WARNING BUZZER — '
          'pothole approaching';
    }

    if (currentStep == 4) {
      statusMsg =
          '⚠ BUZZER ACTIVE — '
          'pothole very close';
    }

    if (currentStep == 5) {
      statusMsg =
          '🚨 DANGER WARNING — '
          'pothole extremely close';
    }

    if (currentStep == 6) {
      statusMsg =
          '🚨 DESTINATION REACHED — '
          'pothole zone';
    }

    onStateChanged();

    // =================================================
    // LAST STEP
    // =================================================

    if (isLast) {
      await Future.delayed(
        const Duration(seconds: 1),
      );

      await _completeSimulation();
    }
  }

  // ===================================================
  // POLL BACKEND
  // ===================================================

  Future<void> _poll() async {
    if (position == null) {
      return;
    }

    // =================================================
    // SIMULATED GPS DEBUG
    // =================================================

    debugPrint(
      '================================================',
    );

    debugPrint(
      'SIMULATION STEP $currentStep/$kTotalSteps',
    );

    debugPrint(
      'Latitude  : ${position!.latitude}',
    );

    debugPrint(
      'Longitude : ${position!.longitude}',
    );

    debugPrint(
      'Accuracy  : ${position!.accuracy}m',
    );

    debugPrint(
      'Destination Latitude  : $kSimLat',
    );

    debugPrint(
      'Destination Longitude : $kSimLng',
    );

    debugPrint(
      '================================================',
    );

    // =================================================
    // BACKEND SIMULATION
    // =================================================

    final PotholeAlert alert =
        await ApiService.instance.simulateStep(
      potholeId: _activePotholeId,
      step: currentStep - 1,
      condition: weather,
    );

    // =================================================
    // FORCE DEMO ALERT LEVEL
    // =================================================

    final AlertLevel level =
        levelForStep(currentStep);

    final PotholeAlert stagedAlert =
        PotholeAlert(
      level: level,
      message:
          alert.message.isNotEmpty
              ? alert.message
              : fallbackMsg(level),
      distance: alert.distance,
      severity: alert.severity,
      weatherNote: alert.weatherNote,
    );

    lastAlert = stagedAlert;

    onStateChanged();

    // =================================================
    // TRIGGER ALERT ONLY WHEN LEVEL CHANGES
    //
    // Step 1:
    //     Stage 1
    //
    // Step 3:
    //     Stage 2 -> BUZZER/WARNING
    //
    // Step 5:
    //     Stage 3 -> DANGER/SIREN
    // =================================================

    if (level != lastTriggeredLevel) {
      lastTriggeredLevel = level;

      debugPrint(
        'ALERT TRIGGERED: $level',
      );

      await AlertService.instance.trigger(
        stagedAlert,
      );
    }
  }

  // ===================================================
  // COMPLETE SIMULATION
  // ===================================================

  Future<void> _completeSimulation() async {
    _tickTimer?.cancel();

    _tickTimer = null;

    // Stop GPS stream.
    await stopLocationTracking();

    // Stop current alert/siren.
    AlertService.instance.stopAlert();

    running = false;

    inCooldown = true;

    cooldownRemaining =
        kCooldownDurationSec;

    statusMsg =
        'Simulation complete — pothole zone '
        'clearing in '
        '${fmtCountdown(
      cooldownRemaining,
    )}';

    onStateChanged();

    // =================================================
    // COOLDOWN TIMER
    // =================================================

    _cooldownTimer =
        Timer.periodic(
      const Duration(seconds: 1),
      (Timer timer) {
        cooldownRemaining--;

        statusMsg =
            'Pothole zone clearing in '
            '${fmtCountdown(
          cooldownRemaining,
        )}…';

        onStateChanged();

        if (cooldownRemaining <= 0) {
          timer.cancel();

          _cooldownTimer = null;

          inCooldown = false;

          lastAlert = null;

          lastTriggeredLevel =
              AlertLevel.none;

          // Keep destination visible after
          // simulation until another simulation starts.

          statusMsg =
              'All clear — pothole zone passed ✅';

          onStateChanged();
        }
      },
    );
  }

  // ===================================================
  // STOP SIMULATION
  // ===================================================

  Future<void> stopSimulation() async {
    _tickTimer?.cancel();

    _tickTimer = null;

    _cooldownTimer?.cancel();

    _cooldownTimer = null;

    // Stop GPS.
    await stopLocationTracking();

    // Stop buzzer/siren/torch.
    AlertService.instance.stopAlert();

    running = false;

    inCooldown = false;

    cooldownRemaining = 0;

    lastAlert = null;

    lastTriggeredLevel =
        AlertLevel.none;

    currentStep = 0;

    secondsRemaining = 0;

    statusMsg =
        'Simulation stopped';

    onStateChanged();
  }

  // ===================================================
  // DISPOSE
  // ===================================================

  Future<void> dispose() async {
    _tickTimer?.cancel();

    _tickTimer = null;

    _cooldownTimer?.cancel();

    _cooldownTimer = null;

    await stopLocationTracking();

    AlertService.instance.stopAlert();
  }
}