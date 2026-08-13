import 'dart:async';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import 'alert_service.dart';

// =====================================================
// CONSTANTS
// =====================================================

const String notifChannelId = 'road_guard_channel';
const String alertChannelId = 'road_guard_alerts';
const String bootChannelId = 'road_guard_boot';
const int foregroundNotifId = 1;
const int bootPromptNotifId = 2;

// SharedPreferences keys
// kMonitoringPref     — the user's last known monitoring INTENT
//                       (were they running it before the phone restarted?)
// kExplicitStartPref  — a one-shot flag set right before we call
//                       service.startService() from a real user action
//                       (START button, or tapping YES on the resume
//                       prompt). If onServiceStart() runs WITHOUT this
//                       flag set, it means Android silently relaunched
//                       the service on its own (typically after a
//                       device reboot) — in that case we must NOT start
//                       monitoring; we only ask.
const String kMonitoringPref = 'monitoring_active';
const String kExplicitStartPref = 'explicit_start_requested';

// =====================================================
// INIT — call once in main() before runApp()
// =====================================================

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();
  final FlutterLocalNotificationsPlugin notifPlugin =
      FlutterLocalNotificationsPlugin();

  await notifPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: _onBootNotificationTap,
    // Lets the YES / No thanks buttons work even if the app process
    // isn't alive when the notification is tapped (e.g. right after
    // a reboot, before the user has opened the app).
    onDidReceiveBackgroundNotificationResponse:
        _onBootNotificationTapBackground,
  );

  // Create all channels
  final androidImpl = notifPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  await androidImpl?.createNotificationChannel(
    const AndroidNotificationChannel(
      notifChannelId,
      'Road Guard AI',
      description: 'Road Guard is actively monitoring for potholes',
      importance: Importance.low,
    ),
  );

  await androidImpl?.createNotificationChannel(
    const AndroidNotificationChannel(
      alertChannelId,
      'Hazard Alerts',
      description: 'Pothole and road hazard warnings',
      importance: Importance.max,
    ),
  );

  await androidImpl?.createNotificationChannel(
    const AndroidNotificationChannel(
      bootChannelId,
      'Boot Prompt',
      description: 'Asks if you want to resume monitoring after restart',
      importance: Importance.high,
    ),
  );

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onServiceStart,
      autoStart: false, // ← Never start right after configure(); only on
      //                    an explicit user action.
      // The plugin's own native boot receiver WILL relaunch this
      // isolate after a device reboot — that's fine, we want the
      // chance to intercept it (see onServiceStart below) rather than
      // disabling it, since there's no other reliable headless hook
      // available without writing custom native Android code.
      autoStartOnBoot: true,
      isForegroundMode: true,
      notificationChannelId: notifChannelId,
      initialNotificationTitle: 'Road Guard AI',
      // Neutral wording: this shows briefly on EVERY start, including
      // the post-boot consent check, so it must not claim monitoring
      // is active before we've confirmed that.
      initialNotificationContent: 'Starting…',
      foregroundServiceNotificationId: foregroundNotifId,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onServiceStart,
    ),
  );
}

// =====================================================
// BOOT CONSENT PROMPT
// Called from onServiceStart() when we detect the service
// was relaunched by Android itself (not by the user tapping
// START), typically right after a device reboot. Instead of
// silently resuming monitoring, we ask first.
// =====================================================

