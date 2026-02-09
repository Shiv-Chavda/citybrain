import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class GeoJsonOverlay extends StatelessWidget {
  final Map<String, dynamic> geojson;

  const GeoJsonOverlay({super.key, required this.geojson});

  @override
  Widget build(BuildContext context) {
    if (geojson["type"] != "FeatureCollection") {
      return const SizedBox.shrink();
    }

    final features = geojson["features"];
    if (features == null || features is! List) {
      return const SizedBox.shrink();
    }

    final List<Polygon> polygons = [];

    for (final feature in features) {
      final geometry = feature["geometry"];
      final properties = feature["properties"] ?? {};

      if (geometry == null) continue;

      final String geomType = geometry["type"];
      final coords = geometry["coordinates"];
      final String bufferType = properties["buffer_type"] ?? "DEFAULT";

      if (coords == null) continue;

      if (geomType == "Polygon") {
        polygons.add(_buildPolygon(coords, bufferType));
      }

      if (geomType == "MultiPolygon") {
        for (final poly in coords) {
          polygons.add(_buildPolygon(poly, bufferType));
        }
      }
    }

    return PolygonLayer(polygons: polygons);
  }

  // 🎨 Buffer zone coloring
  Color bufferColor(String type) {
    switch (type) {
      case "CRITICAL":
        return Colors.red.withOpacity(0.45);
      case "WARNING":
        return Colors.orange.withOpacity(0.35);
      case "CAUTION":
        return Colors.yellow.withOpacity(0.25);
      default:
        return Colors.blue.withOpacity(0.2);
    }
  }

  Polygon _buildPolygon(List<dynamic> rings, String bufferType) {
    if (rings.isEmpty || rings[0] == null) {
      return Polygon(points: []);
    }

    final outerRing = rings[0];

    final List<LatLng> points = outerRing.map<LatLng>((c) {
      final lng = (c[0] as num).toDouble();
      final lat = (c[1] as num).toDouble();
      return LatLng(lat, lng);
    }).toList();

    final color = bufferColor(bufferType);

    return Polygon(
      points: points,
      color: color,
      borderColor: color.withOpacity(0.9),
      borderStrokeWidth: 1.2,
    );
  }
}
