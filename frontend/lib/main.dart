import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;

void main() {
  runApp(const CityBrainApp());
}

class CityBrainApp extends StatelessWidget {
  const CityBrainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const CityMapPage(),
    );
  }
}

class CityMapPage extends StatefulWidget {
  const CityMapPage({super.key});

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
      Uri.parse('http://localhost:8001/api/impact/semantic/$roadId?hops=6'),
    );
    final data = json.decode(res.body);

    impactSubgraph = data['subgraph'] ?? [];

    // Fetch zone-level impact
    final zoneRes = await http.get(
      Uri.parse('http://localhost:4000/api/impact/zones/$roadId?hops=6'),
    );
    final zoneData = json.decode(zoneRes.body);

    zoneImpacts = zoneData['zones'] ?? [];

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
          if (v is List && v.isNotEmpty && v[0] is num) return (v[0] as num).toDouble();
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

  List<LatLng> parseZoneGeometry(List geometry) {
    // Locate the first array that looks like a ring of coordinate pairs
    List? findRing(dynamic node) {
      if (node is List) {
        if (node.isNotEmpty && node[0] is List) {
          final first = node[0];
          if (first is List && first.isNotEmpty && (first[0] is num || first[0] is String)) {
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
      if (v is List && v.isNotEmpty && v[0] is num) return (v[0] as num).toDouble();
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
                PolygonLayer(polygons: buildZonePolygons()),

                PolylineLayer(polylines: buildPropagationLines()),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(12),
              color: Colors.black87,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Impact Simulation",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
