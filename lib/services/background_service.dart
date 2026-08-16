import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'alert_service.dart';

// =====================================================
// CHANNEL / NOTIFICATION IDs
// =====================================================

const String kForegroundChannelId = 'road_guard_channel';
const String kAlertChannelId      = 'road_guard_alerts';
const String kBootChannelId       = 'road_guard_boot';

const int kForegroundNotifId = 1;
const int kBootPromptNotifId = 2;

// =====================================================
// SHARED PREFERENCES KEYS
// =====================================================

const String kMonitoringPref    = 'monitoring_active';
const String kExplicitStartPref = 'explicit_start_requested';

// =====================================================
// MOVEMENT GATE CONSTANTS
// =====================================================

/// Minimum speed (km/h) before we bother hitting the backend.
/// Below this we treat the rider as stationary — no DB query, no alert.
/// Prevents battery drain and pointless $nearSphere calls at red lights.
const double kMinSpeedKmh = 3.0;

/// GPS accuracy must be better than this (metres) to use the reading.
/// A 200m accuracy reading would trigger alerts for potholes 200m off-course.
const double kMaxAccuracyM = 40.0;

/// How long since the last position fix before we consider GPS stale.
/// Stale = don't query backend; wait for fresh fix instead.
const Duration kMaxPositionAge = Duration(seconds: 8);

/// Real-time poll interval — how often the background loop checks GPS
/// and queries /alert. 2 seconds gives ~1 second of total alert latency
/// (1s GPS fix + 1s network) which is well inside any d_alert_m window
/// even at 40 km/h (d_alert ≈ 35 m ÷ 11 m/s ≈ 3s to impact).
const Duration kPollInterval = Duration(seconds: 2);

// =====================================================
// INIT — call once in main() before runApp()
// =====================================================

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  final plugin = FlutterLocalNotificationsPlugin();

  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: _onBootTapForeground,
    onDidReceiveBackgroundNotificationResponse: _onBootTapBackground,
  );

  final androidImpl =
      plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  await androidImpl?.createNotificationChannel(
    const AndroidNotificationChannel(
      kForegroundChannelId,
      'Road Guard AI',
      description: 'Road Guard is actively monitoring for potholes',
      importance: Importance.low,
    ),
  );

  await androidImpl?.createNotificationChannel(
    const AndroidNotificationChannel(
      kAlertChannelId,
      'Hazard Alerts',
      description: 'Pothole and road hazard warnings',
      importance: Importance.max,
    ),
  );

  await androidImpl?.createNotificationChannel(
    const AndroidNotificationChannel(
      kBootChannelId,
      'Boot Prompt',
      description: 'Asks if you want to resume monitoring after restart',
      importance: Importance.high,
    ),
  );

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onServiceStart,
      autoStart: false,
      autoStartOnBoot: true,
      isForegroundMode: true,
      notificationChannelId: kForegroundChannelId,
      initialNotificationTitle: 'Road Guard AI',
      initialNotificationContent: 'Starting…',
      foregroundServiceNotificationId: kForegroundNotifId,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onServiceStart,
    ),
  );
}

// =====================================================
// NOTIFICATION TAP HANDLERS
// =====================================================

@pragma('vm:entry-point')
void _onBootTapForeground(NotificationResponse response) {
  _handleBootResponse(response);
}

@pragma('vm:entry-point')
void _onBootTapBackground(NotificationResponse response) {
  _handleBootResponse(response);
}

Future<void> _handleBootResponse(NotificationResponse response) async {
  final prefs = await SharedPreferences.getInstance();
  if (response.actionId == 'action_yes') {
    await prefs.setBool(kExplicitStartPref, true);
    await prefs.setBool(kMonitoringPref, true);
    await FlutterBackgroundService().startService();
  } else if (response.actionId == 'action_no') {
    await prefs.setBool(kMonitoringPref, false);
  }
}

// =====================================================
// SAVE MONITORING STATE — call from HomeScreen toggle
// =====================================================

Future<void> saveMonitoringState(bool isActive) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kMonitoringPref, isActive);
}

// =====================================================
// MARK EXPLICIT USER START
// =====================================================

Future<void> markExplicitStart() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kExplicitStartPref, true);
}

// =====================================================
// SERVICE ENTRY POINT
// =====================================================

