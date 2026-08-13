import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:torch_light/torch_light.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'api_service.dart';

// =====================================================
// ALERT SERVICE
// Manages the 3 alert stages for pothole proximity
//
// Stage 1 — light beep                   (sound only)
// Stage 2 — normal alert + brief flash   (sound + 3 flashes)
// Stage 3 — extreme alarm + cont. flash  (sound + continuous flash)
//
// All methods are safe to call from main or background isolate.
// =====================================================

class AlertService {
  AlertService._();
  static final AlertService instance = AlertService._();

  final AudioPlayer _player = AudioPlayer();
  Timer? _flashTimer;
  bool _torchOn = false;

  // ---------------------------------------------------
  // PUBLIC ENTRY POINT
  // Call this whenever you receive a PotholeAlert
  // ---------------------------------------------------

  Future<void> trigger(PotholeAlert alert) async {
    // Always cancel any running flash loop first
    await _cancelFlash();

    switch (alert.level) {
      case AlertLevel.none:
        // Nothing
        break;
      case AlertLevel.stage1:
        await _stage1();
        break;
      case AlertLevel.stage2:
        await _stage2();
        break;
      case AlertLevel.stage3:
        await _stage3();
        break;
    }
  }

  // ---------------------------------------------------
  // STAGE 1 — single soft beep
  // ---------------------------------------------------

  Future<void> _stage1() async {
    try {
      // Uses a short 440 Hz beep asset (add to assets/sounds/beep_soft.mp3)
      await _player.setVolume(0.5);
      await _player.play(AssetSource('sounds/beep_soft.mp3'));
    } catch (_) {
      // Asset may not exist in dev — silent fail
    }
  }

  // ---------------------------------------------------
  // STAGE 2 — medium alert + 3 short flashes
  // ---------------------------------------------------

  Future<void> _stage2() async {
    try {
      await _player.setVolume(0.85);
      await _player.play(AssetSource('sounds/alert_medium.mp3'));
    } catch (_) {}

    // 3 quick flashes
    for (int i = 0; i < 3; i++) {
      await _flashOn();
      await Future.delayed(const Duration(milliseconds: 150));
      await _flashOff();
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  // ---------------------------------------------------
  // STAGE 3 — loud siren + continuous flash
  // Flash runs until stopAlert() is called or a new trigger comes in
  // ---------------------------------------------------

  Future<void> _stage3() async {
    try {
      await _player.setVolume(1.0);
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.play(AssetSource('sounds/siren.mp3'));
    } catch (_) {}

    // Continuous flash — 200ms on / 200ms off
    _flashTimer = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) async {
        if (_torchOn) {
          await _flashOff();
        } else {
          await _flashOn();
        }
      },
    );
  }

  // ---------------------------------------------------
  // STOP — call when alert clears or app goes to background
  // ---------------------------------------------------

  Future<void> stopAlert() async {
    await _cancelFlash();
    await _player.stop();
    await _player.setReleaseMode(ReleaseMode.release);
  }

  // ---------------------------------------------------
  // FLASH HELPERS
  // ---------------------------------------------------

  Future<void> _flashOn() async {
    try {
      await TorchLight.enableTorch();
      _torchOn = true;
    } catch (_) {}
  }

  Future<void> _flashOff() async {
    try {
      await TorchLight.disableTorch();
      _torchOn = false;
    } catch (_) {}
  }

  Future<void> _cancelFlash() async {
    _flashTimer?.cancel();
    _flashTimer = null;
    await _flashOff();
  }

  // ---------------------------------------------------
  // DISPOSE
  // ---------------------------------------------------

  void dispose() {
    _flashTimer?.cancel();
    _player.dispose();
  }
}

// =====================================================
// NOTIFICATION HELPER — used by background service
// Shows a heads-up notification for stage 2 / 3
// =====================================================

class AlertNotificationHelper {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> showHazardNotification(PotholeAlert alert) async {
    if (alert.level == AlertLevel.none || alert.level == AlertLevel.stage1) {
      return; // Stage 1 is sound-only, no notification needed
    }

    final String title = alert.level == AlertLevel.stage3
        ? '⚠️ SEVERE POTHOLE AHEAD'
        : '⚠️ Pothole Warning';

    final String body = [
      alert.message,
      if (alert.distance != null)
        '${alert.distance!.toStringAsFixed(0)} m ahead',
      if (alert.weatherNote != null) alert.weatherNote!,
    ].join(' · ');

    await _plugin.show(
      42,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'road_guard_alerts',
          'Hazard Alerts',
          channelDescription: 'Pothole and road hazard warnings',
          importance: alert.level == AlertLevel.stage3
              ? Importance.max
              : Importance.high,
          priority: Priority.high,
          enableVibration: true,
          playSound: false, // AudioPlayer handles sound
        ),
      ),
    );
  }
}
