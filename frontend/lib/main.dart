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
      title: 'CityBrain – Digital Twin',
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
  List<dynamic> features = [];

  @override
  void initState() {
    super.initState();
    loadRoads();
  }

  Future<void> loadRoads() async {
    final response = await http.get(Uri.parse('http://localhost:4000/api/roads'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        features = data['features'];
      });
    }
  }

  List<Polyline> buildRoadPolylines() {
    return features.map((f) {
      final coords = f['geometry']['coordinates'];
      final points = coords.map<LatLng>((c) => LatLng(c[1], c[0])).toList();
      return Polyline(
        points: points,
        color: Colors.orange,
        strokeWidth: 1.5,
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("CityBrain – Ahmedabad Digital Twin")),
      body: FlutterMap(
        options: MapOptions(
          center: LatLng(23.0225, 72.5714), // Ahmedabad
          zoom: 12,
        ),
        children: [
          TileLayer(
            urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
            userAgentPackageName: 'com.citybrain.app',
          ),
          PolylineLayer(polylines: buildRoadPolylines()),
        ],
      ),
    );
  }
}
