import 'package:flutter/material.dart';
import 'screens/upload_pothole.dart';

void main() {
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
      title: 'RoadGuard',

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

  // false = STOP
  // true  = START
  bool isRunning = false;

  // ===================================================
  // START / STOP BUTTON
  // ===================================================

  void toggleMonitoring() {
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
          "RoadGuard",
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
                  "RoadGuard",
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
              "RoadGuard",

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
                  : "Monitoring is stopped",

              style: TextStyle(
                fontSize: 18,
                color: isRunning
                    ? Colors.green
                    : Colors.red,
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

                  // STOP = RED
                  // START = GREEN
                  backgroundColor:
                      isRunning
                          ? Colors.green
                          : Colors.red,

                  foregroundColor: Colors.white,

                  // ROUND BUTTON
                  shape: const CircleBorder(),

                  elevation: 8,

                  padding: EdgeInsets.zero,
                ),

                child: Text(

                  isRunning
                      ? "START"
                      : "STOP",

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
                  : "Tap to start monitoring",

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