@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) async {
  await ApiConfig.load();

  final prefs         = await SharedPreferences.getInstance();
  final bool explicit = prefs.getBool(kExplicitStartPref) ?? false;

  // ── PATH B: Boot relaunch — show consent prompt ───────────────
  if (!explicit) {
    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: 'Road Guard AI',
        content: 'Tap to resume monitoring…',
      );
    }
    await _showBootConsentPrompt(service);
    service.stopSelf();
    return;
  }

  // ── PATH A: Explicit user start ───────────────────────────────
  await prefs.setBool(kExplicitStartPref, false);

  if (service is AndroidServiceInstance) {
    await service.setForegroundNotificationInfo(
      title: '🛡️ Road Guard AI — Active',
      content: 'Monitoring your location for potholes',
    );
  }

  // ── Mutable config (updated via 'config' invoke) ──────────────
  double speedKmh  = 30.0;
  String weather   = 'dry';
  String sessionId = '';

  // ── STOP signal from HomeScreen ───────────────────────────────
  service.on('stop').listen((_) async {
    await AlertService.instance.stopAlert();
    service.stopSelf();
  });

  // ── Config updates from UI ────────────────────────────────────
  service.on('config').listen((data) async {
    if (data == null) return;
    speedKmh  = (data['speed_kmh'] as num?)?.toDouble() ?? speedKmh;
    weather   = (data['weather']   as String?)            ?? weather;
    sessionId = (data['session_id'] as String?)           ?? sessionId;

    final url = data['base_url'] as String?;
    if (url != null && url.trim().isNotEmpty) {
      await ApiConfig.setBaseUrl(url.trim());
    }

    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: '🛡️ Road Guard AI — Active',
        content: '${speedKmh.toInt()} km/h · $weather · scanning…',
      );
    }
  });

  // ── Tracking state ────────────────────────────────────────────

  /// Last alert level — we only re-trigger hardware on a CHANGE.
  /// Prevents the looping siren restarting every 2 seconds.
  AlertLevel lastAlertLevel = AlertLevel.none;

  /// Last position that passed all movement-gate checks.
  /// Used to compute derived speed when device speed is unavailable.
  Position? lastValidPosition;

  /// Consecutive below-threshold readings before we silence a live alert.
  /// Avoids flickering the alert off/on if GPS speed stutters for 1 cycle.
  int stationaryCount = 0;
  const int kStationaryThreshold = 3; // 3 × 2s = 6s of stillness → clear alert

  // ── Main polling loop ─────────────────────────────────────────
  // busy flag prevents a new tick from running while the previous
  // one is still awaiting GPS or the backend. If a tick takes
  // longer than kPollInterval the next one is simply skipped —
  // no cascading queue build-up.
  bool busy = false;

  Timer.periodic(kPollInterval, (timer) async {
    if (busy) return;
    busy = true;
    try {
      // ── 1. Location service + permission check ─────────────────
      if (!await Geolocator.isLocationServiceEnabled()) return;

      final LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;

      // ── 2. Get GPS fix ─────────────────────────────────────────
      final Position pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 5),
        ),
      );

      // ── 3. ACCURACY GATE ───────────────────────────────────────
      // Ignore fixes with poor horizontal accuracy.
      // A 200 m accuracy bubble would trigger alerts for potholes
      // on a completely different road.
      if (pos.accuracy > kMaxAccuracyM) {
        _updateForeground(
          service,
          '🛡️ Road Guard AI — Active',
          'Waiting for GPS lock… (accuracy ${pos.accuracy.toStringAsFixed(0)} m)',
        );
        return;
      }

      // ── 4. MOVEMENT GATE ───────────────────────────────────────
      // Prefer device-reported speed (accelerometer-fused).
      // Fall back to Haversine displacement ÷ time if unavailable.
      double effectiveSpeedKmh;

      if (pos.speed >= 0) {
        effectiveSpeedKmh = pos.speed * 3.6;
      } else if (lastValidPosition != null) {
        final double distM = Geolocator.distanceBetween(
          lastValidPosition!.latitude,
          lastValidPosition!.longitude,
          pos.latitude,
          pos.longitude,
        );
        final double dtSec =
            pos.timestamp.difference(lastValidPosition!.timestamp).inMilliseconds /
                1000.0;
        effectiveSpeedKmh = dtSec > 0 ? (distM / dtSec) * 3.6 : 0;
      } else {
        effectiveSpeedKmh = 0;
      }

      lastValidPosition = pos;

      if (effectiveSpeedKmh < kMinSpeedKmh) {
        stationaryCount++;

        if (stationaryCount >= kStationaryThreshold &&
            lastAlertLevel != AlertLevel.none) {
          await AlertService.instance.stopAlert();
          lastAlertLevel = AlertLevel.none;
          service.invoke('alert', {
            'level':    AlertLevel.none.index,
            'message':  'All clear',
            'distance': null,
            'severity': null,
          });
        }

        _updateForeground(
          service,
          '🛡️ Road Guard AI — Active',
          'Stationary · ${effectiveSpeedKmh.toStringAsFixed(1)} km/h',
        );
        return;
      }

      stationaryCount = 0;

      // ── 5. QUERY BACKEND (/alert) ──────────────────────────────
      final PotholeAlert alert = await ApiService.instance.checkNearby(
        lat:      pos.latitude,
        lng:      pos.longitude,
        speedKmh: effectiveSpeedKmh,
        weather:  weather,
      );

      // ── 6. HARDWARE ALERT — only on stage CHANGE ───────────────
      // Prevents looping siren restarting every 2 s (audible glitch).
      if (alert.level != lastAlertLevel) {
        if (alert.level == AlertLevel.none) {
          await AlertService.instance.stopAlert();
        } else {
          await AlertService.instance.trigger(alert);
        }
        lastAlertLevel = alert.level;
      }

      // ── 7. PUSH STATE TO UI ISOLATE ───────────────────────────
      // Main isolate updates the banner — must NOT call
      // AlertService.trigger() again or you get double beeps.
      service.invoke('alert', {
        'level':    alert.level.index,
        'message':  alert.message,
        'distance': alert.distance,
        'severity': alert.severity,
      });

      // ── 8. HEADS-UP NOTIFICATION (stage 2 / 3 only) ───────────
      await AlertNotificationHelper.showHazardNotification(alert);

      // ── 9. UPDATE FOREGROUND NOTIFICATION ─────────────────────
      final now     = DateTime.now();
      final timeStr =
          '${now.hour.toString().padLeft(2, '0')}:'
          '${now.minute.toString().padLeft(2, '0')}';

      final String statusLine = alert.level == AlertLevel.none
          ? '${effectiveSpeedKmh.toStringAsFixed(0)} km/h · clear · $timeStr'
          : '⚠️ ${alert.message} · $timeStr';

      _updateForeground(service, '🛡️ Road Guard AI — Active', statusLine);

    } catch (_) {
      // Never crash the background service on a single poll failure.
    } finally {
      busy = false;
    }
  });
}

