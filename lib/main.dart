import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'screens/upload_pothole.dart';
import 'screens/simulation_page.dart';
import 'screens/reports_page.dart';                // ← NEW
import 'services/background_service.dart';
import 'services/alert_service.dart';
import 'services/api_service.dart';

// =====================================================
// MAIN  — unchanged
// =====================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ApiConfig.load();
  await initBackgroundService();
  runApp(const RoadGuardApp());
}

// =====================================================
// APP  — unchanged
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

  // NEW — active session kept in memory.
  // Null when monitoring is stopped.
  MonitoringSession? _activeSession;

  // NEW — last known position for movement gate and
  // for sending end coordinates to /alert/stop.
  Position? _lastKnownPosition;

  // NEW — latest alert pushed from the background isolate, kept
  // ONLY for display (banner). Hardware (sound/torch) is triggered
  // by the background isolate itself now — see background_service.dart —
  // so this screen must NOT call AlertService.trigger() again, or
  // you'd get it firing twice whenever the app happens to be open.
  PotholeAlert? _latestAlert;

  // ===================================================
  // INIT  — unchanged
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
  // LISTEN TO ALERTS FROM BACKGROUND SERVICE  — unchanged
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

      // Hardware alert (beep/torch/siren) already fired from the
      // background isolate — see background_service.dart. This
      // listener now only updates the on-screen banner so the UI
      // reflects the current hazard state when the app is open.
      if (mounted) setState(() => _latestAlert = alert);
    });
  }

  // ===================================================
  // LOCATION GATE  — unchanged
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
  // NEW — Get current GPS position (used for start/stop)
  // Returns null silently if GPS unavailable.
  // ===================================================

  Future<Position?> _getCurrentPosition() async {
    try {
      return await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 8));
    } catch (_) {
      return null;
    }
  }

  // ===================================================
  // TOGGLE MONITORING
  // Original flow preserved; /alert/start and /alert/stop
  // calls added around the existing service start/stop.
  // ===================================================

  void toggleMonitoring() async {
    final service = FlutterBackgroundService();

    if (!isRunning) {
      // ── STARTING ──────────────────────────────────

      final locationReady = await _ensureLocationReady();
      if (!locationReady) return;

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

      // NEW — Get GPS for /alert/start.
      // If GPS times out, startMonitoring uses (0,0) and
      // backend logs it as unknown-start. Non-blocking.
      final startPos = await _getCurrentPosition();
      _lastKnownPosition = startPos;

      // NEW — Notify backend: session started.
      // Uses default speed 30 km/h and dry weather as initial
      // defaults. Background service will update these via
      // 'config' invoke once the user sets them.
      // startMonitoring is offline-tolerant (returns local
      // fallback session if backend unreachable).
      _activeSession = await ApiService.instance.startMonitoring(
        lat: startPos?.latitude ?? 0.0,
        lng: startPos?.longitude ?? 0.0,
        speedKmh: 30.0,
        weather: 'dry',
      );

      final plugin = FlutterLocalNotificationsPlugin();
      final android = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();

      _showBatteryTip();

      await markExplicitStart();
      await service.startService();

      service.invoke('config', {
        'speed_kmh': 30.0,
        'weather': 'dry',
        'base_url': ApiConfig.baseUrl,
        // NEW — pass session_id into background isolate so it
        // can tag /alert/check calls with the session if needed.
        'session_id': _activeSession?.sessionId ?? '',
      });
    } else {
      // ── STOPPING ──────────────────────────────────

      service.invoke('stop');
      await AlertService.instance.stopAlert();

      // Clear the on-screen banner too. (The hardware siren/torch
      // is stopped inside the background isolate itself, triggered
      // by its own 'stop' listener in background_service.dart.)
      _latestAlert = null;

      // NEW — Get last GPS before stopping.
      // Sent to /alert/stop as end_lat / end_lon.
      final endPos = await _getCurrentPosition();

      // NEW — Notify backend: session ended.
      // Fire-and-forget; fail silently (stopMonitoring handles it).
      if (_activeSession != null) {
        await ApiService.instance.stopMonitoring(
          sessionId: _activeSession!.sessionId,
          endLat: endPos?.latitude ?? _lastKnownPosition?.latitude ?? 0.0,
          endLng: endPos?.longitude ?? _lastKnownPosition?.longitude ?? 0.0,
        );
        _activeSession = null;
      }

      _lastKnownPosition = null;
    }

    final nowRunning = !isRunning;
    setState(() => isRunning = nowRunning);

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

  // ===================================================
  // BATTERY TIP DIALOG  — unchanged
  // ===================================================

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
  // UI  — unchanged
  // ===================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),

      appBar: AppBar(
        title: const Text(
          'Road Guard AI',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),

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

            _drawerItem(
              icon: Icons.report_outlined,
              label: 'Reports',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ReportsPage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),

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

            // NEW — live hazard banner. Purely visual; the actual
            // beep/torch/siren already fired from the background
            // isolate the moment this alert was detected, even if
            // this screen wasn't open at the time.
            if (isRunning &&
                _latestAlert != null &&
                _latestAlert!.level != AlertLevel.none) ...[
              const SizedBox(height: 20),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: (_latestAlert!.level == AlertLevel.stage3
                          ? Colors.red
                          : const Color(0xFFF39C12))
                      .withOpacity(0.15),
                  border: Border.all(
                    color: _latestAlert!.level == AlertLevel.stage3
                        ? Colors.red
                        : const Color(0xFFF39C12),
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      color: _latestAlert!.level == AlertLevel.stage3
                          ? Colors.red
                          : const Color(0xFFF39C12),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        _latestAlert!.distance != null
                            ? '${_latestAlert!.message} · '
                                '${_latestAlert!.distance!.toStringAsFixed(0)} m ahead'
                            : _latestAlert!.message,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 50),

            SizedBox(
              width: 180,
              height: 180,
              child: ElevatedButton(
                onPressed: toggleMonitoring,
                style: ElevatedButton.styleFrom(
                  backgroundColor: isRunning
                      ? const Color(0xFFDA3633)
                      : const Color(0xFF238636),
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