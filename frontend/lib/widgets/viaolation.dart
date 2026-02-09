import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class ViolationOverlay extends StatelessWidget {
  final Map<String, dynamic> geojson;

  const ViolationOverlay({super.key, required this.geojson});

  @override
  Widget build(BuildContext context) {
    if (geojson["type"] != "FeatureCollection") {
      return const SizedBox.shrink();
    }

    final features = geojson["features"] as List<dynamic>;

    final List<Polyline> lines = [];

    for (final feature in features) {
      final geometry = feature["geometry"];
      final props = feature["properties"] ?? {};

      if (geometry == null) continue;

      final String type = geometry["type"];
      final coords = geometry["coordinates"];
      final String severity = props["severity"] ?? "UNKNOWN";

      if (type == "LineString") {
        lines.add(_buildLine(coords, severity));
      }
    }

    return PolylineLayer(polylines: lines);
  }

  Color severityColor(String severity) {
    switch (severity) {
      case "CRITICAL":
        return Colors.red;
      case "WARNING":
        return Colors.orange;
      case "CAUTION":
        return Colors.yellow;
      default:
        return Colors.blueGrey;
    }
  }

  Polyline _buildLine(List<dynamic> coords, String severity) {
    final points = coords.map<LatLng>((c) {
      final lng = (c[0] as num).toDouble();
      final lat = (c[1] as num).toDouble();
      return LatLng(lat, lng);
    }).toList();

    return Polyline(
      points: points,
      strokeWidth: 6,
      color: severityColor(severity),
    );
  }
}