// ─── Foreground notification helper ──────────────────────────────────────────

void _updateForeground(
  ServiceInstance service,
  String title,
  String content,
) {
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(title: title, content: content);
  }
}

// =====================================================
// BOOT CONSENT PROMPT
// =====================================================

Future<void> _showBootConsentPrompt(ServiceInstance service) async {
  final prefs = await SharedPreferences.getInstance();
  if (!(prefs.getBool(kMonitoringPref) ?? false)) return;

  final plugin = FlutterLocalNotificationsPlugin();

  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveBackgroundNotificationResponse: _onBootTapBackground,
  );

  final androidImpl =
      plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  await androidImpl?.createNotificationChannel(
    const AndroidNotificationChannel(
      kBootChannelId,
      'Boot Prompt',
      description: 'Asks if you want to resume monitoring after restart',
      importance: Importance.high,
    ),
  );

  await plugin.show(
    kBootPromptNotifId,
    '🛡️ Resume Road Guard monitoring?',
    'You were monitoring before your device restarted.',
    NotificationDetails(
      android: AndroidNotificationDetails(
        kBootChannelId,
        'Boot Prompt',
        channelDescription: 'Resume monitoring prompt',
        importance: Importance.high,
        priority: Priority.high,
        autoCancel: false,
        ongoing: false,
        actions: [
          const AndroidNotificationAction(
            'action_yes',
            'YES, Resume',
            showsUserInterface: true,
            cancelNotification: true,
          ),
          const AndroidNotificationAction(
            'action_no',
            'No thanks',
            cancelNotification: true,
          ),
        ],
      ),
    ),
  );
}