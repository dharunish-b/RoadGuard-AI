// =====================================================
// SIMULATION COORDINATES — single source of truth
//
// kPotholeIdFallback → hardcoded safety net only.
//                      Used when no demo upload has been
//                      done yet in the current app install.
//
// kDemoPotholeIdKey  → SharedPreferences key where the ID
//                      returned by the last demo upload is
//                      persisted. SimulationController reads
//                      this at start time and uses it instead
//                      of the fallback.
//
// kSimLat / kSimLng  → coordinates sent on every demo upload.
//                      Must match what's stored in MongoDB for
//                      the seeded pothole so the simulation
//                      route can find it by geospatial query.
// =====================================================

/// Prefs key — stores the _id returned from the last demo upload.
const String kDemoPotholeIdKey = 'demo_pothole_id';

/// Hard-coded fallback — used only if no demo upload has ever been done.
const String kPotholeIdFallback = '6a7d97d7d97b2fc1c888747c';

/// Latitude pinned for all demo-mode uploads.
const double kSimLat = 9.9252;   // <-- set to your seeded lat

/// Longitude pinned for all demo-mode uploads.
const double kSimLng = 78.1198;  // <-- set to your seeded lng
