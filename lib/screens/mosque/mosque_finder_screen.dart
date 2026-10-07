import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../../providers/prayer_provider.dart';
import '../../core/constants/app_colors.dart';


class MosqueFinderScreen extends StatefulWidget {
  const MosqueFinderScreen({super.key});

  @override
  State<MosqueFinderScreen> createState() => _MosqueFinderScreenState();
}

class _MosqueFinderScreenState extends State<MosqueFinderScreen> {
  final MapController _mapController = MapController();
  _MosqueInfo? _selectedMosque;
  final TextEditingController _searchController = TextEditingController();

  bool _filterWomens = false;
  bool _filterJumua = false;
  bool _isLoadingRoute = false;
  List<LatLng> _routePoints = [];

  late List<_MosqueInfo> _mosques;

  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _mosques = [];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchRealMosques();
    });
  }

  Future<void> _fetchRealMosques() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    // context.read is correct here — we only need the value once, not reactively
    final prayers = context.read<PrayerProvider>();
    final lat = prayers.latitude;
    final lon = prayers.longitude;
    const radiusMeters = 5000; // 5 km radius

    // Warn the user if we're falling back to the hardcoded Dhaka default
    const defaultLat = 23.8103;
    const defaultLon = 90.4125;
    if ((lat - defaultLat).abs() < 0.001 && (lon - defaultLon).abs() < 0.001) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⚠️ GPS location not available. Searching near Dhaka (default).\nEnable GPS for accurate mosque results.',
            ),
            duration: Duration(seconds: 5),
          ),
        );
      }
    }


    try {
      final query =
          '[out:json][timeout:25];'
          '(node["amenity"="place_of_worship"]["religion"="muslim"](around:$radiusMeters,$lat,$lon);'
          'way["amenity"="place_of_worship"]["religion"="muslim"](around:$radiusMeters,$lat,$lon););'
          'out center qt;';

      http.Response response;
      // Mirrors ordered by reliability for South Asian networks
      final endpoints = [
        'https://overpass.openstreetmap.ru/api/interpreter',
        'https://overpass.private.coffee/api/interpreter',
        'https://overpass-api.de/api/interpreter',
        'https://overpass.kumi.systems/api/interpreter',
        'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
      ];

      response = await _tryOverpassEndpoints(endpoints, query);

      if (response.statusCode != 200) {
        throw Exception('Server error: ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = data['elements'] as List? ?? [];

      final userPos = LatLng(lat, lon);
      const distCalc = Distance();

      final List<_MosqueInfo> fetched = [];
      for (int i = 0; i < elements.length; i++) {
        final el = elements[i] as Map<String, dynamic>;
        final tags = el['tags'] as Map<String, dynamic>? ?? {};

        // Get coordinates — nodes have lat/lon directly, ways/relations have 'center'
        double? mLat, mLon;
        if (el.containsKey('lat')) {
          mLat = (el['lat'] as num).toDouble();
          mLon = (el['lon'] as num).toDouble();
        } else if (el.containsKey('center')) {
          final center = el['center'] as Map<String, dynamic>;
          mLat = (center['lat'] as num).toDouble();
          mLon = (center['lon'] as num).toDouble();
        }
        if (mLat == null || mLon == null) continue;

        final mosquePos = LatLng(mLat, mLon);
        final distMeters = distCalc.as(LengthUnit.Meter, userPos, mosquePos);
        final distKm = distMeters / 1000;
        final walkMinutes = (distMeters / 80).ceil(); // ~80 m/min walking speed

        final name = tags['name'] as String? ??
            tags['name:en'] as String? ??
            tags['name:bn'] as String? ??
            'Mosque';

        final address = _buildAddress(tags);

        // Check OSM tags for Women's section and Jumu'ah
        final womensSection = tags['female'] == 'yes' ||
            tags['women'] == 'yes' ||
            tags['prayer_room:women'] == 'yes' ||
            tags['amenity:women'] == 'yes';

        // Assume Jumu'ah for larger mosques (tagged as mosque vs musalla/prayer_room)
        final type = tags['building'] as String? ?? tags['mosque:type'] as String? ?? '';
        final hasJumua = tags['jumua'] == 'yes' ||
            tags['friday_prayer'] == 'yes' ||
            (type != 'musalla' && type != 'prayer_room');

        fetched.add(_MosqueInfo(
          id: '${el['type']}_${el['id']}',
          name: name,
          address: address,
          distance:
              distKm < 1 ? '${distMeters.round()} m' : '${distKm.toStringAsFixed(1)} km',
          walkTime: walkMinutes < 60
              ? '$walkMinutes min'
              : '${walkMinutes ~/ 60}h ${walkMinutes % 60}m',
          hasWomensSection: womensSection,
          hasJumua: hasJumua,
          position: mosquePos,
          distanceMeters: distMeters,
        ));
      }

      // Sort by distance — closest first
      fetched.sort((a, b) => a.distanceMeters.compareTo(b.distanceMeters));

      if (mounted) {
        setState(() {
          _mosques = fetched;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        final msgLower = msg.toLowerCase();
        final String errorText;
        if (msgLower.contains('timeout') || msgLower.contains('timed out')) {
          errorText = 'Mosque server timed out. Tap Retry — it usually works on the 2nd attempt.';
        } else if (msgLower.contains('statuscode:') || msgLower.contains('status:') || msgLower.contains('http')) {
          errorText = 'Mosque server returned an error. Tap Retry.';
        } else if (msgLower.contains('all overpass')) {
          errorText = 'All mosque servers failed to respond. Check internet & tap Retry.';
        } else if (msgLower.contains('socket') || msgLower.contains('network') ||
            msgLower.contains('connection') || msgLower.contains('certificate') ||
            msgLower.contains('handshake')) {
          errorText = 'Network error reaching mosque server. Check internet & tap Retry.';
        } else {
          errorText = 'Could not load mosques. Tap Retry.\n(${msg.length > 80 ? msg.substring(0, 80) : msg})';
        }
        setState(() {
          _isLoading = false;
          _error = errorText;
        });
      }
    }
  }

  /// Tries each endpoint with three strategies in order:
  /// 1. GET  (simple, no encoding issues)
  /// 2. POST form-encoded  (avoids URL length limits)
  /// 3. POST raw body  (some mirrors prefer this format)
  static Future<http.Response> _tryOverpassEndpoints(
      List<String> endpoints, String query) async {
    final failures = <String>[];

    for (final base in endpoints) {
      // --- Strategy 1: GET ---
      try {
        final uri = Uri.parse(base).replace(queryParameters: {'data': query});
        final resp = await http
            .get(uri, headers: {
              'Accept': 'application/json',
              'User-Agent': 'MySalahApp/1.0 Flutter',
            })
            .timeout(const Duration(seconds: 25));
        if (resp.statusCode == 200) return resp;
        failures.add('GET $base → ${resp.statusCode}');
      } catch (e) {
        failures.add('GET $base → ${e.runtimeType}');
      }

      // --- Strategy 2: POST form-encoded ---
      try {
        final resp = await http
            .post(
              Uri.parse(base),
              headers: {
                'Content-Type': 'application/x-www-form-urlencoded',
                'Accept': 'application/json',
                'User-Agent': 'MySalahApp/1.0 Flutter',
              },
              body: 'data=${Uri.encodeQueryComponent(query)}',
            )
            .timeout(const Duration(seconds: 25));
        if (resp.statusCode == 200) return resp;
        failures.add('POST-form $base → ${resp.statusCode}');
      } catch (e) {
        failures.add('POST-form $base → ${e.runtimeType}');
      }

      // --- Strategy 3: POST raw body ---
      try {
        final resp = await http
            .post(
              Uri.parse(base),
              headers: {
                'Content-Type': 'text/plain; charset=utf-8',
                'Accept': 'application/json',
                'User-Agent': 'MySalahApp/1.0 Flutter',
              },
              body: query,
            )
            .timeout(const Duration(seconds: 25));
        if (resp.statusCode == 200) return resp;
        failures.add('POST-raw $base → ${resp.statusCode}');
      } catch (e) {
        failures.add('POST-raw $base → ${e.runtimeType}');
      }
    }

    throw Exception('All Overpass endpoints failed:\n${failures.join("\n")}');
  }

  String _buildAddress(Map<String, dynamic> tags) {
    final parts = <String>[];
    if (tags['addr:housenumber'] != null) parts.add(tags['addr:housenumber'] as String);
    if (tags['addr:street'] != null) parts.add(tags['addr:street'] as String);
    if (tags['addr:city'] != null) parts.add(tags['addr:city'] as String);
    if (parts.isEmpty && tags['addr:full'] != null) return tags['addr:full'] as String;
    return parts.isEmpty ? 'Address not available' : parts.join(', ');
  }

  List<_MosqueInfo> get _filteredMosques {
    return _mosques.where((m) {
      if (_filterWomens && !m.hasWomensSection) return false;
      if (_filterJumua && !m.hasJumua) return false;
      final q = _searchController.text.toLowerCase();
      if (q.isNotEmpty &&
          !m.name.toLowerCase().contains(q) &&
          !m.address.toLowerCase().contains(q)) {
        return false;
      }
      return true;
    }).toList();
  }

  /// Fetch walking route from OSRM (free, no API key)
  Future<void> _fetchRoute(LatLng from, LatLng to) async {
    setState(() {
      _isLoadingRoute = true;
      _routePoints = [];
    });
    try {
      final url = Uri.parse(
        'https://router.project-osrm.org/route/v1/foot/'
        '${from.longitude},${from.latitude};'
        '${to.longitude},${to.latitude}'
        '?overview=full&geometries=geojson',
      );
      final resp = await http.get(url).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body) as Map<String, dynamic>;
        final routes = data['routes'] as List?;
        if (routes != null && routes.isNotEmpty) {
          final coords = routes[0]['geometry']['coordinates'] as List;
          setState(() {
            _routePoints = coords
                .map((c) => LatLng((c[1] as num).toDouble(),
                    (c[0] as num).toDouble()))
                .toList();
          });
        }
      }
    } catch (_) {
      // Network unavailable — silently ignore, no route shown
    } finally {
      setState(() => _isLoadingRoute = false);
    }
  }

  void _selectMosque(_MosqueInfo mosque, LatLng userPos) {
    setState(() {
      _selectedMosque = mosque;
      _routePoints = [];
    });
    _mapController.move(mosque.position, 15);
    _fetchRoute(userPos, mosque.position);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // context.select — map only rebuilds when location changes, NOT every 1-second tick
    final lat = context.select<PrayerProvider, double>((p) => p.latitude);
    final lon = context.select<PrayerProvider, double>((p) => p.longitude);
    final center = LatLng(lat, lon);
    final filtered = _filteredMosques;

    return Scaffold(
      backgroundColor: AppColors.darkBg,
      body: Stack(
        children: [
          // ── OpenStreetMap (100% Free) ──
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: center,
              initialZoom: 14.0,
              onTap: (_, __) => setState(() {
                _selectedMosque = null;
                _routePoints = [];
              }),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.mysalah.my_salah_app',
              ),
              // ── Shortest path polyline ──
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: AppColors.gold,
                      strokeWidth: 4.5,
                    ),
                  ],
                ),
              // ── Markers ──
              MarkerLayer(
                markers: [
                  // My location marker
                  Marker(
                    point: center,
                    width: 40,
                    height: 40,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.gold.withValues(alpha: 0.5),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: const Icon(Icons.person_pin_rounded,
                          color: Colors.white, size: 22),
                    ),
                  ),
                  // Mosque markers (only when not loading)
                  if (!_isLoading)
                    ...filtered.map((mosque) => Marker(
                          point: mosque.position,
                          width: 42,
                          height: 42,
                          child: GestureDetector(
                            onTap: () => _selectMosque(mosque, center),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              decoration: BoxDecoration(
                                color: _selectedMosque?.id == mosque.id
                                    ? AppColors.gold
                                    : AppColors.darkCard,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AppColors.gold,
                                  width:
                                      _selectedMosque?.id == mosque.id ? 3 : 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.gold.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.mosque_rounded,
                                color: _selectedMosque?.id == mosque.id
                                    ? Colors.white
                                    : AppColors.gold,
                                size: 22,
                              ),
                            ),
                          ),
                        )),
                ],
              ),
            ],
          ),

          // ── Loading overlay ──
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.4),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.gold),
                      SizedBox(height: 16),
                      Text(
                        'Finding nearby mosques...',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // ── Error overlay ──
          if (_error != null && !_isLoading)
            Positioned(
              bottom: 220,
              left: 24,
              right: 24,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.darkCard,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.wifi_off_rounded,
                        color: Colors.redAccent, size: 28),
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _fetchRealMosques,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 10),
                        decoration: BoxDecoration(
                          color: AppColors.gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: AppColors.gold.withValues(alpha: 0.6)),
                        ),
                        child: const Text('Retry',
                            style: TextStyle(
                                color: AppColors.gold,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Route loading indicator ──
          if (_isLoadingRoute)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                color: AppColors.gold,
                backgroundColor: AppColors.gold.withValues(alpha: 0.2),
                minHeight: 3,
              ),
            ),

          // ── Top UI Overlay ──
          SafeArea(
            child: Column(
              children: [

                // Search Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.darkCard.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppColors.darkBorder),
                    ),
                    child: Row(
                      children: [
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 14),
                          child: Icon(Icons.search_rounded,
                              color: AppColors.textSecondary, size: 22),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            onChanged: (_) => setState(() {}),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w400),
                            cursorColor: AppColors.gold,
                            decoration: InputDecoration(
                              hintText: 'Search mosques nearby...',
                              hintStyle: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.45)),
                              border: InputBorder.none,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.close_rounded,
                                color: AppColors.textSecondary, size: 20),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Filter chips + GPS button on same row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      _MapButton(
                        icon: Icons.my_location_rounded,
                        onTap: () {
                          _mapController.move(center, 14);
                        },
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: "Women's Section",
                        active: _filterWomens,
                        onTap: () =>
                            setState(() => _filterWomens = !_filterWomens),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: "Jumu'a",
                        active: _filterJumua,
                        onTap: () =>
                            setState(() => _filterJumua = !_filterJumua),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Bottom mosque list
                Container(
                  height: 200,
                  margin: const EdgeInsets.all(12),
                  child: filtered.isEmpty
                      ? const Center(
                          child: Text('No mosques found',
                              style: TextStyle(color: AppColors.textSecondary)),
                        )
                      : ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (context, i) => _MosqueCard(
                            mosque: filtered[i],
                            isSelected:
                                _selectedMosque?.id == filtered[i].id,
                            onTap: () =>
                                _selectMosque(filtered[i], center),
                          ),
                        ),
                ),
              ],
            ),
          ),

          // Selected mosque detail panel
          if (_selectedMosque != null)
            Positioned(
              bottom: 228,
              left: 16,
              right: 16,
              child: _MosqueDetailPanel(
                mosque: _selectedMosque!,
                hasRoute: _routePoints.isNotEmpty,
                isLoadingRoute: _isLoadingRoute,
                onClose: () => setState(() {
                  _selectedMosque = null;
                  _routePoints = [];
                }),
                onGetDirections: () =>
                    _fetchRoute(center, _selectedMosque!.position),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Widget: Map Button ──────────────────────────────────
class _MapButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _MapButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.darkCard.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: Icon(icon, color: AppColors.gold, size: 22),
      ),
    );
  }
}

