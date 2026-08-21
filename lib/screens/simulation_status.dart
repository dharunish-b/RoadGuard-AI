import 'simulation_config.dart';

// =====================================================
// STATUS MESSAGE TEXT
//
// Pulled out of the controller so step logic and display
// text can be edited independently. Two moments per step:
//   1. "start" text  -> shown the instant a step begins
//   2. "complete" text -> shown after the backend poll
//      finishes for that step (overridden for buzzer /
//      danger steps so it's obvious in the UI).
// =====================================================

/// Text shown the instant [step] begins.
String statusForStepStart(int step) => switch (step) {
      1 => 'Step 1 of $kTotalSteps — approaching pothole',
      2 => 'Step 2 of $kTotalSteps — pothole getting closer',
      3 => 'Step 3 of $kTotalSteps — WARNING BUZZER ACTIVE',
      4 => 'Step 4 of $kTotalSteps — pothole close, peak speed',
      5 => 'Step 5 of $kTotalSteps — braking, buzzer active',
      6 => 'Step 6 of $kTotalSteps — DANGER, slow crawl',
      _ => 'Step 7 of $kTotalSteps — DANGER, closest point',
    };

/// Text shown after the backend poll for [step] completes.
///
/// [isLast] marks the final step (destination reached).
/// [nextDur] is the duration of the *next* step, used for
/// the "next in Ns" hint.
String statusForStepComplete({
  required int step,
  required bool isLast,
  required int nextDur,
}) {
  if (isLast) {
    return 'Destination reached — starting cooldown…';
  }

  // Buzzer / danger steps get an explicit override so the
  // alert state is obvious in the UI even before the user
  // reads the alert card.
  switch (step) {
    case 3:
      return '⚠ WARNING BUZZER — pothole approaching';
    case 4:
      return '⚠ BUZZER ACTIVE — pothole very close';
    case 5:
      return '⚠ BUZZER ACTIVE — braking';
    case 6:
      return '🚨 DANGER WARNING — pothole extremely close';
    default:
      return 'Step $step of $kTotalSteps complete · next in ${nextDur}s';
  }
}

/// Text shown while the post-simulation cooldown counts down.
String statusForCooldown(int remainingSec) =>
    'Pothole zone clearing in ${fmtCountdown(remainingSec)}…';

/// Text shown once cooldown finishes.
const String statusAllClear = 'All clear — pothole zone passed ✅';

/// Text shown immediately after Start Simulation is pressed.
const String statusStarting = 'Starting demo route…';

/// Text shown when the simulation is manually stopped.
const String statusStopped = 'Simulation stopped';

/// Default text before anything has run.
const String statusIdle = 'Configure and press Start Simulation';
