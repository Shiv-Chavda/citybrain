import 'dart:convert';
import 'package:http/http.dart' as http;

class MapApi {
  static Future<Map<String, dynamic>> fetchHighlight(String entity) async {
    final res = await http.get(
      Uri.parse('http://localhost:8001/map/highlight?entity=$entity'),
    );
    return json.decode(res.body);
  }
}
