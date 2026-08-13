import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:torch_light/torch_light.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'api_service.dart';

class AlertService {
  AlertService._();
  static final AlertService instance = AlertService._();

  final AudioPlayer _player = AudioPlayer();

  Timer? _flashTimer;
  bool _torchOn = false;

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
    await _player.stop();

    // Always reset looping before a new alert.
    await _player.setReleaseMode(ReleaseMode.release);

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
  // STAGE 1
  // =====================================================

  Future<void> _stage1() async {
    try {
      await _player.stop();

      await _player.setReleaseMode(ReleaseMode.release);
      await _player.setVolume(1.0);

      print('[AlertService] Playing Stage 1 sound');

      await _player.play(
        AssetSource('sounds/beep_soft.mp3'),
      );

      print('[AlertService] Stage 1 sound started');
    } catch (e) {
      print('[AlertService] STAGE 1 AUDIO ERROR: $e');
    }
  }

  // =====================================================
  // STAGE 2
  // =====================================================

  Future<void> _stage2() async {
    try {
      await _player.stop();

      await _player.setReleaseMode(ReleaseMode.release);
      await _player.setVolume(1.0);

      print('[AlertService] Playing Stage 2 sound');

      await _player.play(
        AssetSource('sounds/alert_medium.mp3'),
      );

      print('[AlertService] Stage 2 sound started');
    } catch (e) {
      print('[AlertService] STAGE 2 AUDIO ERROR: $e');
    }

    // 3 quick flashes
    for (int i = 0; i < 3; i++) {
      await _flashOn();

      await Future.delayed(
        const Duration(milliseconds: 150),
      );

      await _flashOff();

      await Future.delayed(
        const Duration(milliseconds: 150),
      );
    }
  }

  // =====================================================
  // STAGE 3
  // =====================================================

  Future<void> _stage3() async {
    try {
      await _player.stop();

      await _player.setVolume(1.0);
      await _player.setReleaseMode(ReleaseMode.loop);

      print('[AlertService] Playing Stage 3 siren');

      await _player.play(
        AssetSource('sounds/siren.mp3'),
      );

      print('[AlertService] Stage 3 siren started');
    } catch (e) {
      print('[AlertService] STAGE 3 AUDIO ERROR: $e');
    }

    // Continuous flashlight.
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
      await _player.stop();
      await _player.setReleaseMode(ReleaseMode.release);
    } catch (e) {
      print('[AlertService] stop audio error: $e');
    }
  }

  // =====================================================
  // FLASH
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

    await _player.stop();
    await _player.dispose();
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
          channelDescription:
              'Pothole and road hazard warnings',
          importance:
              alert.level == AlertLevel.stage3
                  ? Importance.max
                  : Importance.high,
          priority: Priority.high,
          enableVibration: true,
          playSound: false,
        ),
      ),
    );
  }
}
