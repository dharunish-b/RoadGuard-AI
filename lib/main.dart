import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'screens/upload_pothole.dart';
import 'services/background_service.dart';

// =====================================================
// MAIN
// =====================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initBackgroundService();
  runApp(const RoadGuardApp());
}

// =====================================================
// ROADGUARD APP
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

  // false = STOPPED  →  green START button
  // true  = RUNNING  →  red STOP button
  bool isRunning = false;

  // ===================================================
  // INIT — sync UI with actual service state
  // ===================================================

  @override
  void initState() {
    super.initState();
    _syncServiceState();
  }

  Future<void> _syncServiceState() async {
    final service = FlutterBackgroundService();
    final running = await service.isRunning();
    setState(() {
      isRunning = running;
    });
  }

  // ===================================================
  // START / STOP BUTTON
  // ===================================================

  void toggleMonitoring() async {
    final service = FlutterBackgroundService();

    if (!isRunning) {
      // Request notification permission at runtime (Android 13+)
      final plugin = FlutterLocalNotificationsPlugin();
      final android = plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission();

      // Show battery optimization tip on first start
      _showBatteryTip();

      await service.startService();
    } else {
      service.invoke('stop');
    }

    setState(() {
      isRunning = !isRunning;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          isRunning
              ? "Monitoring Started"
              : "Monitoring Stopped",
        ),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ===================================================
  // BATTERY TIP DIALOG
  // ===================================================

  void _showBatteryTip() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Keep Road Guard Running"),
        content: const Text(
          "For uninterrupted monitoring, go to:\n\n"
          "Settings → Battery → Road Guard AI\n"
          "→ Set to 'Unrestricted' or 'No restrictions'\n\n"
          "This ensures the app keeps monitoring even when minimized.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Got it"),
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

      // =================================================
      // APP BAR
      // =================================================

      appBar: AppBar(
        title: const Text(
          "Road Guard AI",
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      // =================================================
      // DRAWER
      // =================================================

      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [

            // -------------------------------------------
            // DRAWER HEADER
            // -------------------------------------------

            const DrawerHeader(
              decoration: BoxDecoration(
                color: Colors.blue,
              ),

              child: Center(
                child: Text(
                  "Road Guard AI",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            // -------------------------------------------
            // HOME
            // -------------------------------------------

            ListTile(
              leading: const Icon(Icons.home),
              title: const Text("Home"),

              onTap: () {
                Navigator.pop(context);
              },
            ),

            // -------------------------------------------
            // SIMULATION
            // -------------------------------------------

            ListTile(
              leading: const Icon(Icons.science),
              title: const Text("Simulation"),

              onTap: () {
                Navigator.pop(context);

                // Simulation page can be added later.
              },
            ),

            // -------------------------------------------
            // UPLOAD POT HOLE
            // -------------------------------------------

            ListTile(
              leading: const Icon(Icons.upload),
              title: const Text("Upload Pot Hole"),

              onTap: () {

                Navigator.pop(context);

                Navigator.push(
                  context,

                  MaterialPageRoute(
                    builder: (context) =>
                        const UploadPotholePage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),

      // =================================================
      // HOME BODY
      // =================================================

      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,

          children: [

            // -------------------------------------------
            // TITLE
            // -------------------------------------------

            const Text(
              "Road Guard AI",

              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 15),

            // -------------------------------------------
            // STATUS TEXT
            // -------------------------------------------

            Text(
              isRunning
                  ? "Monitoring is active"
                  : "Tap START to begin monitoring",

              style: TextStyle(
                fontSize: 18,
                color: isRunning
                    ? Colors.green
                    : Colors.grey,
              ),
            ),

            const SizedBox(height: 50),

            // -------------------------------------------
            // ROUND START / STOP BUTTON
            // -------------------------------------------

            SizedBox(
              width: 180,
              height: 180,

              child: ElevatedButton(

                onPressed: toggleMonitoring,

                style: ElevatedButton.styleFrom(

                  // STOPPED = GREEN (tap to START)
                  // RUNNING = RED   (tap to STOP)
                  backgroundColor:
                      isRunning
                          ? Colors.red
                          : Colors.green,

                  foregroundColor: Colors.white,

                  // ROUND BUTTON
                  shape: const CircleBorder(),

                  elevation: 8,

                  padding: EdgeInsets.zero,
                ),

                child: Text(

                  isRunning
                      ? "STOP"
                      : "START",

                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),

            // -------------------------------------------
            // SMALL INSTRUCTION
            // -------------------------------------------

            Text(
              isRunning
                  ? "Tap to stop monitoring"
                  : "Tap START to monitor roads",

              style: const TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}