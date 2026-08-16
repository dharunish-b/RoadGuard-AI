import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';
import 'upload_pothole_widgets.dart';

// =====================================================
// UPLOAD POTHOLE PAGE  — 3-STEP FLOW
//
//  Step 1 — Camera: Take photo from any safe distance
//  Step 2 — Walk:   Instructions to go stand on pothole
//  Step 3 — GPS:    User taps "Enable GPS" while standing
//                   on pothole → live accuracy stream →
//                   "Confirm & Upload" enabled at ≤ 10 m
//
// GPS is NEVER auto-started. User explicitly enables it
// only after physically standing on the pothole.
// This guarantees stored lat/lon = pothole position.
//
// Result card, color scheme, ApiService.uploadPothole()
// call signature all unchanged — friend's backend merges cleanly.
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

  // ── Photo (step 1) ────────────────────────────────
  File? _image;
  final ImagePicker _picker = ImagePicker();

  // ── GPS (step 3) ──────────────────────────────────
  bool _gpsStarted = false;          // user has tapped "Enable GPS"
  bool _gpsPermissionDenied = false;
  Position? _livePosition;           // updating from stream
  Position? _confirmedPosition;      // locked on confirm tap
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
  // Opens rear camera. On success → step 2.
  // GPS is NOT started here intentionally.
  // ===================================================

  Future<void> _takePhoto() async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
      preferredCameraDevice: CameraDevice.rear,
    );

    if (picked == null) return; // user cancelled

    setState(() {
      _image = File(picked.path);
      _lastResult = null;
      _step = 2; // go to walk instruction screen
    });
  }

  // ===================================================
  // STEP 1 (ALT) — PICK FROM GALLERY
  // For users who already took the photo earlier and just
  // need to upload it now. Same downstream flow as camera:
  // goes straight to step 2 (walk to pothole) since GPS
  // still needs to be captured live, standing on the spot.
  // ===================================================

  Future<void> _pickFromGallery() async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );

    if (picked == null) return; // user cancelled

    setState(() {
      _image = File(picked.path);
      _lastResult = null;
      _step = 2; // go to walk instruction screen
    });
  }

  // ===================================================
  // STEP 2 → STEP 3
  // User confirms they've walked to the pothole.
  // ===================================================

  void _proceedToGps() {
    setState(() => _step = 3);
  }

  // ===================================================
  // STEP 3 — USER TAPS "Enable GPS"
  // Only NOW does GPS start. User must already be
  // physically standing on the pothole at this point.
  // ===================================================

  Future<void> _enableGps() async {
    // Check location service
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

    // Check / request permission
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (mounted) setState(() => _gpsPermissionDenied = true);
      return;
    }

    // Mark GPS as started — hides the button, shows accuracy UI
    setState(() {
      _gpsStarted = true;
      _gpsPermissionDenied = false;
    });

    // Start high-accuracy position stream.
    // distanceFilter: 0 = update even when user is standing still,
    // so accuracy can keep improving as GPS satellite lock improves.
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
  // STEP 3 — CONFIRM LOCATION & UPLOAD
  // Locks the current live position and uploads.
  // Only callable when accuracy ≤ 10 m.
  // ===================================================

  Future<void> _confirmAndUpload() async {
    if (_livePosition == null || _image == null) return;

    // Lock position
    setState(() {
      _confirmedPosition = _livePosition;
      _uploading = true;
      _lastResult = null;
    });

    // Stop GPS stream — no longer needed
    await _posStream?.cancel();
    _posStream = null;

    final result = await ApiService.instance.uploadPothole(
      imageFile: _image!,
      lat: _confirmedPosition!.latitude,
      lng: _confirmedPosition!.longitude,
    );

    if (mounted) {
      setState(() {
        _uploading = false;
        _lastResult = result;
      });
    }
  }

  // ===================================================
  // RESTART — report another pothole from step 1
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
                    if (_step == 1) {
                      _image = null;
                    }
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
  // STEP 1 UI — Take Photo
  // ===================================================

  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          const StepIndicator(activeStep: 1),
          const SizedBox(height: 28),

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
          const Text(
            'Stand at a safe distance and photograph the pothole.\n'
            'You will mark its exact GPS location in the next steps.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 32),

          // Tap-to-open-camera area
          GestureDetector(
            onTap: _takePhoto,
            child: Container(
              height: 240,
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                border: Border.all(color: const Color(0xFF30363D)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.camera_alt_outlined,
                      size: 64, color: Color(0xFF1F6FEB)),
                  SizedBox(height: 12),
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

          const SizedBox(height: 20),

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

          // Already have a photo? Upload from gallery instead.
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
  // STEP 2 UI — Walk Instruction
  // No GPS here. Pure instruction screen.
  // ===================================================

  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          const StepIndicator(activeStep: 2),
          const SizedBox(height: 28),

          // Photo thumbnail confirm
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

          // Instruction card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              border: Border.all(
                  color: const Color(0xFFF39C12).withOpacity(0.5)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const Icon(Icons.directions_walk,
                    color: Color(0xFFF39C12), size: 48),
                const SizedBox(height: 14),
                const Text(
                  'Step 2: Walk to the pothole',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                const Text(
                  'Now walk and stand EXACTLY on or beside\n'
                  'the pothole you just photographed.\n\n'
                  'Once you are standing on it, tap the button\n'
                  'below to enable GPS and mark the location.',
                  style: TextStyle(color: Colors.white60, fontSize: 13.5, height: 1.6),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // Visual tip
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.info_outline,
                          color: Colors.white38, size: 14),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'GPS will only start after you tap — '
                          'this ensures the location is yours on the pothole.',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 11),
                        ),
                      ),
                    ],
                  ),
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
  // STEP 3 UI — GPS Confirm
  // Two sub-states:
  //   a) _gpsStarted == false → show "Enable GPS" button
  //   b) _gpsStarted == true  → show live accuracy + confirm button
  // ===================================================

  Widget _buildStep3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          const StepIndicator(activeStep: 3),
          const SizedBox(height: 24),

          // Photo thumbnail
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

          // ── SUB-STATE A: GPS not yet started ──
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
                        color: Colors.white60, fontSize: 13.5, height: 1.6),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // GPS permission denied warning
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

          // ── SUB-STATE B: GPS started, showing live accuracy ──
          if (_gpsStarted) ...[
            AccuracyCard(livePosition: _livePosition),
            const SizedBox(height: 20),

            // Result card (shown after upload attempt)
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

            // Confirm button — only shown before upload
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