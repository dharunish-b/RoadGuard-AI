import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/api_service.dart';
import '../services/local_report_store.dart';         // ← NEW
import '../constants/simulation_coords.dart';   // ← shared sim coords
import 'upload_pothole_widgets.dart';

// =====================================================
// UPLOAD POTHOLE PAGE  — 3-STEP FLOW
//
//  Step 1 — Camera: Take photo from any safe distance
//           Mode toggle: Real GPS  |  Demo Coordinates
//  Step 2 — Walk:   Instructions to go stand on pothole
//           (skipped in demo mode — goes straight to step 3)
//  Step 3 — GPS:    Real mode  → live accuracy stream
//           Demo mode → shows pinned sim coords + upload button
//
// DEMO MODE (for stage presentations / indoor testing):
//   Skips real GPS entirely. Uses kSimLat / kSimLng from
//   simulation_coords.dart — the exact coordinates stored
//   against the seeded demo pothole (kPotholeId).
//   This means the simulation page will find & alert on
//   the pothole you upload here, even inside a building.
//
// REAL MODE (outdoor use):
//   Unchanged 3-step flow. GPS must reach ≤ 10 m accuracy
//   before "Confirm & Upload" is enabled.
// =====================================================

class UploadPotholePage extends StatefulWidget {
  const UploadPotholePage({super.key});

  @override
  State<UploadPotholePage> createState() => _UploadPotholePageState();
}

class _UploadPotholePageState extends State<UploadPotholePage> {
  // ── Step tracking ─────────────────────────────────
  // 1 = photo, 2 = walk instruction, 3 = GPS confirm
  int _step = 1;

  // ── Mode ──────────────────────────────────────────
  // true  = use kSimLat / kSimLng (indoor / stage demo)
  // false = use real GPS (outdoor real-world use)
  bool _demoMode = false;

  // ── Photo (step 1) ────────────────────────────────
  File? _image;
  final ImagePicker _picker = ImagePicker();

  // ── GPS (step 3, real mode only) ──────────────────
  bool _gpsStarted = false;
  bool _gpsPermissionDenied = false;
  Position? _livePosition;
  Position? _confirmedPosition;
  StreamSubscription<Position>? _posStream;

  // ── Upload ────────────────────────────────────────
  bool _uploading = false;
  UploadResult? _lastResult;

  // ===================================================
  // LIFECYCLE
  // ===================================================

  @override
  void dispose() {
    _posStream?.cancel();
    super.dispose();
  }

  // ===================================================
  // STEP 1 — TAKE PHOTO
  // ===================================================

