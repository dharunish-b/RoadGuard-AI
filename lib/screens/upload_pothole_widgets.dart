import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';

// =====================================================
// UPLOAD POTHOLE — DISPLAY WIDGETS
// Pure UI pieces used by UploadPotholePage. Split out of
// upload_pothole.dart so that file stays focused on the
// step flow / GPS / upload logic.
// =====================================================

// ===================================================
// STEP INDICATOR — 3 steps
// ===================================================

class StepIndicator extends StatelessWidget {
  final int activeStep;
  const StepIndicator({super.key, required this.activeStep});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _stepDot(number: 1, label: 'Photo',
            active: activeStep == 1, done: activeStep > 1),
        _stepLine(done: activeStep > 1),
        _stepDot(number: 2, label: 'Walk',
            active: activeStep == 2, done: activeStep > 2),
        _stepLine(done: activeStep > 2),
        _stepDot(number: 3, label: 'GPS',
            active: activeStep == 3, done: false),
      ],
    );
  }

  Widget _stepLine({required bool done}) {
    return Expanded(
      child: Container(
        height: 2,
        color: done ? const Color(0xFF238636) : const Color(0xFF30363D),
      ),
    );
  }

  Widget _stepDot({
    required int number,
    required String label,
    required bool active,
    required bool done,
  }) {
    final Color color = done
        ? const Color(0xFF238636)
        : active
            ? const Color(0xFF1F6FEB)
            : const Color(0xFF30363D);

    return Column(
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Center(
            child: done
                ? const Icon(Icons.check, color: Colors.white, size: 15)
                : Text(
                    '$number',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: active ? const Color(0xFF58A6FF) : Colors.white38,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

// ===================================================
// ACCURACY CARD — live GPS display
// ===================================================

class AccuracyCard extends StatelessWidget {
  final Position? livePosition;
  const AccuracyCard({super.key, required this.livePosition});

  @override
  Widget build(BuildContext context) {
    final pos = livePosition;
    final double? accuracy = pos?.accuracy;

    final bool accuracyGood = accuracy != null && accuracy <= 10.0;

    Color accuracyColor;
    String accuracyLabel;
    if (accuracy == null) {
      accuracyColor = Colors.white38;
      accuracyLabel = 'Acquiring…';
    } else if (accuracy <= 5) {
      accuracyColor = const Color(0xFF2ECC71);
      accuracyLabel = 'Excellent';
    } else if (accuracy <= 10) {
      accuracyColor = const Color(0xFF27AE60);
      accuracyLabel = 'Good  ✓';
    } else if (accuracy <= 20) {
      accuracyColor = Colors.orange;
      accuracyLabel = 'Fair';
    } else {
      accuracyColor = Colors.red;
      accuracyLabel = 'Weak';
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        border: Border.all(
          color: accuracyGood
              ? const Color(0xFF238636)
              : const Color(0xFF30363D),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Row(
            children: [
              Icon(
                pos == null ? Icons.gps_not_fixed : Icons.gps_fixed,
                color: accuracyColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Text(
                'Live GPS Accuracy',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const Spacer(),
              if (pos == null)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white38,
                  ),
                ),
            ],
          ),

          const SizedBox(height: 14),

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                pos == null
                    ? '—'
                    : '± ${accuracy!.toStringAsFixed(1)} m',
                style: TextStyle(
                  color: accuracyColor,
                  fontSize: 36,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  accuracyLabel,
                  style: TextStyle(
                    color: accuracyColor,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Accuracy bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pos == null
                  ? null
                  : (1.0 - ((accuracy! - 1).clamp(0, 29) / 29))
                      .clamp(0.0, 1.0),
              backgroundColor: const Color(0xFF30363D),
              valueColor: AlwaysStoppedAnimation<Color>(accuracyColor),
              minHeight: 7,
            ),
          ),

          const SizedBox(height: 10),

          Text(
            accuracyGood
                ? '✓  Ready — tap Confirm & Upload below'
                : 'Stand still and wait for GPS to lock. Open sky works best.',
            style: TextStyle(
              color: accuracyGood
                  ? const Color(0xFF2ECC71)
                  : Colors.white38,
              fontSize: 12,
            ),
          ),

          // Live coordinates
          if (pos != null) ...[
            const SizedBox(height: 12),
            const Divider(color: Color(0xFF30363D), height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.location_pin,
                    color: Colors.white24, size: 14),
                const SizedBox(width: 6),
                Text(
                  '${pos.latitude.toStringAsFixed(6)},   '
                  '${pos.longitude.toStringAsFixed(6)}',
                  style: const TextStyle(
                    color: Colors.white24,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ===================================================
// CONFIRM BUTTON
// ===================================================

class ConfirmButton extends StatelessWidget {
  final Position? livePosition;
  final bool uploading;
  final VoidCallback onConfirm;

  const ConfirmButton({
    super.key,
    required this.livePosition,
    required this.uploading,
    required this.onConfirm,
  });

  @override
  Widget build(BuildContext context) {
    final pos = livePosition;
    final bool accuracyGood =
        pos != null && pos.accuracy <= 10.0;

    return SizedBox(
      height: 52,
      child: ElevatedButton.icon(
        onPressed: (accuracyGood && !uploading) ? onConfirm : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF1F6FEB),
          foregroundColor: Colors.white,
          disabledBackgroundColor:
              const Color(0xFF1F6FEB).withOpacity(0.25),
          disabledForegroundColor: Colors.white30,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          elevation: 0,
        ),
        icon: uploading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.check_circle),
        label: Text(
          uploading
              ? 'Uploading…'
              : accuracyGood
                  ? 'Confirm Location & Upload'
                  : 'Waiting for GPS accuracy…',
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}

// ===================================================
// RESULT CARD — identical to original
// ===================================================

class ResultCard extends StatelessWidget {
  final UploadResult result;
  const ResultCard({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final r = result;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: r.success
            ? const Color(0xFF238636).withOpacity(0.2)
            : Colors.red.withOpacity(0.2),
        border: Border.all(
          color: r.success ? const Color(0xFF238636) : Colors.red,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                r.success ? Icons.check_circle : Icons.error,
                color: r.success ? const Color(0xFF2ECC71) : Colors.red,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                r.success ? 'Uploaded!' : 'Upload Failed',
                style: TextStyle(
                  color: r.success ? const Color(0xFF2ECC71) : Colors.red,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(r.message,
              style: const TextStyle(color: Colors.white70, fontSize: 13)),
          if (r.detectionLabel != null) ...[
            const SizedBox(height: 4),
            Text('Detected: ${r.detectionLabel}',
                style:
                    const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
          if (r.severity != null) ...[
            const SizedBox(height: 4),
            Text(
              'Severity: ${(r.severity! * 100).toStringAsFixed(0)}%',
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
          if (r.alertStage != null) ...[
            const SizedBox(height: 4),
            Text('Alert Stage: ${r.alertStage}',
                style:
                    const TextStyle(color: Colors.white54, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}
