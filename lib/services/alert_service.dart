import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:torch_light/torch_light.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';

class AlertService {
  AlertService._();
  static final AlertService instance = AlertService._();

  final AudioPlayer _player = AudioPlayer();

  Timer? _flashTimer;
  bool _torchOn = false;

  // =====================================================
  // SAFE VIBRATE
  //
  // Does NOT use Vibration.hasVibrator() — that call
  // returns null/false in background isolates even on
  // phones that do have a vibrator (needs main Context).
  // Instead we just attempt vibration directly and catch
  // any error silently. If the device has no vibrator,
  // the plugin throws and we ignore it.
  // =====================================================

  Future<void> _safeVibrate({
    List<int>? pattern,
    List<int>? intensities,
    int? duration,
    int repeat = -1,
  }) async {
    try {
      if (pattern != null) {
        await Vibration.vibrate(
          pattern:     pattern,
          intensities: intensities ?? [],
          repeat:      repeat,
        );
      } else {
        await Vibration.vibrate(duration: duration ?? 300);
      }
    } catch (e) {
      print('[AlertService] vibration error: $e');
    }
  }

  // =====================================================
  // PUBLIC ENTRY POINT
  // =====================================================

  Future<void> trigger(PotholeAlert alert) async {
    print(
      '[AlertService] trigger: '
      'level=${alert.level}, '
      'message=${alert.message}',
    );

    // Stop anything from the previous alert first.
    await _cancelFlash();

    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.release);
    } catch (_) {}

    try {
      await Vibration.cancel();
    } catch (_) {}

    switch (alert.level) {
      case AlertLevel.none:
        print('[AlertService] ALL CLEAR');
        break;

      case AlertLevel.stage1:
        print('[AlertService] STAGE 1');
        await _stage1();
        break;

      case AlertLevel.stage2:
        print('[AlertService] STAGE 2');
        await _stage2();
        break;

      case AlertLevel.stage3:
        print('[AlertService] STAGE 3');
        await _stage3();
        break;
    }
  }

  // =====================================================
  // STAGE 1 — soft beep + single short buzz
  // =====================================================

  Future<void> _stage1() async {
    // Audio — fire and forget so vibration is never blocked
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.release);
      await _player.setVolume(1.0);
      _player.play(AssetSource('sounds/beep_soft.mp3')); // no await
      print('[AlertService] Stage 1 sound started');
    } catch (e) {
      print('[AlertService] STAGE 1 AUDIO ERROR: $e');
    }

    // Single short buzz
    await _safeVibrate(duration: 200);
  }

  // =====================================================
  // STAGE 2 — medium alert + 3 vibration pulses + 3 flashes
  // =====================================================

  Future<void> _stage2() async {
    // Audio — fire and forget
    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.release);
      await _player.setVolume(1.0);
      _player.play(AssetSource('sounds/alert_medium.mp3')); // no await
      print('[AlertService] Stage 2 sound started');
    } catch (e) {
      print('[AlertService] STAGE 2 AUDIO ERROR: $e');
    }

    // 3 vibration pulses — try pattern first, fallback to single buzz
    try {
      await Vibration.vibrate(
        pattern:     [0, 150, 150, 150, 150, 150],
        intensities: [0, 200,   0, 200,   0, 200],
      );
    } catch (e) {
      print('[AlertService] STAGE 2 VIBRATION PATTERN ERROR: $e');
      // Fallback — plain vibration, no amplitude/pattern
      await _safeVibrate(duration: 400);
    }

    // 3 quick flashes — run after vibration starts (not blocked)
    for (int i = 0; i < 3; i++) {
      await _flashOn();
      await Future.delayed(const Duration(milliseconds: 150));
      await _flashOff();
      await Future.delayed(const Duration(milliseconds: 150));
    }
  }

  // =====================================================
  // STAGE 3 — siren loop + continuous vibration + rapid flash
  // =====================================================

  Future<void> _stage3() async {
    // Audio — fire and forget
    try {
      await _player.stop();
      await _player.setVolume(1.0);
      await _player.setReleaseMode(ReleaseMode.loop);
      _player.play(AssetSource('sounds/siren.mp3')); // no await
      print('[AlertService] Stage 3 siren started');
    } catch (e) {
      print('[AlertService] STAGE 3 AUDIO ERROR: $e');
    }

    // Continuous looping vibration
    // repeat: 1 = loop from index 1 indefinitely until Vibration.cancel()
    try {
      await Vibration.vibrate(
        pattern:     [0, 300, 200],
        intensities: [0, 255,   0],
        repeat:      1,
      );
    } catch (e) {
      print('[AlertService] STAGE 3 VIBRATION ERROR: $e');
      // Fallback — long single buzz
      await _safeVibrate(duration: 1000);
    }

    // Continuous flashlight timer
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

  // =====================================================
  // STOP ALERT
  // =====================================================

  Future<void> stopAlert() async {
    print('[AlertService] stopAlert');

    await _cancelFlash();

    try {
      await Vibration.cancel();
    } catch (e) {
      print('[AlertService] stop vibration error: $e');
    }

    try {
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.release);
    } catch (e) {
      print('[AlertService] stop audio error: $e');
    }
  }

  // =====================================================
  // FLASH HELPERS
  // =====================================================

  Future<void> _flashOn() async {
    try {
      await TorchLight.enableTorch();
      _torchOn = true;
    } catch (e) {
      print('[AlertService] Torch ON error: $e');
    }
  }

  Future<void> _flashOff() async {
    try {
      await TorchLight.disableTorch();
      _torchOn = false;
    } catch (e) {
      print('[AlertService] Torch OFF error: $e');
    }
  }

  Future<void> _cancelFlash() async {
    _flashTimer?.cancel();
    _flashTimer = null;

    if (_torchOn) {
      await _flashOff();
    }
  }

  // =====================================================
  // DISPOSE
  // =====================================================

  Future<void> dispose() async {
    _flashTimer?.cancel();
    _flashTimer = null;

    try { await Vibration.cancel(); } catch (_) {}
    try { await _player.stop(); } catch (_) {}
    try { await _player.dispose(); } catch (_) {}
  }
}


// =====================================================
// NOTIFICATION HELPER
// =====================================================

class AlertNotificationHelper {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  static Future<void> showHazardNotification(
    PotholeAlert alert,
  ) async {
    if (alert.level == AlertLevel.none ||
        alert.level == AlertLevel.stage1) {
      return;
    }

    final String title =
        alert.level == AlertLevel.stage3
            ? '⚠️ SEVERE POTHOLE AHEAD'
            : '⚠️ Pothole Warning';

    final String body = [
      alert.message,
      if (alert.distance != null)
        '${alert.distance!.toStringAsFixed(0)} m ahead',
      if (alert.weatherNote != null)
        alert.weatherNote!,
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
          importance:
              alert.level == AlertLevel.stage3
                  ? Importance.max
                  : Importance.high,
          priority:        Priority.high,
          enableVibration: true,
          playSound:       false,
        ),
      ),
    );
  }
}