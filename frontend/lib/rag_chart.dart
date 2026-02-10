import 'dart:convert';
import 'package:frontend/config/api_config.dart';
import 'package:http/http.dart' as http;

Future<void> askRag(String question) async {
  final res = await http.post(
    Uri.parse("${ApiConfig.baseUrl}/api/rag/query"),
    headers: {"Content-Type": "application/json"},
    body: jsonEncode({"question": question}),
  );

  final data = json.decode(res.body);
  print(data["answer"]);
  print(data["citations"]);
}
