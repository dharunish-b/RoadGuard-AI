import '../services/api_service.dart';
import '../constants/simulation_coords.dart';

// =====================================================
// SIMULATION CONFIGURATION
//
// 7 simulation steps, 10 seconds each.
// TOTAL = 70 SECONDS (1:10)
//
// Speed curve mimics a real vehicle:
//   Step 1 -> 0 km/h   (start)
//   Step 2-3 -> ramp up
//   Step 4 -> peak speed (mid-route)
//   Step 5-6 -> braking
//   Step 7 -> near-stop, closest approach
//
// Destination (real pothole location — never reached
// exactly by the simulated route):
//     kSimLat = 9.9252
//     kSimLng = 78.1198
//
// Step 7 is the CLOSEST approach point, still short of
// the actual pothole coordinates. Danger alarm (stage3)
// fires from step 6 through step 7.
// =====================================================

const int kTotalSteps = 7;

const int kCooldownDurationSec = 180;

/// Duration of each simulation step. 7 x 10s = 70s total.
int stepDurationFor(int step) => switch (step) {
      1 => 10,
      2 => 10,
      3 => 10,
      4 => 10,
      5 => 10,
      6 => 10,
      _ => 10,
    };

/// Speed multiplier per step.
///
/// speedKmh (set by user, e.g. 20 or 40) is the PEAK speed.
/// 0 at start -> ramp up -> peak at step 4 (mid) -> brake
/// down toward near-stop at step 7 (danger zone).
double speedMultiplierFor(int step) => switch (step) {
      1 => 0.0,
      2 => 0.3,
      3 => 0.6,
      4 => 1.0,
      5 => 0.7,
      6 => 0.4,
      _ => 0.15,
    };

/// Alert level for each simulation step.
///
/// Step 1-2:  Stage 1 = early caution / light buzzer
/// Step 3-5:  Stage 2 = warning / buzzer
/// Step 6-7:  Stage 3 = danger / siren (closest approach,
///            held for 20s so it's clearly audible)
AlertLevel levelForStep(int step) => switch (step) {
      1 || 2 => AlertLevel.stage1,
      3 || 4 || 5 => AlertLevel.stage2,
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

/// Demo route — 7 points.
///
/// Step 1 = far from pothole
/// Step 2-5 = progressively closer
/// Step 6 = danger zone begins
/// Step 7 = closest approach point (still short of the
///          actual pothole coords — alarm fires here)
///
/// NOTE: No step ever equals kSimLat/kSimLng exactly.
/// The route approaches the pothole and stops one notch
/// before it.
List<SimulationPoint> get simulationRoute {
  return [
    SimulationPoint(
      latitude: kSimLat - 0.0020,
      longitude: kSimLng - 0.0020,
    ),
    SimulationPoint(
      latitude: kSimLat - 0.0016,
      longitude: kSimLng - 0.0016,
    ),
    SimulationPoint(
      latitude: kSimLat - 0.0012,
      longitude: kSimLng - 0.0012,
    ),
    SimulationPoint(
      latitude: kSimLat - 0.0009,
      longitude: kSimLng - 0.0009,
    ),
    SimulationPoint(
      latitude: kSimLat - 0.0006,
      longitude: kSimLng - 0.0006,
    ),
    SimulationPoint(
      latitude: kSimLat - 0.0003,
      longitude: kSimLng - 0.0003,
    ),
    SimulationPoint(
      latitude: kSimLat - 0.0001,
      longitude: kSimLng - 0.0001,
    ),
  ];
}