// ── Widget: Filter Chip ─────────────────────────────────
class _FilterChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active
              ? AppColors.gold.withValues(alpha: 0.2)
              : AppColors.darkCard.withValues(alpha: 0.9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? AppColors.gold : AppColors.darkBorder,
            width: active ? 1.5 : 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? AppColors.gold : AppColors.textSecondary,
            fontSize: 12,
            fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

// ── Widget: Mosque Card (horizontal list) ───────────────
class _MosqueCard extends StatelessWidget {
  final _MosqueInfo mosque;
  final bool isSelected;
  final VoidCallback onTap;
  const _MosqueCard(
      {required this.mosque, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 220,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.gold.withValues(alpha: 0.15)
              : AppColors.darkCard.withValues(alpha: 0.95),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.gold : AppColors.darkBorder,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.gold.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.mosque_rounded,
                      color: AppColors.gold, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    mosque.name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              mosque.address,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.directions_walk_rounded,
                    color: AppColors.textSecondary, size: 14),
                const SizedBox(width: 4),
                Text(mosque.distance,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(width: 10),
                const Icon(Icons.access_time_rounded,
                    color: AppColors.textSecondary, size: 14),
                const SizedBox(width: 4),
                Text(mosque.walkTime,
                    style: const TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                if (mosque.hasJumua)
                  const _Tag(label: "Jumu'a", color: AppColors.gold),
                if (mosque.hasJumua && mosque.hasWomensSection)
                  const SizedBox(width: 6),
                if (mosque.hasWomensSection)
                  const _Tag(label: 'Women ✓', color: AppColors.onTimeLight),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widget: Tag ─────────────────────────────────────────
class _Tag extends StatelessWidget {
  final String label;
  final Color color;
  const _Tag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

// ── Widget: Selected Mosque Detail Panel ─────────────────
class _MosqueDetailPanel extends StatelessWidget {
  final _MosqueInfo mosque;
  final bool hasRoute;
  final bool isLoadingRoute;
  final VoidCallback onClose;
  final VoidCallback onGetDirections;

  const _MosqueDetailPanel({
    required this.mosque,
    required this.hasRoute,
    required this.isLoadingRoute,
    required this.onClose,
    required this.onGetDirections,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.darkCard.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mosque_rounded, color: AppColors.gold, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  mosque.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    color: AppColors.textSecondary, size: 20),
                onPressed: onClose,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(mosque.address,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(height: 10),
          Row(
            children: [
              _InfoPill(
                  icon: Icons.directions_walk_rounded,
                  label: '${mosque.distance} · ${mosque.walkTime}'),
              const SizedBox(width: 8),
              if (mosque.hasJumua)
                const _Tag(label: "Jumu'a", color: AppColors.gold),
              const SizedBox(width: 6),
              if (mosque.hasWomensSection)
                const _Tag(label: "Women ✓", color: AppColors.onTimeLight),
            ],
          ),
          const SizedBox(height: 12),
          // ── Get Directions / Route status button ──
          GestureDetector(
            onTap: isLoadingRoute ? null : onGetDirections,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 11),
              decoration: BoxDecoration(
                color: hasRoute
                    ? AppColors.gold.withValues(alpha: 0.2)
                    : AppColors.gold.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (isLoadingRoute)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.gold),
                    )
                  else
                    Icon(
                      hasRoute
                          ? Icons.route_rounded
                          : Icons.directions_rounded,
                      color: AppColors.gold,
                      size: 18,
                    ),
                  const SizedBox(width: 8),
                  Text(
                    isLoadingRoute
                        ? 'Finding route...'
                        : hasRoute
                            ? 'Route on map ✓'
                            : 'Get Directions',
                    style: const TextStyle(
                      color: AppColors.gold,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textSecondary, size: 14),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                color: AppColors.textSecondary, fontSize: 12)),
      ],
    );
  }
}

class _MosqueInfo {
  final String id;
  final String name;
  final String address;
  final String distance;
  final String walkTime;
  final bool hasWomensSection;
  final bool hasJumua;
  final LatLng position;
  final double distanceMeters;

  _MosqueInfo({
    required this.id,
    required this.name,
    required this.address,
    required this.distance,
    required this.walkTime,
    required this.hasWomensSection,
    required this.hasJumua,
    required this.position,
    this.distanceMeters = 0,
  });
}
