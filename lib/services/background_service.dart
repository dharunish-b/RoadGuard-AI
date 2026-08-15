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
// INIT — call once in main() before runApp()
// =====================================================

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  // ── Initialize notification plugin (main isolate only) ────────────
  // This instance lives in the MAIN isolate. The background isolate
  // gets its own separate Dart VM and must call initialize() itself.
  final plugin = FlutterLocalNotificationsPlugin();

  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    // Fires when the app IS open and the user taps the boot notification.
    onDidReceiveNotificationResponse: _onBootTapForeground,
    // Fires when the app is NOT open (just after reboot, e.g.).
    // MUST be a top-level @pragma('vm:entry-point') function.
    onDidReceiveBackgroundNotificationResponse: _onBootTapBackground,
  );

  final androidImpl =
      plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  // Silent persistent foreground notification channel
  await androidImpl?.createNotificationChannel(
    const AndroidNotificationChannel(
      kForegroundChannelId,
      'Road Guard AI',
      description: 'Road Guard is actively monitoring for potholes',
      importance: Importance.low,
    ),
  );

  // High-priority hazard alert channel (stage 2 / 3 pop-ups)
  await androidImpl?.createNotificationChannel(
    const AndroidNotificationChannel(
      kAlertChannelId,
      'Hazard Alerts',
      description: 'Pothole and road hazard warnings',
      importance: Importance.max,
    ),
  );

  // Boot consent channel (YES / No prompt after reboot)
  await androidImpl?.createNotificationChannel(
    const AndroidNotificationChannel(
      kBootChannelId,
      'Boot Prompt',
      description: 'Asks if you want to resume monitoring after restart',
      importance: Importance.high,
    ),
  );

  // ── Configure background service ──────────────────────────────────
  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onServiceStart,
      autoStart: false,        // never starts unless we call startService()
      autoStartOnBoot: true,   // plugin's BroadcastReceiver fires on reboot
                               // → we intercept in the consent gate below
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
//
// Both MUST be top-level @pragma functions — never closures
// or instance methods — so the AOT compiler keeps them.
// =====================================================

@pragma('vm:entry-point')
void _onBootTapForeground(NotificationResponse response) {
  _handleBootResponse(response);
}

@pragma('vm:entry-point')
void _onBootTapBackground(NotificationResponse response) {
  // Runs in a separate tiny isolate spawned by the notification system.
  // Calling async functions is fine here.
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
// Call in HomeScreen RIGHT BEFORE service.startService()
// =====================================================

Future<void> markExplicitStart() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kExplicitStartPref, true);
}

// =====================================================
// SERVICE ENTRY POINT
// Runs in the BACKGROUND ISOLATE — completely separate
// Dart VM from the main isolate. No shared memory.
//
// Called in exactly two situations:
//   A) User pressed START (explicitStart = true)  → monitor
//   B) Android rebooted  (explicitStart = false)  → ask first
// =====================================================

