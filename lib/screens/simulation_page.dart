import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'simulation_config.dart';
import '../services/api_service.dart';
import '../services/alert_service.dart';
import 'simulation_controller.dart';

// =====================================================
// SIMULATION PAGE
//
// Features:
// - Backend connection
// - Speed selection
// - Weather selection
// - Automatic GPS location
// - Latitude
// - Longitude
// - GPS accuracy
// - Simulation steps
// - Alert stages
// - Cooldown
//
// GPS is automatically obtained by SimulationController
// when the simulation starts.
// =====================================================

class SimulationPage extends StatefulWidget {
  const SimulationPage({
    super.key,
  });

  @override
  State<SimulationPage> createState() =>
      _SimulationPageState();
}

class _SimulationPageState extends State<SimulationPage> {
  late final TextEditingController _urlController;

  late final SimulationController _ctrl;

  // ===================================================
  // ALERT COLORS
  // ===================================================

  static const Map<AlertLevel, Color> _stageColor = {
    AlertLevel.none:
        Color(0xFF2ECC71),

    AlertLevel.stage1:
        Color(0xFFF39C12),

    AlertLevel.stage2:
        Color(0xFFE67E22),

    AlertLevel.stage3:
        Color(0xFFE74C3C),
  };

  // ===================================================
  // ALERT LABELS
  // ===================================================

  static const Map<AlertLevel, String> _stageLabel = {
    AlertLevel.none:
        'ALL CLEAR',

    AlertLevel.stage1:
        'STAGE 1 — Caution',

    AlertLevel.stage2:
        'STAGE 2 — Warning',

    AlertLevel.stage3:
        'STAGE 3 — DANGER',
  };

  // ===================================================
  // ALERT ICONS
  // ===================================================

  static const Map<AlertLevel, IconData> _stageIcon = {
    AlertLevel.none:
        Icons.check_circle_outline,

    AlertLevel.stage1:
        Icons.warning_amber_outlined,

    AlertLevel.stage2:
        Icons.warning,

    AlertLevel.stage3:
        Icons.dangerous,
  };

  // ===================================================
  // LIFECYCLE
  // ===================================================

  @override
  void initState() {
    super.initState();

    _urlController = TextEditingController(
      text: ApiConfig.baseUrl,
    );

    _ctrl = SimulationController(
      onStateChanged: () {
        if (!mounted) {
          return;
        }

        setState(() {});
      },
    );

    _ctrl.checkBackend();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _urlController.dispose();

    super.dispose();
  }

  // ===================================================
  // SNACKBAR
  // ===================================================

