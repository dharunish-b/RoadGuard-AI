import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// =====================================================
// CONFIG — backend URL is now RUNTIME-CONFIGURABLE
//
// Since the ngrok free-tier URL changes every time you
// restart ngrok, the URL is no longer a hardcoded const.
// It's stored in SharedPreferences under `kBaseUrlPref` and
// can be changed from the Simulation page's "Connect" box.
//
// Default fallback (used until the user connects a URL):
//   Android emulator  → http://10.0.2.2:8000
//   Physical device via USB (adb reverse) → http://localhost:8000
//   Physical device via ngrok → https://xxxx.ngrok-free.app
// =====================================================

const String kBaseUrlPref = 'backend_base_url';
const String kDefaultBaseUrl = 'http://10.0.2.2:8000';

class ApiConfig {
  static String _baseUrl = kDefaultBaseUrl;
  static bool _loaded = false;

  static String get baseUrl => _baseUrl;

  static const Duration timeout = Duration(seconds: 15);

  // ---------------------------------------------------
  // Call once at app startup (main.dart) so the last
  // connected ngrok URL survives an app restart.
  // ---------------------------------------------------
  static Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(kBaseUrlPref);
    if (saved != null && saved.trim().isNotEmpty) {
      _baseUrl = saved;
    }
    _loaded = true;
  }

  // ---------------------------------------------------
  // Called from the Simulation page's Connect button
  // (and by the background isolate, which loads its own
  // copy of SharedPreferences since it can't share memory
  // with the UI isolate).
  // ---------------------------------------------------
  static Future<void> setBaseUrl(String url) async {
    var cleaned = url.trim();
    if (cleaned.endsWith('/')) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }
    if (cleaned.isEmpty) return;
    _baseUrl = cleaned;
    _loaded = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kBaseUrlPref, cleaned);
  }
}

// =====================================================
// ALERT LEVEL — mirrors FastAPI response
// =====================================================

enum AlertLevel {
  none,    // no pothole nearby
  stage1,  // pothole detected, low severity  → light sound
  stage2,  // medium severity                 → normal sound + brief flash
  stage3,  // high severity                   → extreme sound + continuous flash
}

// =====================================================
// POTHOLE NEARBY RESPONSE
// =====================================================

class PotholeAlert {
  final AlertLevel level;
  final String message;
  final double? distance;     // metres to nearest hazard
  final double? severity;     // 0.0 – 1.0
  final String? weatherNote;

  const PotholeAlert({
    required this.level,
    required this.message,
    this.distance,
    this.severity,
    this.weatherNote,
  });

  factory PotholeAlert.none() => const PotholeAlert(
        level: AlertLevel.none,
        message: 'All clear',
      );

  factory PotholeAlert.fromJson(Map<String, dynamic> json) {
    final int stage = (json['alert_stage'] as num?)?.toInt() ?? 0;
    final AlertLevel level = switch (stage) {
      1 => AlertLevel.stage1,
      2 => AlertLevel.stage2,
      3 => AlertLevel.stage3,
      _ => AlertLevel.none,
    };

    return PotholeAlert(
      level: level,
      message: json['message'] as String? ?? '',
      distance: (json['distance_m'] as num?)?.toDouble(),
      severity: (json['severity'] as num?)?.toDouble(),
      weatherNote: json['weather_note'] as String?,
    );
  }
}

// =====================================================
// UPLOAD RESPONSE
// =====================================================

class UploadResult {
  final bool success;
  final String message;
  final int? alertStage;
  final double? severity;
  final String? detectionLabel;

  const UploadResult({
    required this.success,
    required this.message,
    this.alertStage,
    this.severity,
    this.detectionLabel,
  });

  factory UploadResult.fromJson(Map<String, dynamic> json) {
    return UploadResult(
      success: json['success'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      alertStage: (json['alert_stage'] as num?)?.toInt(),
      severity: (json['severity'] as num?)?.toDouble(),
      detectionLabel: json['label'] as String?,
    );
  }

  factory UploadResult.error(String msg) =>
      UploadResult(success: false, message: msg);
}

// =====================================================
// API SERVICE
// =====================================================

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  // ---------------------------------------------------
  // CHECK NEARBY POTHOLES (used by background service + simulation)
  // POST /api/check-nearby
  // Body: { "lat": ..., "lng": ..., "speed_kmh": ..., "weather": ... }
  // ---------------------------------------------------

  Future<PotholeAlert> checkNearby({
    required double lat,
    required double lng,
    double speedKmh = 30,
    String weather = 'dry',
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/check-nearby');

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'lat': lat,
              'lng': lng,
              'speed_kmh': speedKmh,
              'weather': weather,
            }),
          )
          .timeout(ApiConfig.timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return PotholeAlert.fromJson(data);
      } else {
        return PotholeAlert.none();
      }
    } on SocketException {
      // Backend unreachable — silent fail, don't crash the service
      return PotholeAlert.none();
    } catch (_) {
      return PotholeAlert.none();
    }
  }

  // ---------------------------------------------------
  // UPLOAD POTHOLE IMAGE
  // POST /api/upload
  // Multipart: image file + lat + lng
  // ---------------------------------------------------

  Future<UploadResult> uploadPothole({
    required File imageFile,
    required double lat,
    required double lng,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/upload');

      final request = http.MultipartRequest('POST', uri)
        ..fields['lat'] = lat.toString()
        ..fields['lng'] = lng.toString()
        ..files.add(
          await http.MultipartFile.fromPath('image', imageFile.path),
        );

      final streamedResponse =
          await request.send().timeout(ApiConfig.timeout);
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return UploadResult.fromJson(data);
      } else {
        return UploadResult.error(
          'Server error ${response.statusCode}',
        );
      }
    } on SocketException {
      return UploadResult.error(
        'Cannot reach server at ${ApiConfig.baseUrl} — connect the backend '
        'URL from the Simulation page first.',
      );
    } catch (e) {
      return UploadResult.error(e.toString());
    }
  }

  // ---------------------------------------------------
  // HEALTH CHECK — test if backend is reachable
  // GET /health
  // ---------------------------------------------------

  Future<bool> isBackendAlive({String? overrideUrl}) async {
    try {
      final base = overrideUrl ?? ApiConfig.baseUrl;
      final uri = Uri.parse('$base/health');
      final response = await http.get(uri).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}