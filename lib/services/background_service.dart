import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

// =====================================================
// CONSTANTS
// =====================================================

const String notifChannelId = 'road_guard_channel';
const int notifId = 1;

// =====================================================
// INIT — call once in main() before runApp()
// =====================================================

Future<void> initBackgroundService() async {
  final service = FlutterBackgroundService();

  final FlutterLocalNotificationsPlugin notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // Initialize the notifications plugin (required before any notif shows)
  await notificationsPlugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );

  // Create the Android notification channel (required for Android 8+)
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    notifChannelId,
    'Road Guard AI',
    description: 'Road Guard is actively monitoring for potholes',
    importance: Importance.low,
  );

  await notificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onServiceStart,

      // false — only starts when user explicitly taps START
      autoStart: false,

      // Foreground mode keeps Android from killing the service
      // even when the app is swiped from recents
      isForegroundMode: true,

      notificationChannelId: notifChannelId,
      initialNotificationTitle: 'Road Guard AI',
      initialNotificationContent: 'Monitoring active — watching for potholes',
      foregroundServiceNotificationId: notifId,
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onServiceStart,
    ),
  );
}

// =====================================================
// SERVICE ENTRY POINT — runs in background isolate
// =====================================================

@pragma('vm:entry-point')
void onServiceStart(ServiceInstance service) async {

  // Listen for explicit stop signal from toggleMonitoring()
  // This is the ONLY way the service stops — user taps STOP in the app
  service.on('stop').listen((event) {
    service.stopSelf();
  });

  // -------------------------------------------------------
  // GPS polling + pothole proximity check goes here.
  // Sanjai's hazard coordinates from MongoDB slot in below.
  //
  // Example (uncomment when backend is ready):
  //
  // Timer.periodic(const Duration(seconds: 10), (timer) async {
  //   Position pos = await Geolocator.getCurrentPosition();
  //   // fetch nearby hazards from MongoDB via Mithun's API
  //   // if distance < d_alert → fire local notification
  // });
  // -------------------------------------------------------
}