Future<void> _promptResumeConsent() async {
  final prefs = await SharedPreferences.getInstance();
  final wasMonitoring = prefs.getBool(kMonitoringPref) ?? false;

  if (!wasMonitoring) return; // User had it off — don't nag them

  final FlutterLocalNotificationsPlugin notifPlugin =
      FlutterLocalNotificationsPlugin();

  await notifPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: _onBootNotificationTap,
    onDidReceiveBackgroundNotificationResponse:
        _onBootNotificationTapBackground,
  );

  final androidImpl = notifPlugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await androidImpl?.createNotificationChannel(
    const AndroidNotificationChannel(
      bootChannelId,
      'Boot Prompt',
      description: 'Asks if you want to resume monitoring after restart',
      importance: Importance.high,
    ),
  );

  await notifPlugin.show(
    bootPromptNotifId,
    'Resume Road Guard monitoring?',
    'You were monitoring before your device restarted. Tap YES to resume.',
    NotificationDetails(
      android: AndroidNotificationDetails(
        bootChannelId,
        'Boot Prompt',
        channelDescription: 'Asks if you want to resume monitoring',
        importance: Importance.high,
        priority: Priority.high,
        actions: [
          const AndroidNotificationAction(
            'action_yes',
            'YES, Resume',
            showsUserInterface: true,
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

// Called when the user taps YES / No thanks — works whether the app
// process is alive (foreground handler) or not (background handler).
@pragma('vm:entry-point')
void _onBootNotificationTap(NotificationResponse response) async {
  await _handleBootResponse(response);
}

@pragma('vm:entry-point')
void _onBootNotificationTapBackground(NotificationResponse response) async {
  await _handleBootResponse(response);
}

Future<void> _handleBootResponse(NotificationResponse response) async {
  final prefs = await SharedPreferences.getInstance();
  if (response.actionId == 'action_yes') {
    // This IS the explicit user consent — flag it so onServiceStart()
    // knows it's allowed to actually monitor this time.
    await prefs.setBool(kExplicitStartPref, true);
    await prefs.setBool(kMonitoringPref, true);
    final service = FlutterBackgroundService();
    await service.startService();
  } else if (response.actionId == 'action_no') {
    await prefs.setBool(kMonitoringPref, false);
  }
}

// =====================================================
// SAVE MONITORING STATE — call from HomeScreen
// =====================================================

Future<void> saveMonitoringState(bool isActive) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kMonitoringPref, isActive);
}

// =====================================================
// MARK AN EXPLICIT, USER-INITIATED START
// Call this right before service.startService() from the
// START button so onServiceStart() can tell "user pressed
// START" apart from "Android silently relaunched me".
// =====================================================

Future<void> markExplicitStart() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(kExplicitStartPref, true);
}

// =====================================================
// SERVICE ENTRY POINT — runs in background isolate
// =====================================================

@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) async {
  // Stop signal from toggleMonitoring()
  service.on('stop').listen((event) {
    service.stopSelf();
  });

  // The background service runs in its OWN isolate, so it does NOT
  // share ApiConfig's in-memory static with the UI isolate. Load the
  // last-connected ngrok URL from SharedPreferences here.
  await ApiConfig.load();

  // ---------------------------------------------------------------
  // CONSENT GATE — this is the important bit.
  // If this start was not explicitly requested (START button, or
  // tapping YES on the resume prompt), it means Android relaunched
  // us on its own — almost always right after a device reboot.
  // We NEVER start monitoring in that case; we only ask.
  // ---------------------------------------------------------------
  final prefs = await SharedPreferences.getInstance();
  final bool explicitStart = prefs.getBool(kExplicitStartPref) ?? false;

  if (!explicitStart) {
    await _promptResumeConsent();
    service.stopSelf();
    return;
  }

  // Consume the one-shot flag so a *future* silent restart isn't
  // mistaken for consent again.
  await prefs.setBool(kExplicitStartPref, false);

  // Receive speed + weather + base_url config from the UI (Start button
  // or Simulation page "Connect")
  double speedKmh = 30.0;
  String weather = 'dry';

  service.on('config').listen((data) async {
    if (data != null) {
      speedKmh = (data['speed_kmh'] as num?)?.toDouble() ?? speedKmh;
      weather = data['weather'] as String? ?? weather;
      final newUrl = data['base_url'] as String?;
      if (newUrl != null && newUrl.trim().isNotEmpty) {
        await ApiConfig.setBaseUrl(newUrl);
      }
    }
  });

  // -------------------------------------------------------
  // GPS polling + backend proximity check every 10 seconds
  // -------------------------------------------------------
  Timer.periodic(const Duration(seconds: 10), (timer) async {
    try {
      final bool serviceEnabled =
          await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      final LocationPermission perm =
          await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;

      final Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      final PotholeAlert alert = await ApiService.instance.checkNearby(
        lat: pos.latitude,
        lng: pos.longitude,
        speedKmh: speedKmh,
        weather: weather,
      );

      // Send alert level back to the UI (if app is open)
      service.invoke('alert', {
        'level': alert.level.index,
        'message': alert.message,
        'distance': alert.distance,
        'severity': alert.severity,
      });

      // Show a notification for stage 2 / 3
      await AlertNotificationHelper.showHazardNotification(alert);
    } catch (_) {
      // Never crash the background service
    }
  });
}