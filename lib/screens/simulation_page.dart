import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import '../services/alert_service.dart';

// =====================================================
// SIMULATION PAGE
// Lets the user connect a backend URL (ngrok), pick
// speed + weather, grab GPS, and step through 6 checks
// of 20s each (2 min total) to demo the alert stages.
// =====================================================

class SimulationPage extends StatefulWidget {
  const SimulationPage({super.key});

  @override
  State<SimulationPage> createState() => _SimulationPageState();
}

class _SimulationPageState extends State<SimulationPage> {
  // ---- Backend connect box ----
  late final TextEditingController _urlController;
  bool _connecting = false;

  // ---- Config ----
  double _speedKmh = 20;
  String _weather = 'dry';

  // ---- Step timer: 20s per step × 6 steps = 2 minutes ----
  static const int _stepDurationSec = 20;
  static const int _totalSteps = 6;
  int _currentStep = 0;
  int _secondsRemaining = _stepDurationSec;
  Timer? _tickTimer;

  // ---- State ----
  bool _running = false;
  bool _fetchingLocation = false;
  Position? _position;
  PotholeAlert? _lastAlert;
  String _statusMsg = 'Configure and press Start Simulation';
  bool _backendAlive = false;

  // ---- UI colours per stage ----
  static const Map<AlertLevel, Color> _stageColor = {
    AlertLevel.none: Color(0xFF2ECC71),
    AlertLevel.stage1: Color(0xFFF39C12),
    AlertLevel.stage2: Color(0xFFE67E22),
    AlertLevel.stage3: Color(0xFFE74C3C),
  };

  static const Map<AlertLevel, String> _stageLabel = {
    AlertLevel.none: 'ALL CLEAR',
    AlertLevel.stage1: 'STAGE 1 — Caution',
    AlertLevel.stage2: 'STAGE 2 — Warning',
    AlertLevel.stage3: 'STAGE 3 — DANGER',
  };

  static const Map<AlertLevel, IconData> _stageIcon = {
    AlertLevel.none: Icons.check_circle_outline,
    AlertLevel.stage1: Icons.warning_amber_outlined,
    AlertLevel.stage2: Icons.warning,
    AlertLevel.stage3: Icons.dangerous,
  };

