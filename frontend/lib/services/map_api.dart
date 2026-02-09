import 'dart:convert';
import 'package:http/http.dart' as http;

class MapApi {
  static Future<Map<String, dynamic>?> fetchHighlight(String entity) async {
  final res = await http.get(
    Uri.parse("http://localhost:4000/api/map/highlight/$entity"),
  );

  if (res.statusCode != 200) {
    print("Highlight API error ${res.statusCode}");
    print(res.body);
    return null;
  }

  return json.decode(res.body);
}

static Future<Map<String, dynamic>?> fetchConstructionHospitalViolations() async {
    final res = await http.get(
      Uri.parse("http://localhost:4000/api/violations/construction-hospitals"),
    );

    if (res.statusCode != 200) return null;

    return json.decode(res.body);
  }


  static Future<Map<String, dynamic>> fetchHospitalBuffers() async {
  final res = await http.get(
    Uri.parse("http://localhost:4000/api/map/hospital-buffers"),
  );
  return json.decode(res.body);
}

}
