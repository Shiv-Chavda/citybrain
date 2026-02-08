import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class GeoJsonOverlay extends StatelessWidget {
  final Map<String, dynamic> geojson;

  const GeoJsonOverlay({required this.geojson});

  @override
  Widget build(BuildContext context) {
    final features = geojson['features'] as List;

    return PolygonLayer(
      polygons: features.map((f) {
        final coords = f['geometry']['coordinates'][0] as List;
        return Polygon(
          points: coords
              .map<LatLng>((c) => LatLng(c[1], c[0]))
              .toList(),
          color: Colors.red.withOpacity(0.3),
          borderColor: Colors.red,
          borderStrokeWidth: 2,
        );
      }).toList(),
    );
  }
}