  void _showSnack(String msg) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
      ),
    );
  }

  // ===================================================
  // CONNECT BACKEND
  // ===================================================

  Future<void> _onConnectPressed() async {
    final String? error = await _ctrl.connectBackend(
      _urlController.text.trim(),
    );

    _showSnack(
      error ?? 'Connected to backend ✅',
    );
  }

  // ===================================================
  // BUILD
  // ===================================================

  @override
  Widget build(BuildContext context) {
    final AlertLevel level =
        _ctrl.lastAlert?.level ?? AlertLevel.none;

    return Scaffold(
      backgroundColor:
          const Color(0xFF0D1117),

      appBar: AppBar(
        backgroundColor:
            const Color(0xFF161B22),

        title: const Text(
          'Simulation',
          style: TextStyle(
            color: Colors.white,
          ),
        ),

        iconTheme:
            const IconThemeData(
          color: Colors.white,
        ),

        actions: [
          _buildBackendStatusChip(),
        ],
      ),

      body: SingleChildScrollView(
        padding:
            const EdgeInsets.all(20),

        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch,

          children: [
            // =================================================
            // BACKEND
            // =================================================

            _buildUrlRow(),

            const SizedBox(height: 16),

            if (!_ctrl.backendAlive)
              _buildOfflineBanner(),

            // =================================================
            // ALERT
            // =================================================

            _buildAlertPill(level),

            const SizedBox(height: 28),

            // =================================================
            // SPEED
            // =================================================

            _buildSpeedSelector(),

            const SizedBox(height: 28),

            // =================================================
            // WEATHER
            // =================================================

            _buildWeatherSelector(),

            const SizedBox(height: 28),

            // =================================================
            // GPS
            // =================================================

            _buildGpsReadout(),

            const SizedBox(height: 20),

            // =================================================
            // SIMULATION STEP
            // =================================================

            if (_ctrl.running) ...[
              _buildStepProgress(),

              const SizedBox(height: 16),
            ],

            // =================================================
            // COOLDOWN
            // =================================================

            if (_ctrl.inCooldown) ...[
              _buildCooldownProgress(),

              const SizedBox(height: 16),
            ],

            // =================================================
            // STATUS
            // =================================================

            _buildStatusText(),

            const SizedBox(height: 24),

            // =================================================
            // START / STOP
            // =================================================

            _buildStartStopButton(),

            const SizedBox(height: 24),

            // =================================================
            // LEGEND
            // =================================================

            _buildLegend(),
          ],
        ),
      ),
    );
  }

  // ===================================================
  // BACKEND STATUS
  // ===================================================

  Widget _buildBackendStatusChip() {
    return Padding(
      padding:
          const EdgeInsets.only(
        right: 16,
      ),

      child: Row(
        children: [
          Icon(
            Icons.circle,
            size: 10,
            color: _ctrl.backendAlive
                ? const Color(0xFF2ECC71)
                : Colors.red,
          ),

          const SizedBox(width: 6),

          Text(
            _ctrl.backendAlive
                ? 'Backend'
                : 'Offline',

            style: TextStyle(
              color: _ctrl.backendAlive
                  ? const Color(0xFF2ECC71)
                  : Colors.red,

              fontSize: 12,
            ),
          ),

          const SizedBox(width: 8),

          GestureDetector(
            onTap: _ctrl.checkBackend,

            child: const Icon(
              Icons.refresh,
              color: Colors.grey,
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  // ===================================================
  // BACKEND URL
  // ===================================================

  Widget _buildUrlRow() {
    final bool locked =
        _ctrl.running ||
        _ctrl.inCooldown;

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,

      children: [
        _sectionLabel(
          'Backend URL',
        ),

        const SizedBox(height: 10),

        Row(
          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [
            Expanded(
              child: TextField(
                controller:
                    _urlController,

                enabled:
                    !locked,

                keyboardType:
                    TextInputType.url,

                style:
                    const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                ),

                decoration:
                    const InputDecoration(
                  hintText:
                      'https://xxxx.ngrok-free.app',

                  hintStyle:
                      TextStyle(
                    color: Colors.white24,
                  ),

                  prefixIcon:
                      Icon(
                    Icons.link,
                    color: Colors.white38,
                  ),

                  filled: true,

                  fillColor:
                      Color(0xFF161B22),

                  enabledBorder:
                      OutlineInputBorder(
                    borderSide:
                        BorderSide(
                      color:
                          Color(0xFF30363D),
                    ),
                  ),

                  focusedBorder:
                      OutlineInputBorder(
                    borderSide:
                        BorderSide(
                      color:
                          Color(0xFF1F6FEB),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(width: 10),

            SizedBox(
              height: 56,

              child:
                  ElevatedButton(
                onPressed:
                    (_ctrl.connecting ||
                            locked)
                        ? null
                        : _onConnectPressed,

                style:
                    ElevatedButton.styleFrom(
                  backgroundColor:
                      const Color(
                    0xFF1F6FEB,
                  ),

                  foregroundColor:
                      Colors.white,

                  shape:
                      RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(
                      10,
                    ),
                  ),
                ),

                child:
                    _ctrl.connecting
                        ? const SizedBox(
                            width: 18,
                            height: 18,

                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                              color:
                                  Colors.white,
                            ),
                          )
                        : const Text(
                            'Connect',
                          ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ===================================================
  // OFFLINE BANNER
  // ===================================================

  Widget _buildOfflineBanner() {
    return Container(
      margin:
          const EdgeInsets.only(
        bottom: 16,
      ),

      padding:
          const EdgeInsets.all(12),

      decoration:
          BoxDecoration(
        color:
            Colors.orange.withOpacity(
          0.15,
        ),

        border:
            Border.all(
          color:
              Colors.orange,
        ),

        borderRadius:
            BorderRadius.circular(
          8,
        ),
      ),

      child: const Row(
        children: [
          Icon(
            Icons.wifi_off,
            color:
                Colors.orange,
            size: 18,
          ),

          SizedBox(width: 10),

          Expanded(
            child: Text(
              'Backend not reachable. Paste your ngrok URL above and tap Connect.\n'
              'USB: adb reverse tcp:8000 tcp:8000',

              style:
                  TextStyle(
                color:
                    Colors.orange,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===================================================
  // ALERT PILL
  // ===================================================

  Widget _buildAlertPill(
    AlertLevel level,
  ) {
    final Color color =
        _stageColor[level]!;

    return AnimatedContainer(
      duration:
          const Duration(
        milliseconds: 400,
      ),

      curve:
          Curves.easeOut,

      height:
          _ctrl.inCooldown
              ? 175
              : 145,

      decoration:
          BoxDecoration(
        color:
            color.withOpacity(
          0.15,
        ),

        border:
            Border.all(
          color:
              color,
          width: 2,
        ),

        borderRadius:
            BorderRadius.circular(
          16,
        ),
      ),

      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,

        children: [
          Icon(
            _stageIcon[level]!,
            color:
                color,
            size: 40,
          ),

          const SizedBox(height: 8),

          Text(
            _stageLabel[level]!,

            style:
                TextStyle(
              color:
                  color,
              fontSize:
                  18,
              fontWeight:
                  FontWeight.bold,
              letterSpacing:
                  1.2,
            ),
          ),

          if (_ctrl.lastAlert?.distance !=
              null) ...[
            const SizedBox(height: 4),

            Text(
              '${_ctrl.lastAlert!.distance!.toStringAsFixed(0)} m ahead',

              style:
                  const TextStyle(
                color:
                    Colors.white60,
                fontSize:
                    13,
              ),
            ),
          ],

          if (_ctrl.lastAlert?.message
                  .isNotEmpty ==
              true) ...[
            const SizedBox(height: 2),

            Text(
              _ctrl.lastAlert!.message,

              style:
                  const TextStyle(
                color:
                    Colors.white54,
                fontSize:
                    12,
              ),

              textAlign:
                  TextAlign.center,
            ),
          ],

          if (_ctrl.inCooldown) ...[
            const SizedBox(height: 10),

            Container(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 6,
              ),

              decoration:
                  BoxDecoration(
                color:
                    Colors.black26,

                borderRadius:
                    BorderRadius.circular(
                  20,
                ),
              ),

              child: Row(
                mainAxisSize:
                    MainAxisSize.min,

                children: [
                  const Icon(
                    Icons.timer_outlined,
                    color:
                        Colors.white54,
                    size: 14,
                  ),

                  const SizedBox(width: 6),

                  Text(
                    'Clearing in ${fmtCountdown(_ctrl.cooldownRemaining)}',

                    style:
                        const TextStyle(
                      color:
                          Colors.white54,
                      fontSize:
                          12,
                      fontWeight:
                          FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ===================================================
  // SPEED
  // ===================================================

  Widget _buildSpeedSelector() {
    final bool locked =
        _ctrl.running ||
        _ctrl.inCooldown;

    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,

      children: [
        _sectionLabel(
          'Speed',
        ),

        const SizedBox(height: 10),

        Row(
          children:
              [20.0, 40.0]
                  .map(
                    (speed) {
                      final bool selected =
                          _ctrl.speedKmh ==
                              speed;

                      return Expanded(
                        child: Padding(
                          padding:
                              const EdgeInsets.symmetric(
                            horizontal: 6,
                          ),

                          child:
                              GestureDetector(
                            onTap:
                                locked
                                    ? null
                                    : () {
                                        setState(
                                          () {
                                            _ctrl.speedKmh =
                                                speed;
                                          },
                                        );
                                      },

                            child:
                                AnimatedContainer(
                              duration:
                                  const Duration(
                                milliseconds:
                                    200,
                              ),

                              padding:
                                  const EdgeInsets.symmetric(
                                vertical:
                                    18,
                              ),

                              decoration:
                                  BoxDecoration(
                                color:
                                    selected
                                        ? const Color(
                                            0xFF1F6FEB,
                                          ).withOpacity(
                                            0.2,
                                          )
                                        : const Color(
                                            0xFF21262D,
                                          ),

                                border:
                                    Border.all(
                                  color:
                                      selected
                                          ? const Color(
                                              0xFF1F6FEB,
                                            )
                                          : const Color(
                                              0xFF30363D,
                                            ),

                                  width:
                                      selected
                                          ? 2
                                          : 1,
                                ),

                                borderRadius:
                                    BorderRadius.circular(
                                  12,
                                ),
                              ),

                              child:
                                  Column(
                                children: [
                                  Text(
                                    '${speed.toInt()}',

                                    style:
                                        TextStyle(
                                      fontSize:
                                          32,

                                      fontWeight:
                                          FontWeight.bold,

                                      color:
                                          selected
                                              ? const Color(
                                                  0xFF58A6FF,
                                                )
                                              : Colors.white70,
                                    ),
                                  ),

                                  const Text(
                                    'km/h',

                                    style:
                                        TextStyle(
                                      fontSize:
                                          13,

                                      color:
                                          Colors.white38,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  )
                  .toList(),
        ),
      ],
    );
  }

  // ===================================================
  // WEATHER
  // ===================================================

  Widget _buildWeatherSelector() {
    return Column(
      crossAxisAlignment:
          CrossAxisAlignment.start,

      children: [
        _sectionLabel(
          'Weather Condition',
        ),

        const SizedBox(height: 10),

        Row(
          children: [
            _weatherOption(
              'dry',
              '☀️',
              'Dry',
            ),

            _weatherOption(
              'rain',
              '🌧️',
              'Rain',
            ),
          ]
              .map(
                (widget) => Expanded(
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 6,
                    ),

                    child:
                        widget,
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }

  Widget _weatherOption(
    String value,
    String emoji,
    String label,
  ) {
    final bool selected =
        _ctrl.weather ==
            value;

    final bool locked =
        _ctrl.running ||
        _ctrl.inCooldown;

    return GestureDetector(
      onTap:
          locked
              ? null
              : () {
                  setState(
                    () {
                      _ctrl.weather =
                          value;
                    },
                  );
                },

      child:
          AnimatedContainer(
        duration:
            const Duration(
          milliseconds:
              200,
        ),

        padding:
            const EdgeInsets.symmetric(
          vertical:
              16,
        ),

        decoration:
            BoxDecoration(
          color:
              selected
                  ? const Color(
                      0xFF1F6FEB,
                    ).withOpacity(
                      0.2,
                    )
                  : const Color(
                      0xFF21262D,
                    ),

          border:
              Border.all(
            color:
                selected
                    ? const Color(
                        0xFF1F6FEB,
                      )
                    : const Color(
                        0xFF30363D,
                      ),

            width:
                selected
                    ? 2
                    : 1,
          ),

          borderRadius:
              BorderRadius.circular(
            12,
          ),
        ),

        child:
            Column(
          children: [
            Text(
              emoji,

              style:
                  const TextStyle(
                fontSize:
                    26,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              label,

              style:
                  TextStyle(
                fontSize:
                    14,

                fontWeight:
                    FontWeight.w600,

                color:
                    selected
                        ? const Color(
                            0xFF58A6FF,
                          )
                        : Colors.white60,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ===================================================
  // GPS READOUT
  //
  // AUTOMATIC GPS
  //
  // Position comes from SimulationController.
  //
  // When simulation starts:
  // Controller obtains the phone's GPS position.
  //
  // The page automatically displays:
  // - Latitude
  // - Longitude
  // - Accuracy
  // ===================================================

  Widget _buildGpsReadout() {
    final Position? position =
        _ctrl.position;

    // =================================================
    // GETTING GPS
    // =================================================

    if (_ctrl.fetchingLocation) {
      return Container(
        padding:
            const EdgeInsets.all(
          16,
        ),

        decoration:
            BoxDecoration(
          color:
              const Color(
            0xFF161B22,
          ),

          border:
              Border.all(
            color:
                const Color(
              0xFF1F6FEB,
            ),
          ),

          borderRadius:
              BorderRadius.circular(
            12,
          ),
        ),

        child:
            const Row(
          children: [
            SizedBox(
              width:
                  22,
              height:
                  22,

              child:
                  CircularProgressIndicator(
                strokeWidth:
                    2,

                color:
                    Color(
                  0xFF58A6FF,
                ),
              ),
            ),

            SizedBox(width: 12),

            Expanded(
              child:
                  Text(
                'Detecting current GPS location automatically...',

                style:
                    TextStyle(
                  color:
                      Colors.white70,

                  fontSize:
                      13,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // =================================================
    // GPS NOT AVAILABLE
    // =================================================

    if (position == null) {
      return Container(
        padding:
            const EdgeInsets.all(
          14,
        ),

        decoration:
            BoxDecoration(
          color:
              const Color(
            0xFF161B22,
          ),

          border:
              Border.all(
            color:
                const Color(
              0xFF30363D,
            ),
          ),

          borderRadius:
              BorderRadius.circular(
            10,
          ),
        ),

        child:
            const Row(
          children: [
            Icon(
              Icons.location_searching,

              color:
                  Colors.orange,

              size:
                  20,
            ),

            SizedBox(width: 10),

            Expanded(
              child:
                  Text(
                'GPS location will be detected automatically when you start the simulation.',

                style:
                    TextStyle(
                  color:
                      Colors.white60,

                  fontSize:
                      12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // =================================================
    // GPS AVAILABLE
    // =================================================

    return AnimatedContainer(
      duration:
          const Duration(
        milliseconds:
            300,
      ),

      padding:
          const EdgeInsets.all(
        14,
      ),

      decoration:
          BoxDecoration(
        color:
            const Color(
          0xFF161B22,
        ),

        border:
            Border.all(
          color:
              _ctrl.isTrackingLocation
                  ? const Color(
                      0xFF238636,
                    )
                  : const Color(
                      0xFF30363D,
                    ),

          width:
              _ctrl.isTrackingLocation
                  ? 1.5
                  : 1,
        ),

        borderRadius:
            BorderRadius.circular(
          10,
        ),
      ),

      child:
          Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [
          // ===========================================
          // HEADER
          // ===========================================

          Row(
            children: [
              Icon(
                _ctrl.isTrackingLocation
                    ? Icons.gps_fixed
                    : Icons.location_on,

                color:
                    _ctrl.isTrackingLocation
                        ? const Color(
                            0xFF2ECC71,
                          )
                        : const Color(
                            0xFF58A6FF,
                          ),

                size:
                    20,
              ),

              const SizedBox(width: 8),

              const Text(
                'CURRENT GPS LOCATION',

                style:
                    TextStyle(
                  color:
                      Colors.white70,

                  fontSize:
                      11,

                  fontWeight:
                      FontWeight.bold,

                  letterSpacing:
                      1.2,
                ),
              ),

              const Spacer(),

              if (_ctrl.isTrackingLocation)
                Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal:
                        8,

                    vertical:
                        4,
                  ),

                  decoration:
                      BoxDecoration(
                    color:
                        const Color(
                      0xFF238636,
                    ).withOpacity(
                      0.20,
                    ),

                    borderRadius:
                        BorderRadius.circular(
                      20,
                    ),
                  ),

                  child:
                      const Row(
                    children: [
                      Icon(
                        Icons.circle,

                        color:
                            Color(
                          0xFF2ECC71,
                        ),

                        size:
                            7,
                      ),

                      SizedBox(width: 5),

                      Text(
                        'LIVE',

                        style:
                            TextStyle(
                          color:
                              Color(
                            0xFF2ECC71,
                          ),

                          fontSize:
                              9,

                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          const SizedBox(height: 14),

          // ===========================================
          // LATITUDE
          // ===========================================

          _gpsRow(
            icon:
                Icons.north,

            label:
                'Latitude',

            value:
                position.latitude
                    .toStringAsFixed(
              6,
            ),
          ),

          const SizedBox(height: 8),

          // ===========================================
          // LONGITUDE
          // ===========================================

          _gpsRow(
            icon:
                Icons.east,

            label:
                'Longitude',

            value:
                position.longitude
                    .toStringAsFixed(
              6,
            ),
          ),

          const SizedBox(height: 8),

          // ===========================================
          // ACCURACY
          // ===========================================

          _gpsRow(
            icon:
                Icons.my_location,

            label:
                'Accuracy',

            value:
                '${position.accuracy.toStringAsFixed(1)} m',
          ),
        ],
      ),
    );
  }

  // ===================================================
  // GPS ROW
  // ===================================================

  Widget _gpsRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(
          icon,

          color:
              Colors.white38,

          size:
              16,
        ),

        const SizedBox(width: 8),

        SizedBox(
          width:
              75,

          child:
              Text(
            label,

            style:
                const TextStyle(
              color:
                  Colors.white54,

              fontSize:
                  12,
            ),
          ),
        ),

        Expanded(
          child:
              Text(
            value,

            style:
                const TextStyle(
              color:
                  Colors.white,

              fontSize:
                  14,

              fontFamily:
                  'monospace',

              fontWeight:
                  FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  // ===================================================
  // STEP PROGRESS
  // ===================================================

  Widget _buildStepProgress() {
    return Container(
      padding:
          const EdgeInsets.all(
        14,
      ),

      decoration:
          BoxDecoration(
        color:
            const Color(
          0xFF161B22,
        ),

        border:
            Border.all(
          color:
              const Color(
            0xFF30363D,
          ),
        ),

        borderRadius:
            BorderRadius.circular(
          10,
        ),
      ),

      child:
          Column(
        children: [
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,

            children: [
              Text(
                'Step ${_ctrl.currentStep} / $kTotalSteps',

                style:
                    const TextStyle(
                  color:
                      Colors.white70,

                  fontSize:
                      13,

                  fontWeight:
                      FontWeight.w600,
                ),
              ),

              Text(
                'Next check in ${_ctrl.secondsRemaining}s',

                style:
                    const TextStyle(
                  color:
                      Color(
                    0xFF58A6FF,
                  ),

                  fontSize:
                      13,

                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          ClipRRect(
            borderRadius:
                BorderRadius.circular(
              6,
            ),

            child:
                LinearProgressIndicator(
              value:
                  _ctrl.currentStep /
                      kTotalSteps,

              minHeight:
                  6,

              backgroundColor:
                  const Color(
                0xFF21262D,
              ),

              valueColor:
                  const AlwaysStoppedAnimation<Color>(
                Color(
                  0xFF1F6FEB,
                ),
              ),
            ),
          ),

          if (_ctrl.running) ...[
            const SizedBox(height: 10),

            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,

              children: [
                const Text(
                  'Live speed',

                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                Text(
                  '${_ctrl.currentSpeedKmh.toStringAsFixed(1)} km/h',

                  style: const TextStyle(
                    color: Color(0xFF3FB950),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 6),

            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,

              children: [
                const Text(
                  'Road condition',

                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                Text(
                  _ctrl.weather == 'rain'
                      ? '🌧️ Rain'
                      : '☀️ Dry',

                  style: TextStyle(
                    color: _ctrl.weather == 'rain'
                        ? const Color(0xFF58A6FF)
                        : const Color(0xFFF0B429),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ===================================================
  // COOLDOWN
  // ===================================================

  Widget _buildCooldownProgress() {
    final double progress =
        1.0 -
        (_ctrl.cooldownRemaining /
            kCooldownDurationSec);

    return Container(
      padding:
          const EdgeInsets.all(
        14,
      ),

      decoration:
          BoxDecoration(
        color:
            const Color(
          0xFF161B22,
        ),

        border:
            Border.all(
          color:
              const Color(
            0xFF30363D,
          ),
        ),

        borderRadius:
            BorderRadius.circular(
          10,
        ),
      ),

      child:
          Column(
        children: [
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,

            children: [
              const Text(
                'Pothole zone',

                style:
                    TextStyle(
                  color:
                      Colors.white70,

                  fontSize:
                      13,

                  fontWeight:
                      FontWeight.w600,
                ),
              ),

              Text(
                'Clears in ${fmtCountdown(_ctrl.cooldownRemaining)}',

                style:
                    const TextStyle(
                  color:
                      Color(
                    0xFFE74C3C,
                  ),

                  fontSize:
                      13,

                  fontWeight:
                      FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          ClipRRect(
            borderRadius:
                BorderRadius.circular(
              6,
            ),

            child:
                LinearProgressIndicator(
              value:
                  progress,

              minHeight:
                  6,

              backgroundColor:
                  const Color(
                0xFF21262D,
              ),

              valueColor:
                  const AlwaysStoppedAnimation<Color>(
                Color(
                  0xFFE74C3C,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===================================================
  // STATUS
  // ===================================================

  Widget _buildStatusText() {
    return Text(
      _ctrl.statusMsg,

      textAlign:
          TextAlign.center,

      style:
          const TextStyle(
        color:
            Colors.white54,

        fontSize:
            13,
      ),
    );
  }

  // ===================================================
  // START / STOP BUTTON
  // ===================================================

  Widget _buildStartStopButton() {
    final bool locked =
        _ctrl.fetchingLocation ||
        _ctrl.inCooldown;

    final Color bgColor;

    final IconData icon;

    final String label;

    if (_ctrl.inCooldown) {
      bgColor =
          const Color(
        0xFF30363D,
      );

      icon =
          Icons.hourglass_top;

      label =
          'Waiting — zone clears in '
          '${fmtCountdown(_ctrl.cooldownRemaining)}';
    } else if (_ctrl.running) {
      bgColor =
          const Color(
        0xFFDA3633,
      );

      icon =
          Icons.stop;

      label =
          'Stop Simulation';
    } else if (_ctrl.fetchingLocation) {
      bgColor =
          const Color(
        0xFF238636,
      );

      icon =
          Icons.my_location;

      label =
          'Getting location…';
    } else {
      bgColor =
          const Color(
        0xFF238636,
      );

      icon =
          Icons.play_arrow;

      label =
          'Start Simulation';
    }

    return SizedBox(
      height:
          56,

      child:
          ElevatedButton.icon(
        onPressed:
            locked
                ? null
                : (_ctrl.running
                    ? _ctrl.stopSimulation
                    : () {
                        _ctrl.startSimulation(
                          _showSnack,
                        );
                      }),

        style:
            ElevatedButton.styleFrom(
          backgroundColor:
              bgColor,

          foregroundColor:
              Colors.white,

          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
              12,
            ),
          ),

          elevation:
              0,
        ),

        icon:
            _ctrl.fetchingLocation
                ? const SizedBox(
                    width:
                        18,

                    height:
                        18,

                    child:
                        CircularProgressIndicator(
                      strokeWidth:
                          2,

                      color:
                          Colors.white,
                    ),
                  )
                : Icon(
                    icon,
                  ),

        label:
            Text(
          label,

          style:
              const TextStyle(
            fontSize:
                16,

            fontWeight:
                FontWeight.bold,
          ),
        ),
      ),
    );
  }

  // ===================================================
  // LEGEND
  // ===================================================

  Widget _buildLegend() {
    return Container(
      padding:
          const EdgeInsets.all(
        14,
      ),

      decoration:
          BoxDecoration(
        color:
            const Color(
          0xFF161B22,
        ),

        border:
            Border.all(
          color:
              const Color(
            0xFF30363D,
          ),
        ),

        borderRadius:
            BorderRadius.circular(
          10,
        ),
      ),

      child:
          Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,

        children: [
          const Text(
            'ALERT STAGES',

            style:
                TextStyle(
              color:
                  Colors.white38,

              fontSize:
                  10,

              letterSpacing:
                  1.5,
            ),
          ),

          const SizedBox(height: 10),

          _legendRow(
            AlertLevel.stage1,
            'Light beep only',
          ),

          const SizedBox(height: 6),

          _legendRow(
            AlertLevel.stage2,
            'Medium sound + 3 torch flashes',
          ),

          const SizedBox(height: 6),

          _legendRow(
            AlertLevel.stage3,
            'Siren loop + continuous torch',
          ),

          const SizedBox(height: 10),

          const Divider(
            color:
                Color(
              0xFF30363D,
            ),
          ),

          const SizedBox(height: 6),

          _timingRow(
            'Steps 1-2',
            '10s each',
            const Color(
              0xFFF39C12,
            ),
          ),

          const SizedBox(height: 4),

          _timingRow(
            'Steps 3-4',
            '8s each',
            const Color(
              0xFFE67E22,
            ),
          ),

          const SizedBox(height: 4),

          _timingRow(
            'Step 5',
            '7s',
            const Color(
              0xFFE74C3C,
            ),
          ),
        ],
      ),
    );
  }

  // ===================================================
  // LEGEND ROW
  // ===================================================

  Widget _legendRow(
    AlertLevel level,
    String desc,
  ) {
    return Row(
      children: [
        Container(
          width:
              10,

          height:
              10,

          decoration:
              BoxDecoration(
            color:
                _stageColor[level]!,

            shape:
                BoxShape.circle,
          ),
        ),

        const SizedBox(width: 10),

        Text(
          _stageLabel[level]!,

          style:
              TextStyle(
            color:
                _stageColor[level]!,

            fontSize:
                12,

            fontWeight:
                FontWeight.bold,
          ),
        ),

        const SizedBox(width: 8),

        Expanded(
          child:
              Text(
            '— $desc',

            style:
                const TextStyle(
              color:
                  Colors.white38,

              fontSize:
                  12,
            ),
          ),
        ),
      ],
    );
  }

  // ===================================================
  // TIMING ROW
  // ===================================================

  Widget _timingRow(
    String steps,
    String duration,
    Color color,
  ) {
    return Row(
      children: [
        Text(
          steps,

          style:
              TextStyle(
            color:
                color,

            fontSize:
                11,

            fontWeight:
                FontWeight.w600,
          ),
        ),

        const SizedBox(width: 8),

        Text(
          duration,

          style:
              const TextStyle(
            color:
                Colors.white38,

            fontSize:
                11,
          ),
        ),
      ],
    );
  }

  // ===================================================
  // SECTION LABEL
  // ===================================================

  Widget _sectionLabel(
    String text,
  ) {
    return Text(
      text.toUpperCase(),

      style:
          const TextStyle(
        color:
            Colors.white38,

        fontSize:
            11,

        letterSpacing:
            1.5,

        fontWeight:
            FontWeight.w600,
      ),
    );
  }
}