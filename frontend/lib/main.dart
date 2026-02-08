import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:frontend/services/map_api.dart';
import 'package:frontend/widgets/map_overlay.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const CityBrainApp());
}

class CityBrainApp extends StatefulWidget {
  const CityBrainApp({super.key});

  @override
  State<CityBrainApp> createState() => _CityBrainAppState();
}

class _CityBrainAppState extends State<CityBrainApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const InitializationPage(),
    );
  }
}

class InitializationPage extends StatefulWidget {
  const InitializationPage({super.key});

  @override
  State<InitializationPage> createState() => _InitializationPageState();
}

class _InitializationPageState extends State<InitializationPage>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  String _statusMessage = "Initializing CityBrain...";
  bool _hasError = false;
  String _errorMessage = "";
  double _progress = 0.0;
  List<dynamic> _constructionProjects = [];
  

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );

    _animationController.forward();
    _initializeApp();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  

  Future<void> _initializeApp() async {
    try {
      // Step 1: Check backend connectivity
      await _updateProgress(0.2, "Checking backend connectivity...");
      await _checkBackendConnectivity();

      // Step 2: Load construction projects
      await _updateProgress(0.5, "Loading construction projects...");
      await _loadConstructionProjects();

      // Step 3: Verify AI engine
      await _updateProgress(0.8, "Verifying AI engine...");
      await _checkAIEngine();

      // Step 4: Initialization complete
      await _updateProgress(1.0, "Initialization complete!");
      await Future.delayed(const Duration(milliseconds: 500));

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => CityMapPage(
              preloadedConstructionProjects: _constructionProjects,
            ),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _hasError = true;
        _errorMessage = e.toString();
        _statusMessage = "Initialization failed";
      });
    }
  }

  Future<void> _updateProgress(double progress, String message) async {
    setState(() {
      _progress = progress;
      _statusMessage = message;
    });
    await Future.delayed(const Duration(milliseconds: 300));
  }

  Future<void> _checkBackendConnectivity() async {
    try {
      final response = await http
          .get(Uri.parse("http://localhost:4000/api/health"))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception("Gateway service not responding");
      }
    } catch (e) {
      try {
        // Fallback check - try to connect to any known endpoint
        await http
            .get(Uri.parse("http://localhost:4000/api/construction/geometry"))
            .timeout(const Duration(seconds: 5));
      } catch (e2) {
        throw Exception("Cannot connect to backend services on localhost:4000");
      }
    }
  }

  Future<void> _loadConstructionProjects() async {
    try {
      final response = await http
          .get(Uri.parse("http://localhost:4000/api/construction/geometry"))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception("Failed to load construction projects");
      }

      _constructionProjects = json.decode(response.body);
    } catch (e) {
      throw Exception("Error loading construction data: ${e.toString()}");
    }
  }

  Future<void> _checkAIEngine() async {
    try {
      final response = await http
          .get(Uri.parse("http://localhost:8001/api/health"))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) {
        throw Exception("AI Engine not responding");
      }
    } catch (e) {
      // AI Engine check failed, but we can still continue
      print("Warning: AI Engine may not be available: $e");
    }
  }

  void _retryInitialization() {
    setState(() {
      _hasError = false;
      _errorMessage = "";
      _progress = 0.0;
      _statusMessage = "Retrying initialization...";
    });
    _initializeApp();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo/Title
              const Icon(Icons.location_city, size: 80, color: Colors.blue),
              const SizedBox(height: 24),
              const Text(
                "CityBrain",
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                "Smart City Infrastructure Management",
                style: TextStyle(fontSize: 16, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 60),

              // Progress indicator
              if (!_hasError) ...[
                SizedBox(
                  width: 300,
                  child: Column(
                    children: [
                      LinearProgressIndicator(
                        value: _progress,
                        backgroundColor: Colors.grey[800],
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _statusMessage,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.white70,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "${(_progress * 100).toInt()}%",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Error state
              if (_hasError) ...[
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  _statusMessage,
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.withOpacity(0.3)),
                  ),
                  child: Text(
                    _errorMessage,
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _retryInitialization,
                  icon: const Icon(Icons.refresh),
                  label: const Text("Retry"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CityMapPage extends StatefulWidget {
  final List<dynamic>? preloadedConstructionProjects;

  const CityMapPage({super.key, this.preloadedConstructionProjects});

  @override
  State<CityMapPage> createState() => _CityMapPageState();
}

class _CityMapPageState extends State<CityMapPage> {
  List<dynamic> impactSubgraph = [];
  int currentHop = 0;
  bool animating = false;
  String status = "Click any road to simulate failure propagation";
  List<dynamic> zoneImpacts = [];
  bool showZones = true;
  List<dynamic> hospitalImpacts = [];
  bool showHospitals = true;
  List<dynamic> topHospitals = [];
  Map<int, List<LatLng>> rerouteGeometries = {};
  int? selectedHospitalRoad; // reroute road id
  List<dynamic> constructionProjects = [];
  bool showConstruction = true;
  List<dynamic> junctions = [];
  bool showJunctions = true;
  Map<String, dynamic>? highlightData;

  @override
  void initState() {
    super.initState();
      loadHighlight();
    // Use preloaded construction projects if available
    if (widget.preloadedConstructionProjects != null) {
      constructionProjects = widget.preloadedConstructionProjects!;
    } else {
      // Fallback: fetch construction projects if not preloaded
      fetchConstructionProjects();
      fetchJunctions();
    }
  }

  void loadHighlight() async {
  final data = await MapApi.fetchHighlight("hospital");
  setState(() {
    highlightData = data;
  });
}

  Color constructionColor(double risk) {
    if (risk > 0.8) return Colors.red.withOpacity(0.6);
    if (risk > 0.6) return Colors.orange.withOpacity(0.6);
    return Colors.yellow.withOpacity(0.6);
  }

  Color junctionColor() => Colors.lightBlueAccent;

  Color hopColor(int hop) {
    switch (hop) {
      case 0:
        return Colors.red;
      case 1:
        return Colors.orange;
      case 2:
        return Colors.yellow;
      case 3:
        return Colors.green;
      default:
        return Colors.blueGrey;
    }
  }

  Future<void> fetchJunctions() async {
    final res = await http.get(
      Uri.parse("http://localhost:4000/api/junctions"),
    );

    setState(() {
      junctions = json.decode(res.body);
    });
  }

  Future<void> fetchConstructionProjects() async {
    final res = await http.get(
      Uri.parse("http://localhost:4000/api/construction/geometry"),
    );

    setState(() {
      constructionProjects = json.decode(res.body);
    });
  }

  Future<void> fetchRerouteRoad(int roadId) async {
    if (rerouteGeometries.containsKey(roadId)) return;

    final res = await http.get(
      Uri.parse('http://localhost:4000/api/roads/$roadId/geometry'),
    );
    final data = json.decode(res.body);

    final coords = data["geometry"];
    if (coords == null) return;

    final points = coords.map<LatLng>((c) => LatLng(c[1], c[0])).toList();

    setState(() {
      rerouteGeometries[roadId] = points;
      selectedHospitalRoad = roadId;
    });
  }

  Future<void> fetchNearestRoad(LatLng point) async {
    final res = await http.get(
      Uri.parse(
        'http://localhost:4000/api/nearest-road?lat=${point.latitude}&lng=${point.longitude}',
      ),
    );
    final data = json.decode(res.body);
    final roadId = data['road_id'].toString();
    await fetchImpact(roadId);
  }

  Future<void> fetchImpact(String roadId) async {
    setState(() {
      animating = true;
      currentHop = 0;
      impactSubgraph = [];
      status = "Computing impact for Road $roadId ...";
    });

    final res = await http.get(
      Uri.parse('http://localhost:8001/api/impact/semantic/$roadId?hops=3'),
    );
    final data = json.decode(res.body);

    impactSubgraph = data['subgraph'] ?? [];

    // Fetch zone-level impact
    final zoneRes = await http.get(
      Uri.parse('http://localhost:4000/api/impact/zones/$roadId?hops=3'),
    );
    final zoneData = json.decode(zoneRes.body);

    zoneImpacts = zoneData['zones'] ?? [];

    final hosRes = await http.get(
      Uri.parse('http://localhost:4000/api/impact/hospitals/$roadId?hops=3'),
    );
    final hosData = json.decode(hosRes.body);

    hospitalImpacts = hosData['affected_hospitals'] ?? [];

    final summaryRes = await http.get(
      Uri.parse('http://localhost:4000/api/impact/summary/$roadId?hops=3'),
    );
    final summaryData = json.decode(summaryRes.body);

    topHospitals = summaryData['top_hospitals'] ?? [];

    final conRes = await http.get(
      Uri.parse('http://localhost:4000/api/impact/construction/$roadId'),
    );
    final conData = json.decode(conRes.body);

    if (conData["projects"] != null && conData["projects"].length > 0) {
      setState(() {
        status +=
            "\n⚠ Construction impact detected (${conData["projects"].length} projects)";
      });
    }

    for (int i = 0; i <= 3; i++) {
      await Future.delayed(const Duration(milliseconds: 700));
      setState(() {
        currentHop = i;
      });
    }

    setState(() {
      status = "Propagation complete for Road $roadId";
      animating = false;
    });
  }

  List<Polyline> buildConstructionOverlays() {
    if (!showConstruction) return [];

    return constructionProjects.map<Polyline>((c) {
      final geom = json.decode(c["geometry"]);
      final coords = geom["coordinates"];

      double toDouble(dynamic value) {
        if (value is double) return value;
        if (value is int) return value.toDouble();
        if (value is String) return double.tryParse(value) ?? 0.0;
        return 0.0;
      }

      List<LatLng> points = coords.map<LatLng>((p) {
        return LatLng(toDouble(p[1]), toDouble(p[0]));
      }).toList();

      return Polyline(
        points: points,
        strokeWidth: 6,
        color: constructionColor(toDouble(c["risk_factor"])),
      );
    }).toList();
  }

  // List<Marker> buildJunctionMarkers() {
  //   if (!showJunctions) re// turn [];

  //   return junctions.map<Marker>((j) {
  //     return Marker(
  //       width: 14,
  //       height: 14,
  //       point: LatLng(j["lat"], j["lon"]),
  //       child: Container(
  //         decoration: BoxDecoration(
  //           shape: BoxShape.circle,
  //           color: junctionColor(),
  //           border: Border.all(color: Colors.black, width: 0.5),
  //         ),
  //       ),
  //     );
  //   }).toList();
  // }

  List<Polyline> buildPropagationLines() {
    List<dynamic> roads = impactSubgraph
        .where((n) => n["type"] == "Road" && n["hop"] <= currentHop)
        .toList();

    // Draw higher hops first so lower hops (red) stay on top
    roads.sort((a, b) => b["hop"].compareTo(a["hop"]));

    return roads.map<Polyline>((node) {
      int hop = node["hop"];
      List coords = node["geometry"];
      double toDouble(dynamic v) {
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v) ?? 0.0;
        if (v is List && v.isNotEmpty && v[0] is num)
          return (v[0] as num).toDouble();
        return 0.0;
      }

      List<LatLng> points = coords.map<LatLng>((c) {
        final lng = toDouble((c is List && c.length > 0) ? c[0] : c);
        final lat = toDouble((c is List && c.length > 1) ? c[1] : c);
        return LatLng(lat, lng);
      }).toList();

      return Polyline(
        points: points,
        strokeWidth: hop == 0 ? 5 : 3,
        color: hopColor(hop),
      );
    }).toList();
  }

  Color zoneColor(double severity) {
    if (severity > 0.6) return Colors.red.withOpacity(0.45);
    if (severity > 0.4) return Colors.orange.withOpacity(0.45);
    if (severity > 0.2) return Colors.yellow.withOpacity(0.45);
    return Colors.green.withOpacity(0.45);
  }

  Color hospitalColor(String risk) {
    switch (risk) {
      case "CRITICAL":
        return Colors.red;
      case "HIGH":
        return Colors.orange;
      case "MEDIUM":
        return Colors.yellow;
      default:
        return Colors.green;
    }
  }

  List<LatLng> parseZoneGeometry(List geometry) {
    // Locate the first array that looks like a ring of coordinate pairs
    List? findRing(dynamic node) {
      if (node is List) {
        if (node.isNotEmpty && node[0] is List) {
          final first = node[0];
          if (first is List &&
              first.isNotEmpty &&
              (first[0] is num || first[0] is String)) {
            return node;
          }
        }
        for (var child in node) {
          final res = findRing(child);
          if (res != null) return res;
        }
      }
      return null;
    }

    double toDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      if (v is List && v.isNotEmpty && v[0] is num)
        return (v[0] as num).toDouble();
      return 0.0;
    }

    final ring = findRing(geometry) ?? [];
    return ring.map<LatLng>((c) {
      final lng = toDouble((c is List && c.length > 0) ? c[0] : c);
      final lat = toDouble((c is List && c.length > 1) ? c[1] : c);
      return LatLng(lat, lng);
    }).toList();
  }

  List<Polygon> buildZonePolygons() {
    if (!showZones) return [];

    return zoneImpacts.map<Polygon>((z) {
      final points = parseZoneGeometry(z["geometry"]);

      return Polygon(
        points: points,
        color: zoneColor((z["severity"] as num).toDouble()),
        borderColor: Colors.black26,
        borderStrokeWidth: 0.8,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("CityBrain – Failure Propagation")),
      body: Row(
        children: [
          Expanded(
            flex: 4,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: LatLng(23.0225, 72.5714),
                initialZoom: 12,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
                onTap: (tapPos, latlng) {
                  if (!animating) {
                    fetchNearestRoad(latlng);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                ),
                if (highlightData != null)
                  GeoJsonOverlay(geojson: highlightData!),

                PolygonLayer(polygons: buildZonePolygons()),
                PolylineLayer(polylines: buildConstructionOverlays()),
                PolylineLayer(polylines: buildPropagationLines()),
                MarkerLayer(
                  markers: showHospitals
                      ? hospitalImpacts.map<Marker>((h) {
                          return Marker(
                            width: 30,
                            height: 30,
                            point: LatLng(h["location"][0], h["location"][1]),
                            child: Tooltip(
                              message:
                                  "${h["name"]}\n"
                                  "Risk: ${h["risk"]} (Hop ${h["hop"]})\n"
                                  "Why: ${h["reason"]}\n"
                                  "${h["reroute"] != null ? "Reroute: Road ${h["reroute"]["suggested_road_id"]}" : ""}",
                              child: Icon(
                                Icons.local_hospital,
                                color: hospitalColor(h["risk"]),
                                size: 26,
                              ),
                            ),
                          );
                        }).toList()
                      : [],
                ),

                // MarkerLayer(markers: buildJunctionMarkers()),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.black87,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Impact Simulation",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Show Zone Heatmap"),
                        Switch(
                          value: showZones,
                          onChanged: (v) {
                            setState(() {
                              showZones = v;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Show Construction"),
                        Switch(
                          value: showConstruction,
                          onChanged: (v) {
                            setState(() {
                              showConstruction = v;
                            });
                          },
                        ),
                      ],
                    ),
                    // const SizedBox(height: 10),
                    // const Divider(),
                    // Row(
                    //   mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    //   children: [
                    //     const Text("Show Junctions"),
                    //     Switch(
                    //       value: showJunctions,
                    //       onChanged: (v) {
                    //         setState(() {
                    //           showJunctions = v;
                    //         });
                    //       },
                    //     ),
                    //   ],
                    // ),
                    const SizedBox(height: 10),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Show Hospitals"),
                        Switch(
                          value: showHospitals,
                          onChanged: (v) {
                            setState(() {
                              showHospitals = v;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(status, style: const TextStyle(color: Colors.orange)),
                    const SizedBox(height: 10),
                    const Divider(),
                    const Text("Legend:"),
                    const SizedBox(height: 6),
                    Row(
                      children: const [
                        Icon(Icons.remove, color: Colors.red),
                        SizedBox(width: 6),
                        Text("Hop 0 – Failure Origin"),
                      ],
                    ),
                    Row(
                      children: const [
                        Icon(Icons.remove, color: Colors.orange),
                        SizedBox(width: 6),
                        Text("Hop 1 – Directly Affected"),
                      ],
                    ),
                    Row(
                      children: const [
                        Icon(Icons.remove, color: Colors.yellow),
                        SizedBox(width: 6),
                        Text("Hop 2 – Secondary Spread"),
                      ],
                    ),
                    Row(
                      children: const [
                        Icon(Icons.remove, color: Colors.green),
                        SizedBox(width: 6),
                        Text("Hop 3 – Tertiary Spread"),
                      ],
                    ),
                    const Divider(),
                    Text("Visible Hops: $currentHop / 3"),
                    const Divider(),
                    const Text("Zone Severity"),
                    const SizedBox(height: 6),
                    Row(
                      children: const [
                        Icon(Icons.square, color: Colors.red),
                        SizedBox(width: 6),
                        Text("> 60% affected"),
                      ],
                    ),
                    Row(
                      children: const [
                        Icon(Icons.square, color: Colors.orange),
                        SizedBox(width: 6),
                        Text("40–60% affected"),
                      ],
                    ),
                    Row(
                      children: const [
                        Icon(Icons.square, color: Colors.yellow),
                        SizedBox(width: 6),
                        Text("20–40% affected"),
                      ],
                    ),
                    Row(
                      children: const [
                        Icon(Icons.square, color: Colors.green),
                        SizedBox(width: 6),
                        Text("< 20% affected"),
                      ],
                    ),
                    const Divider(),
                    const Text(
                      "Construction Risk",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),

                    Row(
                      children: const [
                        Icon(Icons.remove, color: Colors.red),
                        SizedBox(width: 6),
                        Text("High Risk Construction"),
                      ],
                    ),
                    Row(
                      children: const [
                        Icon(Icons.remove, color: Colors.orange),
                        SizedBox(width: 6),
                        Text("Medium Risk Construction"),
                      ],
                    ),
                    Row(
                      children: const [
                        Icon(Icons.remove, color: Colors.yellow),
                        SizedBox(width: 6),
                        Text("Low Risk Construction"),
                      ],
                    ),
                    const Divider(),
                    const Text(
                      "Affected Hospitals",
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    ...hospitalImpacts.map(
                      (h) => Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: hospitalColor(h["risk"]).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "🏥 ${h["name"]}",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: hospitalColor(h["risk"]),
                              ),
                            ),
                            Text("Risk: ${h["risk"]} (Hop ${h["hop"]})"),
                            Text(
                              "Why: ${h["reason"]}",
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white70,
                              ),
                            ),
                            if (h["reroute"] != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  "🔁 Reroute via Road ${h["reroute"]["suggested_road_id"]}",
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.lightBlueAccent,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    const Divider(),
                    const Text(
                      "🚨 Priority Response (Top 5 Facilities)",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),

                    ...topHospitals.map(
                      (h) => Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.redAccent),
                        ),
                        child: Text(
                          "🏥 ${h["name"]}\n"
                          "Hop: ${h["hop"]} | Priority Score: ${h["priority_score"]}\n"
                          "Why: ${h["explanation"]}",
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
