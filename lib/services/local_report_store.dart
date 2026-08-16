import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

// =====================================================
// LOCAL REPORT STORE
//
// Persists every pothole the current user uploads to
// SharedPreferences as a JSON list. Since there is no
// auth, this is inherently per-device — each phone only
// ever sees its own uploads, which is exactly what we want.
//
// Key: 'user_pothole_reports'
// Value: JSON-encoded List<Map>
//
// Usage:
//   // After a successful upload:
//   await LocalReportStore.instance.add(LocalPotholeReport(...));
//
//   // In ReportsPage:
//   final reports = await LocalReportStore.instance.getAll();
//
//   // After marking fixed:
//   await LocalReportStore.instance.markFixed(potholeId);
// =====================================================

const String _kReportsKey = 'user_pothole_reports';

class LocalReportStore {
  LocalReportStore._();
  static final LocalReportStore instance = LocalReportStore._();

  // ── Write: add a new report after upload ──────────

  Future<void> add(LocalPotholeReport report) async {
    final prefs   = await SharedPreferences.getInstance();
    final current = _loadList(prefs);

    // Guard: don't double-save the same pothole_id
    current.removeWhere((r) => r.potholeId == report.potholeId);
    current.insert(0, report); // newest first

    await prefs.setString(_kReportsKey, jsonEncode(
      current.map((r) => r.toJson()).toList(),
    ));
  }

  // ── Read: all reports, newest first ───────────────

  Future<List<LocalPotholeReport>> getAll() async {
    final prefs = await SharedPreferences.getInstance();
    return _loadList(prefs);
  }

  // ── Write: mark one pothole as fixed locally ──────
  //
  // Called AFTER the backend PATCH succeeds, so the UI
  // reflects the fix even if the app is restarted.

  Future<void> markFixed(String potholeId) async {
    final prefs   = await SharedPreferences.getInstance();
    final current = _loadList(prefs);

    final idx = current.indexWhere((r) => r.potholeId == potholeId);
    if (idx == -1) return;

    current[idx] = current[idx].copyWithFixed();

    await prefs.setString(_kReportsKey, jsonEncode(
      current.map((r) => r.toJson()).toList(),
    ));
  }

  // ── Internal ──────────────────────────────────────

  List<LocalPotholeReport> _loadList(SharedPreferences prefs) {
    final raw = prefs.getString(_kReportsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => LocalPotholeReport.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
}

// =====================================================
// LOCAL POTHOLE REPORT MODEL
// =====================================================

class LocalPotholeReport {
  final String   potholeId;
  final String?  imagePath;   // absolute path on this device's storage
  final double   lat;
  final double   lon;
  final String   severity;
  final double?  confidence;
  final String?  fallType;
  final DateTime uploadedAt;
  final bool     isDemo;      // true if uploaded via Demo Coordinates mode
  final bool     fixed;
  final DateTime? fixedAt;

  const LocalPotholeReport({
    required this.potholeId,
    this.imagePath,
    required this.lat,
    required this.lon,
    required this.severity,
    this.confidence,
    this.fallType,
    required this.uploadedAt,
    this.isDemo = false,
    this.fixed = false,
    this.fixedAt,
  });

  // ── Serialisation ──────────────────────────────────

  Map<String, dynamic> toJson() => {
        'pothole_id':   potholeId,
        'image_path':   imagePath,
        'lat':          lat,
        'lon':          lon,
        'severity':     severity,
        'confidence':   confidence,
        'fall_type':    fallType,
        'uploaded_at':  uploadedAt.toIso8601String(),
        'is_demo':      isDemo,
        'fixed':        fixed,
        'fixed_at':     fixedAt?.toIso8601String(),
      };

  factory LocalPotholeReport.fromJson(Map<String, dynamic> j) =>
      LocalPotholeReport(
        potholeId:   j['pothole_id']  as String,
        imagePath:   j['image_path']  as String?,
        lat:         (j['lat']        as num).toDouble(),
        lon:         (j['lon']        as num).toDouble(),
        severity:    j['severity']    as String? ?? 'unknown',
        confidence:  (j['confidence'] as num?)?.toDouble(),
        fallType:    j['fall_type']   as String?,
        uploadedAt:  DateTime.parse(j['uploaded_at'] as String),
        isDemo:      j['is_demo']     as bool? ?? false,
        fixed:       j['fixed']       as bool? ?? false,
        fixedAt:     j['fixed_at'] != null
            ? DateTime.tryParse(j['fixed_at'] as String)
            : null,
      );

  // ── Copy with fixed ────────────────────────────────

  LocalPotholeReport copyWithFixed() => LocalPotholeReport(
        potholeId:   potholeId,
        imagePath:   imagePath,
        lat:         lat,
        lon:         lon,
        severity:    severity,
        confidence:  confidence,
        fallType:    fallType,
        uploadedAt:  uploadedAt,
        isDemo:      isDemo,
        fixed:       true,
        fixedAt:     DateTime.now(),
      );
}