  // ---------------------------------------------------
  // LIFECYCLE
  // ---------------------------------------------------

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: ApiConfig.baseUrl);
    _checkBackend();
  }

  @override
  void dispose() {
    _stopSimulation();
    _urlController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------
  // BACKEND HEALTH CHECK (uses whatever is currently saved)
  // ---------------------------------------------------

  Future<void> _checkBackend() async {
    final alive = await ApiService.instance.isBackendAlive();
    if (mounted) {
      setState(() => _backendAlive = alive);
    }
  }

  // ---------------------------------------------------
  // CONNECT — save the typed URL (ngrok or otherwise),
  // test it, and only keep it if it actually answers /health
  // ---------------------------------------------------

  Future<void> _connectBackend() async {
    final typed = _urlController.text.trim();
    if (typed.isEmpty) {
      _showSnack('Enter a backend URL first (e.g. https://xxxx.ngrok-free.app)');
      return;
    }

    setState(() => _connecting = true);

    final reachable = await ApiService.instance.isBackendAlive(overrideUrl: typed);

    if (reachable) {
      await ApiConfig.setBaseUrl(typed);
    }

    if (mounted) {
      setState(() {
        _connecting = false;
        _backendAlive = reachable;
      });
    }

    _showSnack(
      reachable
          ? 'Connected to backend ✅'
          : 'Could not reach that URL — check it\'s running and the tunnel is up',
    );
  }

  // ---------------------------------------------------
  // GET LOCATION
  // ---------------------------------------------------

  Future<Position?> _getLocation() async {
    setState(() {
      _fetchingLocation = true;
      _statusMsg = 'Getting your location…';
    });

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack('Please enable Location on your device');
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showSnack('Location permission denied');
          return null;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        _showSnack('Location permission permanently denied — enable in Settings');
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return pos;
    } finally {
      if (mounted) setState(() => _fetchingLocation = false);
    }
  }

  // ---------------------------------------------------
  // START SIMULATION
  // Runs 6 steps of 20s each = 2 minutes total, then
  // auto-completes. Each step does one backend check.
  // ---------------------------------------------------

  Future<void> _startSimulation() async {
    if (!_backendAlive) {
      _showSnack('Connect a working backend URL first');
      return;
    }

    final pos = await _getLocation();
    if (pos == null) return;

    setState(() {
      _position = pos;
      _running = true;
      _currentStep = 0;
      _secondsRemaining = _stepDurationSec;
      _statusMsg =
          'Simulating at ${_speedKmh.toInt()} km/h · $_weather weather';
    });

    // Step 1 fires immediately
    await _runStep();

    // 1-second UI ticker drives the 20s-per-step cadence
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted) return;

      setState(() => _secondsRemaining--);

      if (_secondsRemaining <= 0) {
        if (_currentStep >= _totalSteps) {
          _completeSimulation();
          return;
        }
        await _runStep();
        if (_running && mounted) {
          setState(() => _secondsRemaining = _stepDurationSec);
        }
      }
    });
  }

  // ---------------------------------------------------
  // ONE STEP = one poll to the backend
  // ---------------------------------------------------

  Future<void> _runStep() async {
    _currentStep++;
    setState(() {
      _statusMsg = 'Step $_currentStep of $_totalSteps — checking backend…';
    });
    await _poll();
    if (!mounted) return;
    setState(() {
      _statusMsg = _currentStep >= _totalSteps
          ? 'Final step done — wrapping up…'
          : 'Step $_currentStep of $_totalSteps complete';
    });

    if (_currentStep >= _totalSteps) {
      // Let the last result stay on screen for one more tick, then stop.
      await Future.delayed(const Duration(seconds: 1));
      _completeSimulation();
    }
  }

  // ---------------------------------------------------
  // COMPLETE — 2 minutes / 6 steps done, auto-stop
  // ---------------------------------------------------

  void _completeSimulation() {
    _tickTimer?.cancel();
    _tickTimer = null;
    AlertService.instance.stopAlert();
    if (mounted) {
      setState(() {
        _running = false;
        _statusMsg = 'Simulation complete — $_totalSteps steps, 2 minutes';
      });
    }
  }

  // ---------------------------------------------------
  // STOP SIMULATION (manual)
  // ---------------------------------------------------

  void _stopSimulation() {
    _tickTimer?.cancel();
    _tickTimer = null;
    AlertService.instance.stopAlert();
    if (mounted) {
      setState(() {
        _running = false;
        _lastAlert = null;
        _statusMsg = 'Simulation stopped';
      });
    }
  }

  // ---------------------------------------------------
  // POLL BACKEND
  // ---------------------------------------------------

  Future<void> _poll() async {
    if (_position == null) return;

    final alert = await ApiService.instance.checkNearby(
      lat: _position!.latitude,
      lng: _position!.longitude,
      speedKmh: _speedKmh,
      weather: _weather,
    );

    if (!mounted) return;

    setState(() => _lastAlert = alert);

    // Trigger sound + flash
    await AlertService.instance.trigger(alert);
  }

  // ---------------------------------------------------
  // HELPERS
  // ---------------------------------------------------

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------------------------------------------
  // UI
  // ---------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final AlertLevel currentLevel =
        _lastAlert?.level ?? AlertLevel.none;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),

      appBar: AppBar(
        backgroundColor: const Color(0xFF161B22),
        title: const Text(
          'Simulation',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Backend status indicator
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Row(
              children: [
                Icon(
                  Icons.circle,
                  size: 10,
                  color: _backendAlive
                      ? const Color(0xFF2ECC71)
                      : Colors.red,
                ),
                const SizedBox(width: 6),
                Text(
                  _backendAlive ? 'Backend' : 'Offline',
                  style: TextStyle(
                    color: _backendAlive
                        ? const Color(0xFF2ECC71)
                        : Colors.red,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: _checkBackend,
                  child: const Icon(
                    Icons.refresh,
                    color: Colors.grey,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // ==========================================
            // BACKEND URL — CONNECT BOX
            // Paste your ngrok URL here and hit Connect.
            // Free ngrok URLs change on every restart, so
            // this is intentionally editable at runtime.
            // ==========================================

            _sectionLabel('Backend URL'),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    enabled: !_running,
                    keyboardType: TextInputType.url,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'https://xxxx.ngrok-free.app',
                      hintStyle: const TextStyle(color: Colors.white24),
                      prefixIcon:
                          const Icon(Icons.link, color: Colors.white38),
                      filled: true,
                      fillColor: const Color(0xFF161B22),
                      enabledBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF30363D)),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFF1F6FEB)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: (_connecting || _running) ? null : _connectBackend,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1F6FEB),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: _connecting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Connect'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // ==========================================
            // BACKEND OFFLINE BANNER
            // ==========================================

            if (!_backendAlive)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.15),
                  border: Border.all(color: Colors.orange),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off, color: Colors.orange, size: 18),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Backend not reachable. Paste your ngrok URL above and '
                        'tap Connect.\nFor USB testing: adb reverse tcp:8000 tcp:8000',
                        style: TextStyle(color: Colors.orange, fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),

            // ==========================================
            // ALERT INDICATOR (big pill)
            // ==========================================

            AnimatedContainer(
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              height: 140,
              decoration: BoxDecoration(
                color: _stageColor[currentLevel]!.withOpacity(0.15),
                border: Border.all(
                  color: _stageColor[currentLevel]!,
                  width: 2,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _stageIcon[currentLevel]!,
                    color: _stageColor[currentLevel]!,
                    size: 40,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _stageLabel[currentLevel]!,
                    style: TextStyle(
                      color: _stageColor[currentLevel]!,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                  if (_lastAlert?.distance != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${_lastAlert!.distance!.toStringAsFixed(0)} m ahead',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                      ),
                    ),
                  ],
                  if (_lastAlert?.message.isNotEmpty == true) ...[
                    const SizedBox(height: 2),
                    Text(
                      _lastAlert!.message,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 28),

            // ==========================================
            // SPEED SELECTOR
            // ==========================================

            _sectionLabel('Speed'),
            const SizedBox(height: 10),

            Row(
              children: [20.0, 40.0].map((speed) {
                final bool selected = _speedKmh == speed;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: GestureDetector(
                      onTap: _running
                          ? null
                          : () => setState(() => _speedKmh = speed),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          color: selected
                              ? const Color(0xFF1F6FEB).withOpacity(0.2)
                              : const Color(0xFF21262D),
                          border: Border.all(
                            color: selected
                                ? const Color(0xFF1F6FEB)
                                : const Color(0xFF30363D),
                            width: selected ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          children: [
                            Text(
                              '${speed.toInt()}',
                              style: TextStyle(
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                color: selected
                                    ? const Color(0xFF58A6FF)
                                    : Colors.white70,
                              ),
                            ),
                            const Text(
                              'km/h',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.white38,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 28),

            // ==========================================
            // WEATHER SELECTOR
            // ==========================================

            _sectionLabel('Weather Condition'),
            const SizedBox(height: 10),

            Row(
              children: [
                _weatherOption('dry', '☀️', 'Dry'),
                _weatherOption('rain', '🌧️', 'Rain'),
              ].map((w) => Expanded(child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: w,
              ))).toList(),
            ),

            const SizedBox(height: 28),

            // ==========================================
            // GPS READOUT
            // ==========================================

            if (_position != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF21262D),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on,
                        color: Color(0xFF58A6FF), size: 16),
                    const SizedBox(width: 8),
                    Text(
                      '${_position!.latitude.toStringAsFixed(5)}, '
                      '${_position!.longitude.toStringAsFixed(5)}',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // ==========================================
            // STEP / COUNTDOWN (20s per step × 6 = 2 min)
            // ==========================================

            if (_running) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF30363D)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Step $_currentStep / $_totalSteps',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'Next check in ${_secondsRemaining}s',
                          style: const TextStyle(
                            color: Color(0xFF58A6FF),
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: _currentStep / _totalSteps,
                        minHeight: 6,
                        backgroundColor: const Color(0xFF21262D),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF1F6FEB),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ==========================================
            // STATUS TEXT
            // ==========================================

            Text(
              _statusMsg,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),

            const SizedBox(height: 24),

            // ==========================================
            // START / STOP BUTTON
            // ==========================================

            SizedBox(
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _fetchingLocation
                    ? null
                    : (_running ? _stopSimulation : _startSimulation),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _running
                      ? const Color(0xFFDA3633)
                      : const Color(0xFF238636),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                icon: _fetchingLocation
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(_running ? Icons.stop : Icons.play_arrow),
                label: Text(
                  _fetchingLocation
                      ? 'Getting location…'
                      : (_running ? 'Stop Simulation' : 'Start Simulation'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ==========================================
            // ALERT LEGEND
            // ==========================================

            _legend(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // WEATHER OPTION WIDGET
  // ---------------------------------------------------

  Widget _weatherOption(String value, String emoji, String label) {
    final bool selected = _weather == value;
    return GestureDetector(
      onTap: _running ? null : () => setState(() => _weather = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF1F6FEB).withOpacity(0.2)
              : const Color(0xFF21262D),
          border: Border.all(
            color: selected
                ? const Color(0xFF1F6FEB)
                : const Color(0xFF30363D),
            width: selected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected
                    ? const Color(0xFF58A6FF)
                    : Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------
  // SECTION LABEL
  // ---------------------------------------------------

  Widget _sectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: Colors.white38,
        fontSize: 11,
        letterSpacing: 1.5,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  // ---------------------------------------------------
  // LEGEND
  // ---------------------------------------------------

  Widget _legend() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ALERT STAGES',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 10,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 10),
          _legendRow(AlertLevel.stage1, 'Light beep only'),
          const SizedBox(height: 6),
          _legendRow(AlertLevel.stage2, 'Normal sound + 3 flash pulses'),
          const SizedBox(height: 6),
          _legendRow(AlertLevel.stage3, 'Siren loop + continuous flashlight'),
        ],
      ),
    );
  }

  Widget _legendRow(AlertLevel level, String desc) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: _stageColor[level]!,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Text(
          _stageLabel[level]!,
          style: TextStyle(
            color: _stageColor[level]!,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '— $desc',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }
}