@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) async {
  // The background isolate has its own fresh Dart VM.
  // Load the persisted ngrok URL from SharedPreferences.
  await ApiConfig.load();

  final prefs        = await SharedPreferences.getInstance();
  final bool explicit = prefs.getBool(kExplicitStartPref) ?? false;

  // =============================================================
  // PATH B — Android relaunched us (reboot or system restart).
  //
  // FIX: isForegroundMode:true means Android expects a foreground
  // notification within ~5 seconds or it kills the service (ANR).
  // We MUST call setForegroundNotificationInfo() immediately here,
  // BEFORE the async notification show(), or the service is killed
  // before the boot prompt ever appears.
  // =============================================================
  if (!explicit) {
    // Satisfy Android's foreground notification requirement first.
    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: 'Road Guard AI',
        content: 'Tap to resume monitoring…',
      );
    }

    // Now show the boot consent prompt (YES / No thanks).
    await _showBootConsentPrompt(service);

    // Stop the service — we're just a messenger, not monitoring yet.
    service.stopSelf();
    return;
  }

  // =============================================================
  // PATH A — Explicit user start (START button or YES on prompt).
  // =============================================================

  // Consume the one-shot flag so future silent relaunches don't
  // bypass the consent gate.
  await prefs.setBool(kExplicitStartPref, false);

  // Update foreground notification to "Active" now that we know
  // we're actually monitoring. This is the fix for the missing
  // "Monitoring active" notification after pressing START.
  if (service is AndroidServiceInstance) {
    await service.setForegroundNotificationInfo(
      title: '🛡️ Road Guard AI — Active',
      content: 'Monitoring your location for potholes',
    );
  }

  // Handle STOP signal from HomeScreen.
  // Also kill any live siren/torch — they live in THIS isolate now,
  // so stopping the service alone won't silence them.
  service.on('stop').listen((_) async {
    await AlertService.instance.stopAlert();
    service.stopSelf();
  });

  // Receive config updates from the UI (speed, weather, backend URL)
  double speedKmh = 30.0;
  String weather  = 'dry';

  service.on('config').listen((data) async {
    if (data == null) return;
    speedKmh = (data['speed_kmh'] as num?)?.toDouble() ?? speedKmh;
    weather  = data['weather']   as String? ?? weather;
    final url = data['base_url'] as String?;
    if (url != null && url.trim().isNotEmpty) {
      await ApiConfig.setBaseUrl(url.trim());
    }
    // Reflect current config in the foreground notification
    if (service is AndroidServiceInstance) {
      await service.setForegroundNotificationInfo(
        title: '🛡️ Road Guard AI — Active',
        content: '${speedKmh.toInt()} km/h · $weather · scanning…',
      );
    }
  });

  // Tracks the last alert level so we only re-trigger hardware on a
  // CHANGE of stage, not every single 10s poll. Without this, a
  // continuous stage3 would restart the looping siren + torch timer
  // every 10 seconds, causing an audible stutter.
  AlertLevel lastAlertLevel = AlertLevel.none;

  // GPS poll + backend proximity check every 10 seconds
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;

      final LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;

      final Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final PotholeAlert alert = await ApiService.instance.checkNearby(
        lat:      pos.latitude,
        lng:      pos.longitude,
        speedKmh: speedKmh,
        weather:  weather,
      );

      // NEW — fire beep/torch/siren directly from THIS isolate.
      // This is what makes real-time alerts work whether the app
      // is foregrounded, backgrounded, or the screen is off — the
      // background isolate keeps running as long as the foreground
      // service notification is alive.
      // Only re-trigger on a stage CHANGE so a sustained stage3
      // siren doesn't restart every poll cycle.
      if (alert.level != lastAlertLevel) {
        await AlertService.instance.trigger(alert);
        lastAlertLevel = alert.level;
      }

      // Push alert level to the UI isolate too — purely for the
      // in-app banner/state, NOT for triggering sound/torch again.
      // (Main isolate must not call AlertService.trigger anymore,
      // or you'd get double beeps/double flashes when app is open.)
      service.invoke('alert', {
        'level':    alert.level.index,
        'message':  alert.message,
        'distance': alert.distance,
        'severity': alert.severity,
      });

      // Heads-up notification for stage 2 / 3 hazards
      await AlertNotificationHelper.showHazardNotification(alert);

      // Keep the foreground notification live with last-checked time
      if (service is AndroidServiceInstance) {
        final now     = DateTime.now();
        final timeStr =
            '${now.hour.toString().padLeft(2, '0')}:'
            '${now.minute.toString().padLeft(2, '0')}';

        final String content = alert.level == AlertLevel.none
            ? 'All clear · last checked $timeStr'
            : '⚠️ ${alert.message} · $timeStr';

        await service.setForegroundNotificationInfo(
          title: '🛡️ Road Guard AI — Active',
          content: content,
        );
      }
    } catch (_) {
      // Never crash the background service
    }
  });
}

// =====================================================
// BOOT CONSENT PROMPT (runs inside background isolate)
//
// The background isolate has its OWN Dart VM — it has no
// access to the FlutterLocalNotificationsPlugin instance
// initialized in main(). We create a fresh local instance
// here and initialize it before calling show().
// =====================================================

Future<void> _showBootConsentPrompt(ServiceInstance service) async {
  final prefs = await SharedPreferences.getInstance();
  if (!(prefs.getBool(kMonitoringPref) ?? false)) return;

  // Fresh plugin instance for this isolate
  final plugin = FlutterLocalNotificationsPlugin();

  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    // Only the background handler matters here — the main isolate
    // registers the foreground handler when the app opens.
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
            showsUserInterface: true,   // opens the app
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