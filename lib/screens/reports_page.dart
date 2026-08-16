import 'dart:io';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/local_report_store.dart';

// =====================================================
// REPORTS PAGE
//
// Shows ONLY the potholes this user uploaded on this device.
// Data source: LocalReportStore (SharedPreferences cache).
// No backend fetch for the list — purely local.
//
// The ✔ fix button:
//   1. Shows confirmation dialog
//   2. Calls PATCH /reports/{id}/fix on the backend
//      → so the alert route stops warning riders there
//   3. Calls LocalReportStore.markFixed() to persist
//      the fixed state locally
//   4. Card updates in-place with green Fixed stamp
//
// Image: displayed from the local file path saved at
// upload time — no network needed, loads instantly.
// =====================================================

class ReportsPage extends StatefulWidget {
  const ReportsPage({super.key});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}

class _ReportsPageState extends State<ReportsPage> {
  bool _loading = true;
  List<LocalPotholeReport> _all = [];

  // 'all' | 'active' | 'fixed'
  String _filter = 'all';

  List<LocalPotholeReport> get _filtered => switch (_filter) {
        'active' => _all.where((r) => !r.fixed).toList(),
        'fixed'  => _all.where((r) => r.fixed).toList(),
        _        => _all,
      };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final reports = await LocalReportStore.instance.getAll();
    if (mounted) setState(() { _all = reports; _loading = false; });
  }

  // ===================================================
  // MARK FIXED
  // ===================================================

  Future<void> _markFixed(LocalPotholeReport report) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Row(
          children: [
            Icon(Icons.check_circle_outline,
                color: Color(0xFF2ECC71), size: 22),
            SizedBox(width: 10),
            Text(
              'Mark as Fixed?',
              style: TextStyle(color: Colors.white, fontSize: 17),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Show the photo in the dialog too
            if (report.imagePath != null &&
                File(report.imagePath!).existsSync())
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(report.imagePath!),
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            const SizedBox(height: 14),
            const Text(
              'Confirm this pothole has been repaired.\n'
              'It will stop triggering alerts for riders.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.5),
            ),
            const SizedBox(height: 10),
            _coordRow(report.lat, report.lon),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF238636),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
              elevation: 0,
            ),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Yes, It\'s Fixed'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // 1. Optimistic UI update
    final idx = _all.indexWhere((r) => r.potholeId == report.potholeId);
    if (idx == -1) return;
    setState(() => _all[idx] = _all[idx].copyWithFixed());

    // 2. Tell backend → alert route will stop firing for this spot
    final backendOk =
        await ApiService.instance.markPotholeFixed(report.potholeId);

    // 3. Persist fix locally regardless of backend result
    //    (if backend failed, the pothole may still alert — show warning)
    await LocalReportStore.instance.markFixed(report.potholeId);

    if (!mounted) return;

    if (backendOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅  Marked as fixed — riders will no longer be alerted here'),
          backgroundColor: Color(0xFF238636),
          duration: Duration(seconds: 3),
        ),
      );
    } else {
      // Still marked locally, but backend didn't update — riders may still get alerted
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '⚠️  Saved locally but backend unreachable — '
            'connect backend to fully remove the alert',
          ),
          backgroundColor: Color(0xFFF39C12),
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  // ===================================================
  // BUILD
  // ===================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('My Reports'),
            if (!_loading)
              Text(
                '${_all.length} pothole${_all.length == 1 ? '' : 's'} reported by you',
                style: const TextStyle(fontSize: 11, color: Colors.white54),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          if (!_loading && _all.isNotEmpty)
            _FilterBar(
              selected:    _filter,
              allCount:    _all.length,
              activeCount: _all.where((r) => !r.fixed).length,
              fixedCount:  _all.where((r) => r.fixed).length,
              onChanged:   (f) => setState(() => _filter = f),
            ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF1F6FEB)),
      );
    }

    if (_all.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.add_road, color: Colors.white24, size: 56),
              const SizedBox(height: 16),
              const Text(
                'No reports yet',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Potholes you report will appear here.\n'
                'Only you can see your own reports.',
                style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final list = _filtered;

    if (list.isEmpty) {
      return Center(
        child: Text(
          _filter == 'fixed'
              ? 'None of your reports are fixed yet'
              : 'All your reported potholes are fixed ✅',
          style: const TextStyle(color: Colors.white38, fontSize: 14),
          textAlign: TextAlign.center,
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      color: const Color(0xFF1F6FEB),
      backgroundColor: const Color(0xFF161B22),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: list.length,
        itemBuilder: (ctx, i) => _ReportCard(
          report: list[i],
          onMarkFixed: () => _markFixed(list[i]),
        ),
      ),
    );
  }

  Widget _coordRow(double lat, double lon) => Row(
        children: [
          const Icon(Icons.location_pin, color: Colors.white24, size: 13),
          const SizedBox(width: 5),
          Text(
            '${lat.toStringAsFixed(5)},  ${lon.toStringAsFixed(5)}',
            style: const TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontFamily: 'monospace',
            ),
          ),
        ],
      );
}

// =====================================================
// FILTER BAR
// =====================================================

class _FilterBar extends StatelessWidget {
  final String selected;
  final int allCount;
  final int activeCount;
  final int fixedCount;
  final ValueChanged<String> onChanged;

