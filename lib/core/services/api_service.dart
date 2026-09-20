import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http_parser/http_parser.dart';

class ApiService {
  static String get baseUrl {
    if (kIsWeb) return 'http://127.0.0.1:8000/api/v1';
    // Nota: Para dispositivos físicos Android usar 127.0.0.1 y ejecutar 'adb reverse tcp:8000 tcp:8000'
    if (Platform.isAndroid) return 'http://127.0.0.1:8000/api/v1';
    return 'http://127.0.0.1:8000/api/v1';
  }

  static String getFullImageUrl(String path) {
    if (path.startsWith('http')) return path;
    if (!path.startsWith('/')) path = '/$path';
    return 'http://127.0.0.1:8000$path';
  }

  static Future<Map<String, String>> _getHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static Future<http.Response> get(String endpoint) async {
    final headers = await _getHeaders();
    return http.get(Uri.parse('$baseUrl$endpoint'), headers: headers);
  }

  static Future<http.Response> post(String endpoint, Map<String, dynamic> body) async {
    final headers = await _getHeaders();
    return http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    );
  }
  
  static Future<http.Response> postForm(String endpoint, Map<String, String> body) async {
    final headers = await _getHeaders();
    headers.remove('Content-Type'); // http.post handles it for form-data
    return http.post(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: body,
    );
  }

  static Future<http.Response> patch(String endpoint, Map<String, dynamic> body) async {
    final headers = await _getHeaders();
    return http.patch(
      Uri.parse('$baseUrl$endpoint'),
      headers: headers,
      body: jsonEncode(body),
    );
  }

  static Future<http.Response> delete(String endpoint) async {
    final headers = await _getHeaders();
    return http.delete(Uri.parse('$baseUrl$endpoint'), headers: headers);
  }

  static Future<Map<String, dynamic>> generateAiTryOn(int productId, String imagePath) async {
    final headers = await _getHeaders();
    headers.remove('Content-Type'); // Let the multipart request set it
    
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/ai/tryon'));
    request.headers.addAll(headers);
    request.fields['product_id'] = productId.toString();
    request.files.add(await http.MultipartFile.fromPath(
      'user_photo', 
      imagePath,
      contentType: MediaType('image', 'jpeg'),
    ));
    
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);
    
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to generate try-on: ${response.statusCode} - ${response.body}');
    }
  }
}