  Future<void> _takePhoto() async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (picked == null) return;
    setState(() {
      _image = File(picked.path);
      _lastResult = null;
      // Demo mode: skip walk step, jump straight to confirm
      _step = _demoMode ? 3 : 2;
    });
  }

  Future<void> _pickFromGallery() async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked == null) return;
    setState(() {
      _image = File(picked.path);
      _lastResult = null;
      _step = _demoMode ? 3 : 2;
    });
  }

  // ===================================================
  // STEP 2 → STEP 3 (real mode only)
  // ===================================================

  void _proceedToGps() => setState(() => _step = 3);

  // ===================================================
  // STEP 3 — ENABLE GPS (real mode only)
  // ===================================================

  Future<void> _enableGps() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enable Location on your device'),
            duration: Duration(seconds: 2),
          ),
        );
        await Geolocator.openLocationSettings();
      }
      return;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (mounted) setState(() => _gpsPermissionDenied = true);
      return;
    }

    setState(() {
      _gpsStarted = true;
      _gpsPermissionDenied = false;
    });

    _posStream = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 0,
      ),
    ).listen((pos) {
      if (mounted) setState(() => _livePosition = pos);
    });
  }

  // ===================================================
  // UPLOAD — real GPS path
  // ===================================================

  Future<void> _confirmAndUpload() async {
    if (_livePosition == null || _image == null) return;
    setState(() {
      _confirmedPosition = _livePosition;
      _uploading = true;
      _lastResult = null;
    });
    await _posStream?.cancel();
    _posStream = null;

    final result = await ApiService.instance.uploadPothole(
      imageFile: _image!,
      lat: _confirmedPosition!.latitude,
      lng: _confirmedPosition!.longitude,
    );

    // Save to local cache so Reports page can show this user's own uploads
    // with the actual photo (image path stays valid on this device).
    if (result.success && result.potholeId != null) {
      await LocalReportStore.instance.add(LocalPotholeReport(
        potholeId:  result.potholeId!,
        imagePath:  _image!.path,
        lat:        _confirmedPosition!.latitude,
        lon:        _confirmedPosition!.longitude,
        severity:   _severityFromResult(result),
        confidence: result.severity,
        fallType:   result.detectionLabel,
        uploadedAt: DateTime.now(),
        isDemo:     false,
      ));
    }

    if (mounted) {
      setState(() {
        _uploading = false;
        _lastResult = result;
      });
    }
  }

  // ===================================================
  // UPLOAD — demo / simulation coordinates path
  // ===================================================

  Future<void> _uploadWithSimCoords() async {
    if (_image == null) return;
    setState(() {
      _uploading = true;
      _lastResult = null;
    });

    final result = await ApiService.instance.uploadPothole(
      imageFile: _image!,
      lat: kSimLat,
      lng: kSimLng,
    );

    if (result.success && result.potholeId != null) {
      // Persist ID for SimulationController
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kDemoPotholeIdKey, result.potholeId!);

      // Save to local cache with image path + demo flag
      await LocalReportStore.instance.add(LocalPotholeReport(
        potholeId:  result.potholeId!,
        imagePath:  _image!.path,
        lat:        kSimLat,
        lon:        kSimLng,
        severity:   _severityFromResult(result),
        confidence: result.severity,
        fallType:   result.detectionLabel,
        uploadedAt: DateTime.now(),
        isDemo:     true,
      ));
    }

    if (mounted) {
      setState(() {
        _uploading = false;
        _lastResult = result;
      });
    }
  }

  // ===================================================
  // HELPERS
  // ===================================================

  /// Maps UploadResult.alertStage back to a severity string
  /// for local cache storage.
  String _severityFromResult(UploadResult result) {
    return switch (result.alertStage) {
      1 => 'low',
      2 => 'medium',
      3 => 'high',
      _ => 'unknown',
    };
  }

  // ===================================================
  // RESTART
  // ===================================================

  void _restart() {
    _posStream?.cancel();
    _posStream = null;
    setState(() {
      _step = 1;
      _image = null;
      _gpsStarted = false;
      _gpsPermissionDenied = false;
      _livePosition = null;
      _confirmedPosition = null;
      _lastResult = null;
      _uploading = false;
      // keep _demoMode so user doesn't have to re-toggle
    });
  }

  // ===================================================
  // BUILD
  // ===================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: const Text('Upload Pothole'),
        leading: _step > 1
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  _posStream?.cancel();
                  _posStream = null;
                  setState(() {
                    _step = _step - 1;
                    if (_step == 1) _image = null;
                    _gpsStarted = false;
                    _livePosition = null;
                    _confirmedPosition = null;
                    _lastResult = null;
                    _gpsPermissionDenied = false;
                  });
                },
              )
            : null,
      ),
      body: switch (_step) {
        1 => _buildStep1(),
        2 => _buildStep2(),
        _ => _buildStep3(),
      },
    );
  }

  // ===================================================
  // STEP 1 UI — Take Photo  +  Mode Toggle
  // ===================================================

  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          const StepIndicator(activeStep: 1),
          const SizedBox(height: 20),

          // ── MODE TOGGLE ────────────────────────────
          _ModeToggle(
            demoMode: _demoMode,
            onChanged: (val) => setState(() => _demoMode = val),
          ),

          const SizedBox(height: 24),

          const Text(
            'Step 1: Take a photo of the pothole',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            _demoMode
                ? 'Take or pick a photo. The demo pothole coordinates\nwill be used — no need to go outdoors.'
                : 'Stand at a safe distance and photograph the pothole.\n'
                  'You will mark its exact GPS location in the next steps.',
            style: const TextStyle(color: Colors.white54, fontSize: 13),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 28),

          GestureDetector(
            onTap: _takePhoto,
            child: Container(
              height: 200,
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                border: Border.all(color: const Color(0xFF30363D)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt_outlined,
                      size: 56, color: Color(0xFF1F6FEB)),
                  SizedBox(height: 10),
                  Text(
                    'Tap to open camera',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Rear camera  •  85% quality',
                    style: TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 18),

          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _takePhoto,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1F6FEB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              icon: const Icon(Icons.camera_alt),
              label: const Text(
                'Open Camera',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),

          const SizedBox(height: 14),

          Row(
            children: const [
              Expanded(child: Divider(color: Color(0xFF30363D))),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  'OR',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ),
              Expanded(child: Divider(color: Color(0xFF30363D))),
            ],
          ),

          const SizedBox(height: 14),

          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _pickFromGallery,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF58A6FF),
                side: const BorderSide(color: Color(0xFF30363D)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text(
                'Upload from Gallery',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Already took the photo? Pick it from your gallery.',
            style: TextStyle(color: Colors.white38, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ===================================================
  // STEP 2 UI — Walk Instruction  (real mode only)
  // ===================================================

  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          const StepIndicator(activeStep: 2),
          const SizedBox(height: 28),

          if (_image != null)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                _image!,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),

          const SizedBox(height: 8),
          const Center(
            child: Text(
              '✓ Photo captured',
              style: TextStyle(
                color: Color(0xFF2ECC71),
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),

          const SizedBox(height: 28),

          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              border: Border.all(
                  color: const Color(0xFFF39C12).withOpacity(0.5)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Column(
              children: [
                Icon(Icons.directions_walk,
                    color: Color(0xFFF39C12), size: 48),
                SizedBox(height: 14),
                Text(
                  'Step 2: Walk to the pothole',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 10),
                Text(
                  'Now walk and stand EXACTLY on or beside\n'
                  'the pothole you just photographed.\n\n'
                  'Once you are standing on it, tap the button\n'
                  'below to enable GPS and mark the location.',
                  style: TextStyle(
                      color: Colors.white60, fontSize: 13.5, height: 1.6),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline,
                        color: Colors.white38, size: 14),
                    SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'GPS will only start after you tap — '
                        'this ensures the location is yours on the pothole.',
                        style:
                            TextStyle(color: Colors.white38, fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _proceedToGps,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF39C12),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              icon: const Icon(Icons.location_searching),
              label: const Text(
                'I am standing on the pothole →',
                style:
                    TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===================================================
  // STEP 3 UI — branches on _demoMode
  // ===================================================

  Widget _buildStep3() {
    return _demoMode ? _buildStep3Demo() : _buildStep3Real();
  }

  // ── DEMO MODE: pinned sim coordinates, one-tap upload ──

  Widget _buildStep3Demo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          const StepIndicator(activeStep: 3),
          const SizedBox(height: 24),

          if (_image != null)
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(_image!,
                      width: 72, height: 54, fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Photo captured ✓\nUsing demo pothole coordinates.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 24),

          // Pinned coordinate card
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              border: Border.all(color: const Color(0xFF6E40C9)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.science,
                        color: Color(0xFFBC8CFF), size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Demo Mode — Simulation Coordinates',
                      style: TextStyle(
                          color: Color(0xFFBC8CFF), fontSize: 13),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Text(
                  'This photo will be uploaded to the seeded\n'
                  'demo pothole location used by the Simulation page.',
                  style: TextStyle(
                      color: Colors.white60, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 16),
                const Divider(color: Color(0xFF30363D), height: 1),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.location_pin,
                        color: Colors.white24, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      '${kSimLat.toStringAsFixed(6)},   '
                      '${kSimLng.toStringAsFixed(6)}',
                      style: const TextStyle(
                        color: Color(0xFFBC8CFF),
                        fontSize: 13,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Pinned from simulation_coords.dart',
                  style: TextStyle(color: Colors.white24, fontSize: 11),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Result card
          if (_lastResult != null) ...[
            ResultCard(result: _lastResult!),
            const SizedBox(height: 16),
            if (_lastResult!.success)
              OutlinedButton.icon(
                onPressed: _restart,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Color(0xFF30363D)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.add_a_photo),
                label: const Text('Report Another Pothole'),
              ),
          ],

          if (_lastResult == null)
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _uploading ? null : _uploadWithSimCoords,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6E40C9),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor:
                      const Color(0xFF6E40C9).withOpacity(0.25),
                  disabledForegroundColor: Colors.white30,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                icon: _uploading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.science),
                label: Text(
                  _uploading ? 'Uploading…' : 'Upload to Demo Location',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── REAL MODE: unchanged GPS accuracy flow ──

  Widget _buildStep3Real() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          const StepIndicator(activeStep: 3),
          const SizedBox(height: 24),

          if (_image != null)
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(_image!,
                      width: 72, height: 54, fit: BoxFit.cover),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Photo captured ✓\nNow mark the exact location.',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 24),

          if (!_gpsStarted) ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                border: Border.all(
                    color: const Color(0xFF238636).withOpacity(0.5)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                children: [
                  Icon(Icons.gps_not_fixed,
                      color: Color(0xFF2ECC71), size: 48),
                  SizedBox(height: 14),
                  Text(
                    'Step 3: Enable GPS',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 10),
                  Text(
                    'You should be standing EXACTLY on the pothole.\n\n'
                    'Tap the button below to turn on GPS.\n'
                    'Your current position will be used as the\n'
                    'pothole\'s location in the database.',
                    style: TextStyle(
                        color: Colors.white60,
                        fontSize: 13.5,
                        height: 1.6),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            if (_gpsPermissionDenied)
              Container(
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  border: Border.all(color: Colors.red),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  '⚠️  Location permission denied.\n'
                  'Open Settings → App Permissions → Location → Allow.',
                  style: TextStyle(color: Colors.red, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),

            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _enableGps,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF238636),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.gps_fixed),
                label: const Text(
                  'Enable GPS — I am on the pothole',
                  style:
                      TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],

          if (_gpsStarted) ...[
            AccuracyCard(livePosition: _livePosition),
            const SizedBox(height: 20),

            if (_lastResult != null) ...[
              ResultCard(result: _lastResult!),
              const SizedBox(height: 16),
              if (_lastResult!.success)
                OutlinedButton.icon(
                  onPressed: _restart,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white70,
                    side: const BorderSide(color: Color(0xFF30363D)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  icon: const Icon(Icons.add_a_photo),
                  label: const Text('Report Another Pothole'),
                ),
            ],

            if (_lastResult == null)
              ConfirmButton(
                livePosition: _livePosition,
                uploading: _uploading,
                onConfirm: _confirmAndUpload,
              ),
          ],

          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// =====================================================
// MODE TOGGLE WIDGET
// =====================================================

class _ModeToggle extends StatelessWidget {
  final bool demoMode;
  final ValueChanged<bool> onChanged;

  const _ModeToggle({
    required this.demoMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        border: Border.all(color: const Color(0xFF30363D)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          _tab(
            label: '🛰  Real Location',
            active: !demoMode,
            onTap: () => onChanged(false),
            activeColor: const Color(0xFF238636),
          ),
          const SizedBox(width: 4),
          _tab(
            label: '🔬  Demo Coordinates',
            active: demoMode,
            onTap: () => onChanged(true),
            activeColor: const Color(0xFF6E40C9),
          ),
        ],
      ),
    );
  }

  Widget _tab({
    required String label,
    required bool active,
    required VoidCallback onTap,
    required Color activeColor,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: active ? Colors.white : Colors.white38,
              fontSize: 13,
              fontWeight:
                  active ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }
}