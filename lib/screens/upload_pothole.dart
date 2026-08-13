import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import '../services/api_service.dart';

class UploadPotholePage extends StatefulWidget {
  const UploadPotholePage({super.key});

  @override
  State<UploadPotholePage> createState() => _UploadPotholePageState();
}

class _UploadPotholePageState extends State<UploadPotholePage> {
  File? image;
  final latController = TextEditingController();
  final lngController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  bool _uploading = false;
  UploadResult? _lastResult;

  // ---------------------------------------------------
  // PICK IMAGE
  // ---------------------------------------------------

  Future<void> pickImage() async {
    final XFile? picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null) {
      setState(() {
        image = File(picked.path);
        _lastResult = null;
      });
    }
  }

  // ---------------------------------------------------
  // GET LOCATION
  // ---------------------------------------------------

  Future<void> getLocation() async {
    bool enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      _snack('Please enable Location on your device');
      return;
    }

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) {
        _snack('Location permission denied');
        return;
      }
    }
    if (perm == LocationPermission.deniedForever) {
      _snack('Location permission permanently denied');
      return;
    }

    final pos = await Geolocator.getCurrentPosition();
    setState(() {
      latController.text = pos.latitude.toString();
      lngController.text = pos.longitude.toString();
    });
  }

  // ---------------------------------------------------
  // SUBMIT — calls FastAPI /api/upload
  // ---------------------------------------------------

  Future<void> _submit() async {
    if (image == null) {
      _snack('Please select a pothole image');
      return;
    }
    final lat = double.tryParse(latController.text);
    final lng = double.tryParse(lngController.text);
    if (lat == null || lng == null) {
      _snack('Please enter valid latitude and longitude');
      return;
    }

    setState(() {
      _uploading = true;
      _lastResult = null;
    });

    final result = await ApiService.instance.uploadPothole(
      imageFile: image!,
      lat: lat,
      lng: lng,
    );

    if (mounted) {
      setState(() {
        _uploading = false;
        _lastResult = result;
      });
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    latController.dispose();
    lngController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------
  // UI
  // ---------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: const Text('Upload Pothole'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // IMAGE AREA
            GestureDetector(
              onTap: pickImage,
              child: Container(
                height: 220,
                decoration: BoxDecoration(
                  color: const Color(0xFF161B22),
                  border: Border.all(
                    color: image != null
                        ? const Color(0xFF238636)
                        : const Color(0xFF30363D),
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: image == null
                    ? const Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_photo_alternate_outlined,
                              size: 48, color: Colors.white38),
                          SizedBox(height: 8),
                          Text('Tap to select image',
                              style: TextStyle(color: Colors.white38)),
                        ],
                      )
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: Image.file(image!,
                            fit: BoxFit.cover, width: double.infinity),
                      ),
              ),
            ),

            const SizedBox(height: 16),

            // UPLOAD PHOTO BUTTON
            OutlinedButton.icon(
              onPressed: pickImage,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Color(0xFF30363D)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.photo),
              label: const Text('Choose from Gallery'),
            ),

            const SizedBox(height: 28),

            // LATITUDE
            _textField(
              controller: latController,
              label: 'Latitude',
              hint: 'e.g. 9.9252',
            ),

            const SizedBox(height: 16),

            // LONGITUDE
            _textField(
              controller: lngController,
              label: 'Longitude',
              hint: 'e.g. 78.1198',
            ),

            const SizedBox(height: 16),

            // GET LOCATION
            OutlinedButton.icon(
              onPressed: getLocation,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF58A6FF),
                side: const BorderSide(color: Color(0xFF1F6FEB)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.my_location),
              label: const Text('Use Current Location'),
            ),

            const SizedBox(height: 28),

            // RESULT CARD
            if (_lastResult != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _lastResult!.success
                      ? const Color(0xFF238636).withOpacity(0.2)
                      : Colors.red.withOpacity(0.2),
                  border: Border.all(
                    color: _lastResult!.success
                        ? const Color(0xFF238636)
                        : Colors.red,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          _lastResult!.success
                              ? Icons.check_circle
                              : Icons.error,
                          color: _lastResult!.success
                              ? const Color(0xFF2ECC71)
                              : Colors.red,
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _lastResult!.success ? 'Uploaded!' : 'Upload Failed',
                          style: TextStyle(
                            color: _lastResult!.success
                                ? const Color(0xFF2ECC71)
                                : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _lastResult!.message,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    if (_lastResult!.detectionLabel != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Detected: ${_lastResult!.detectionLabel}',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                    if (_lastResult!.severity != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Severity: ${(_lastResult!.severity! * 100).toStringAsFixed(0)}%',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                    if (_lastResult!.alertStage != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Alert Stage: ${_lastResult!.alertStage}',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // SUBMIT
            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _uploading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1F6FEB),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  elevation: 0,
                ),
                child: _uploading
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 12),
                          Text('Uploading…'),
                        ],
                      )
                    : const Text(
                        'Submit',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white54),
        hintStyle: const TextStyle(color: Colors.white24),
        prefixIcon: const Icon(Icons.location_on, color: Colors.white38),
        enabledBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF30363D)),
        ),
        focusedBorder: const OutlineInputBorder(
          borderSide: BorderSide(color: Color(0xFF1F6FEB)),
        ),
        filled: true,
        fillColor: const Color(0xFF161B22),
      ),
    );
  }
}