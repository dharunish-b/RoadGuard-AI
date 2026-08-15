import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String kBaseUrlPref = 'backend_base_url';
const String kDefaultBaseUrl = 'http://10.0.2.2:8000';

const Map<String, String> kNgrokSkipHeader = {
  'ngrok-skip-browser-warning': 'true',
};

// =====================================================
// API CONFIG  — unchanged
// =====================================================

class ApiConfig {
  static String _baseUrl = kDefaultBaseUrl;
  static bool _loaded = false;

  static String get baseUrl => _baseUrl;

  static const Duration timeout = Duration(seconds: 15);

  static Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(kBaseUrlPref);
    if (saved != null && saved.trim().isNotEmpty) {
      _baseUrl = saved;
    }
    _loaded = true;
  }

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
// ENUMS & MODELS  — unchanged
// =====================================================

enum AlertLevel {
  none,
  stage1,
  stage2,
  stage3,
}

class PotholeAlert {
  final AlertLevel level;
  final String message;
  final double? distance;
  final double? severity;
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
    final bool fires = json['alert'] as bool? ?? false;
    final String? severityStr = json['severity'] as String?;

    final AlertLevel level = !fires
        ? AlertLevel.none
        : switch (severityStr) {
            'low' => AlertLevel.stage1,
            'medium' => AlertLevel.stage2,
            'high' => AlertLevel.stage3,
            'critical' => AlertLevel.stage3,
            _ => AlertLevel.none,
          };

    return PotholeAlert(
      level: level,
      message: json['message'] as String? ?? 'All clear',
      distance: (json['distance_m'] as num?)?.toDouble(),
      severity: null,
      weatherNote: null,
    );
  }
}

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
    final int detections = (json['detections'] as num?)?.toInt() ?? 0;
    final List results = json['results'] as List? ?? [];
    final Map<String, dynamic>? first =
        results.isNotEmpty ? results.first as Map<String, dynamic> : null;

    final String? severityStr = first?['severity'] as String?;
    final AlertLevel level = switch (severityStr) {
      'low' => AlertLevel.stage1,
      'medium' => AlertLevel.stage2,
      'high' || 'critical' => AlertLevel.stage3,
      _ => AlertLevel.none,
    };

    return UploadResult(
      success: detections > 0,
      message: detections > 0
          ? 'Pothole detected and saved'
          : 'No pothole detected in image',
      alertStage: level == AlertLevel.none ? null : level.index,
      severity: (first?['confidence'] as num?)?.toDouble(),
      detectionLabel: first?['fall_type'] as String?,
    );
  }

  factory UploadResult.error(String msg) =>
      UploadResult(success: false, message: msg);
}

// =====================================================
// NEW — Monitoring session model
// Returned by /alert/start, carried until /alert/stop
// =====================================================

class MonitoringSession {
  final String sessionId;
  final DateTime startedAt;

  const MonitoringSession({
    required this.sessionId,
    required this.startedAt,
  });

  factory MonitoringSession.fromJson(Map<String, dynamic> json) {
    return MonitoringSession(
      sessionId: json['session_id'] as String? ?? '',
      startedAt: DateTime.tryParse(json['started_at'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

// =====================================================
// API SERVICE
// =====================================================

class ApiService {
  ApiService._();
  static final ApiService instance = ApiService._();

  // ---------------------------------------------------
  // EXISTING — GET /alert  (unchanged)
  // Called by background service polling loop.
  // Movement gate is applied BEFORE calling this —
  // see background_service.dart / HomeScreen.
  // ---------------------------------------------------

  Future<PotholeAlert> checkNearby({
    required double lat,
    required double lng,
    double speedKmh = 30,
    String weather = 'dry',
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/alert').replace(
        queryParameters: {
          'lat': lat.toString(),
          'lon': lng.toString(),
          'speed_kmh': speedKmh.toString(),
        },
      );

      final response = await http
          .get(uri, headers: kNgrokSkipHeader)
          .timeout(ApiConfig.timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return PotholeAlert.fromJson(data);
      } else {
        return PotholeAlert.none();
      }
    } on SocketException {
      return PotholeAlert.none();
    } catch (_) {
      return PotholeAlert.none();
    }
  }

  // ---------------------------------------------------
  // EXISTING — GET /simulate/step  (unchanged)
  // ---------------------------------------------------

  Future<PotholeAlert> simulateStep({
    required String potholeId,
    required int step,
    required String condition,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/simulate/step').replace(
        queryParameters: {
          'pothole_id': potholeId,
          'step': step.toString(),
          'condition': condition,
        },
      );

      final response = await http
          .get(uri, headers: kNgrokSkipHeader)
          .timeout(ApiConfig.timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return PotholeAlert.fromJson(data);
      }

      return PotholeAlert.none();
    } catch (_) {
      return PotholeAlert.none();
    }
  }

  // ---------------------------------------------------
  // EXISTING — POST /upload  (unchanged)
  // ---------------------------------------------------

  Future<UploadResult> uploadPothole({
    required File imageFile,
    required double lat,
    required double lng,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/upload');

      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll(kNgrokSkipHeader)
        ..fields['lat'] = lat.toString()
        ..fields['lon'] = lng.toString()
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
        return UploadResult.error('Server error ${response.statusCode}');
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
  // EXISTING — GET /health  (unchanged)
  // ---------------------------------------------------

  Future<bool> isBackendAlive({String? overrideUrl}) async {
    try {
      final base = overrideUrl ?? ApiConfig.baseUrl;
      final uri = Uri.parse('$base/health');
      final response = await http
          .get(uri, headers: kNgrokSkipHeader)
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  // ---------------------------------------------------
  // NEW — POST /alert/start
  // Called when user taps START button.
  // Backend creates a session document in MongoDB and
  // returns a session_id used for /alert/stop.
  // If backend unreachable, returns a local fallback
  // session so monitoring still runs (offline-tolerant).
  // ---------------------------------------------------

  Future<MonitoringSession> startMonitoring({
    required double lat,
    required double lng,
    required double speedKmh,
    required String weather,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/alert/start');

      final response = await http
          .post(
            uri,
            headers: {
              ...kNgrokSkipHeader,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'lat': lat,
              'lon': lng,
              'speed_kmh': speedKmh,
              'weather': weather,
            }),
          )
          .timeout(ApiConfig.timeout);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return MonitoringSession.fromJson(data);
      }

      // Non-200 — use local fallback session
      return _localSession();
    } on SocketException {
      return _localSession();
    } catch (_) {
      return _localSession();
    }
  }

  // ---------------------------------------------------
  // NEW — POST /alert/stop
  // Called when user taps STOP button.
  // Sends session summary back to backend (MongoDB).
  // Fails silently — STOP always succeeds on UI side.
  // ---------------------------------------------------

  Future<void> stopMonitoring({
    required String sessionId,
    required double endLat,
    required double endLng,
  }) async {
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/alert/stop');

      await http
          .post(
            uri,
            headers: {
              ...kNgrokSkipHeader,
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'session_id': sessionId,
              'end_lat': endLat,
              'end_lon': endLng,
            }),
          )
          .timeout(ApiConfig.timeout);

      // Response ignored — STOP is fire-and-forget.
    } catch (_) {
      // Fail silently. UI has already stopped monitoring.
    }
  }

  // ---------------------------------------------------
  // INTERNAL — local fallback session when backend down
  // Allows monitoring to run even if /alert/start fails.
  // ---------------------------------------------------

  MonitoringSession _localSession() {
    return MonitoringSession(
      sessionId: 'local_${DateTime.now().millisecondsSinceEpoch}',
      startedAt: DateTime.now(),
    );
  }
}