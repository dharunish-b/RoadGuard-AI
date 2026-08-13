import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
  // TOGGLE MONITORING
  // ===================================================

  void toggleMonitoring() async {
    final service = FlutterBackgroundService();

    if (!isRunning) {
      // Make sure the backend is actually reachable before we start
      // burning battery polling it in the background.
      final alive = await ApiService.instance.isBackendAlive();
      if (!alive) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Cannot reach backend at ${ApiConfig.baseUrl}. '
                'Connect a valid URL from the Simulation page first.',
              ),
              duration: const Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      final plugin = FlutterLocalNotificationsPlugin();
      final android = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();

      _showBatteryTip();
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