  const _FilterBar({
    required this.selected,
    required this.allCount,
    required this.activeCount,
    required this.fixedCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF161B22),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          _chip('all',    'All ($allCount)',       Icons.list_alt),
          const SizedBox(width: 8),
          _chip('active', 'Active ($activeCount)', Icons.warning_amber_rounded),
          const SizedBox(width: 8),
          _chip('fixed',  'Fixed ($fixedCount)',   Icons.check_circle),
        ],
      ),
    );
  }

  Widget _chip(String value, String label, IconData icon) {
    final bool active = selected == value;
    final Color color = value == 'fixed'
        ? const Color(0xFF238636)
        : value == 'active'
            ? const Color(0xFFF39C12)
            : const Color(0xFF1F6FEB);

    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.18) : Colors.transparent,
            border: Border.all(
                color: active ? color : const Color(0xFF30363D)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12,
                  color: active ? color : Colors.white38),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight:
                      active ? FontWeight.bold : FontWeight.normal,
                  color: active ? color : Colors.white38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// =====================================================
// REPORT CARD
// =====================================================

class _ReportCard extends StatelessWidget {
  final LocalPotholeReport report;
  final VoidCallback onMarkFixed;

  const _ReportCard({required this.report, required this.onMarkFixed});

  Color _sevColor(String s) => switch (s) {
        'low'      => const Color(0xFF2ECC71),
        'medium'   => const Color(0xFFF39C12),
        'high'     => const Color(0xFFE74C3C),
        'critical' => const Color(0xFFB71C1C),
        _          => Colors.white38,
      };

  String _sevLabel(String s) => switch (s) {
        'low'      => '🟢  Low',
        'medium'   => '🟡  Medium',
        'high'     => '🔴  High',
        'critical' => '🚨  Critical',
        _          => '⚪  Unknown',
      };

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays > 0)    return '${diff.inDays}d ago';
    if (diff.inHours > 0)   return '${diff.inHours}h ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    final r     = report;
    final color = _sevColor(r.severity);
    final fixed = r.fixed;
    final hasImage = r.imagePath != null && File(r.imagePath!).existsSync();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        border: Border.all(
          color: fixed
              ? const Color(0xFF238636).withOpacity(0.5)
              : color.withOpacity(0.3),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          // ── Photo ─────────────────────────────────
          if (hasImage)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(11)),
              child: Stack(
                children: [
                  Image.file(
                    File(r.imagePath!),
                    height: 180,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                  // Fixed overlay on image
                  if (fixed)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black.withOpacity(0.45),
                        child: const Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle,
                                  color: Color(0xFF2ECC71), size: 28),
                              SizedBox(width: 8),
                              Text(
                                'REPAIRED',
                                style: TextStyle(
                                  color: Color(0xFF2ECC71),
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  // Demo badge
                  if (r.isDemo)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6E40C9),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: const Text(
                          '🔬 Demo',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            )
          else
            // No image placeholder
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(11)),
              child: Container(
                height: 80,
                color: const Color(0xFF0D1117),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.broken_image_outlined,
                        color: Colors.white24, size: 24),
                    const SizedBox(width: 8),
                    Text(
                      r.isDemo ? '🔬 Demo upload' : 'No image available',
                      style: const TextStyle(
                          color: Colors.white24, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),

          // ── Card body ─────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                // Header: severity badge + fix button
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.15),
                        border: Border.all(color: color.withOpacity(0.5)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _sevLabel(r.severity),
                        style: TextStyle(
                          color: color,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (fixed)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF238636).withOpacity(0.15),
                          border: Border.all(
                              color: const Color(0xFF238636)
                                  .withOpacity(0.5)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.check_circle,
                                color: Color(0xFF2ECC71), size: 13),
                            SizedBox(width: 4),
                            Text(
                              'Fixed',
                              style: TextStyle(
                                color: Color(0xFF2ECC71),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Tooltip(
                        message: 'Mark this pothole as repaired',
                        child: GestureDetector(
                          onTap: onMarkFixed,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF238636)
                                  .withOpacity(0.12),
                              border: Border.all(
                                  color: const Color(0xFF238636)
                                      .withOpacity(0.5)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.check,
                              color: Color(0xFF2ECC71),
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 10),

                // Coordinates
                Row(
                  children: [
                    const Icon(Icons.location_pin,
                        color: Colors.white38, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      '${r.lat.toStringAsFixed(5)},  '
                      '${r.lon.toStringAsFixed(5)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // Meta chips
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _meta(Icons.access_time,
                        'Uploaded ${_timeAgo(r.uploadedAt)}'),
                    if (r.fallType != null)
                      _meta(Icons.category_outlined, r.fallType!),
                    if (r.confidence != null)
                      _meta(Icons.analytics_outlined,
                          '${(r.confidence! * 100).toStringAsFixed(0)}% confidence'),
                  ],
                ),

                // Fixed-at
                if (fixed && r.fixedAt != null) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.build_circle_outlined,
                          color: Color(0xFF2ECC71), size: 13),
                      const SizedBox(width: 5),
                      Text(
                        'Marked repaired ${_timeAgo(r.fixedAt!)}',
                        style: const TextStyle(
                          color: Color(0xFF2ECC71),
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white24),
          const SizedBox(width: 4),
          Text(text,
              style: const TextStyle(
                  color: Colors.white38, fontSize: 11)),
        ],
      );
}
