import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'screens/upload_pothole.dart';
import 'screens/simulation_page.dart';
import 'services/background_service.dart';
import 'services/alert_service.dart';
import 'services/api_service.dart';

// =====================================================
// MAIN
// =====================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiConfig.load(); // restore last-connected ngrok URL, if any
  await initBackgroundService();
  runApp(const RoadGuardApp());
}

// =====================================================
// APP
// =====================================================

class RoadGuardApp extends StatelessWidget {
  const RoadGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Road Guard AI',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFF0D1117),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF161B22),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

// =====================================================
// HOME SCREEN
// =====================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool isRunning = false;

  // ===================================================
  // INIT
  // ===================================================

  @override
  void initState() {
    super.initState();
    _syncServiceState();
    _listenToAlerts();
  }

  Future<void> _syncServiceState() async {
    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    if (mounted) setState(() => isRunning = running);
  }

  // ===================================================
  // LISTEN TO ALERTS FROM BACKGROUND SERVICE
  // When the app is open, the service streams alert
  // events — we trigger sound + flash here in the main isolate
  // ===================================================

  void _listenToAlerts() {
    final service = FlutterBackgroundService();
    service.on('alert').listen((data) async {
      if (data == null) return;
      final int levelIndex = (data['level'] as num?)?.toInt() ?? 0;
      final AlertLevel level = AlertLevel.values[levelIndex];

      final alert = PotholeAlert(
        level: level,
        message: data['message'] as String? ?? '',
        distance: (data['distance'] as num?)?.toDouble(),
        severity: (data['severity'] as num?)?.toDouble(),
      );

      await AlertService.instance.trigger(alert);
    });
  }

  // ===================================================
  // LOCATION GATE — runs on every tap of START, independent
  // of the Simulation page (which has its own copy of this
  // logic and is never touched by this code).
  // Returns true only if location service is ON and permission
  // is granted; otherwise shows a snack and returns false.
  // ===================================================

  Future<bool> _ensureLocationReady() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enable Location to start monitoring'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      // Opens the device location settings screen so the user can
      // flip it on themselves — apps cannot toggle it programmatically.
      await Geolocator.openLocationSettings();
      return false;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission required to start monitoring'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return false;
    }
    return true;
  }

  // ===================================================
  // TOGGLE MONITORING
  // ===================================================

  void toggleMonitoring() async {
    final service = FlutterBackgroundService();

    if (!isRunning) {
      // Ask location EVERY time START is tapped.
      final locationReady = await _ensureLocationReady();
      if (!locationReady) return;

      // Make sure the backend is actually reachable — but don't block
      // START on it. If unreachable, warn only; monitoring still starts
      // and will just keep retrying once a URL is reachable.
      final alive = await ApiService.instance.isBackendAlive();
      if (!alive && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Warning: cannot reach backend at ${ApiConfig.baseUrl}. '
              'Monitoring will start anyway.',
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      final plugin = FlutterLocalNotificationsPlugin();
      final android = plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();

      _showBatteryTip();

      // FIX: mark this as a real, user-initiated start BEFORE calling
      // startService(). Without this, onServiceStart() in the background
      // isolate always thinks Android silently relaunched it (its
      // consent-gate check), fires the "Resume monitoring?" notification
      // every single time, and stops itself — monitoring never actually runs.
      await markExplicitStart();
      await service.startService();

      // Give the background isolate its base_url + default config.
      // (It also re-reads the URL from SharedPreferences on every poll,
      // this just avoids a cold-start race.)
      service.invoke('config', {
        'speed_kmh': 30.0,
        'weather': 'dry',
        'base_url': ApiConfig.baseUrl,
      });
    } else {
      service.invoke('stop');
      await AlertService.instance.stopAlert();
      // App-side location usage ends here — background isolate's GPS
      // polling timer stops with the service, so no further location
      // reads happen until START is tapped again.
    }

    final nowRunning = !isRunning;
    setState(() => isRunning = nowRunning);

    // Persist state so boot handler knows user's intent
    await saveMonitoringState(nowRunning);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nowRunning ? 'Monitoring Started' : 'Monitoring Stopped',
          ),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _showBatteryTip() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text(
          'Keep Road Guard Running',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'For uninterrupted monitoring:\n\n'
          'Settings → Battery → Road Guard AI\n'
          '→ Set to "Unrestricted"\n\n'
          'This keeps monitoring active when minimized.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  // ===================================================
  // UI
  // ===================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),

      // =================================================
      // APP BAR
      // =================================================

      appBar: AppBar(
        title: const Text(
          'Road Guard AI',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

      // =================================================
      // DRAWER
      // =================================================

      drawer: Drawer(
        backgroundColor: const Color(0xFF161B22),
        child: ListView(
          padding: EdgeInsets.zero,
          children: [

            const DrawerHeader(
              decoration: BoxDecoration(color: Color(0xFF1F6FEB)),
              child: Center(
                child: Text(
                  'Road Guard AI',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            _drawerItem(
              icon: Icons.home,
              label: 'Home',
              onTap: () => Navigator.pop(context),
            ),

            _drawerItem(
              icon: Icons.science,
              label: 'Simulation',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const SimulationPage(),
                  ),
                );
              },
            ),

            _drawerItem(
              icon: Icons.upload,
              label: 'Upload Pot Hole',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const UploadPotholePage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),

      // =================================================
      // BODY
      // =================================================

      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [

            const Text(
              'Road Guard AI',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),

            const SizedBox(height: 15),

            Text(
              isRunning
                  ? 'Monitoring is active'
                  : 'Tap START to begin monitoring',
              style: TextStyle(
                fontSize: 18,
                color: isRunning
                    ? const Color(0xFF2ECC71)
                    : Colors.white38,
              ),
            ),

            const SizedBox(height: 50),

            // Round START / STOP button
            SizedBox(
              width: 180,
              height: 180,
              child: ElevatedButton(
                onPressed: toggleMonitoring,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      isRunning ? const Color(0xFFDA3633) : const Color(0xFF238636),
                  foregroundColor: Colors.white,
                  shape: const CircleBorder(),
                  elevation: 8,
                  padding: EdgeInsets.zero,
                ),
                child: Text(
                  isRunning ? 'STOP' : 'START',
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),

            Text(
              isRunning
                  ? 'Tap to stop monitoring'
                  : 'Tap START to monitor roads',
              style: const TextStyle(fontSize: 16, color: Colors.white38),
            ),
          ],
        ),
      ),
    );
  }

  Widget _drawerItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }
}