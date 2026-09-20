import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';
import 'api_service.dart';

class AiService {
  /// Llama al endpoint de Virtual Try-On del backend.
  /// Retorna la URL pública de la imagen generada.
  static Future<String> generateTryOn({
    required File userPhoto,
    required int productId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');

    final uri = Uri.parse('${ApiService.baseUrl}/ai/tryon');
    final request = http.MultipartRequest('POST', uri);

    if (token != null) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    // Adjuntar product_id como campo de formulario
    request.fields['product_id'] = productId.toString();

    // Adjuntar la foto del usuario
    final photoBytes = await userPhoto.readAsBytes();
    final ext = userPhoto.path.toLowerCase().split('.').last;
    final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';

    request.files.add(http.MultipartFile.fromBytes(
      'user_photo',
      photoBytes,
      filename: 'user_photo.$ext',
    ));

    final streamedResponse = await request.send().timeout(
      const Duration(seconds: 120),
      onTimeout: () => throw Exception('Tiempo agotado. Gemini tardó demasiado.'),
    );

    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode == 200) {
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      final resultUrl = data['result_url'] as String;
      // Construir URL completa si es relativa
      if (resultUrl.startsWith('/uploads/')) {
        final base = ApiService.baseUrl.replaceAll('/api/v1', '');
        return '$base$resultUrl';
      }
      return resultUrl;
    }

    final error = jsonDecode(utf8.decode(response.bodyBytes));
    throw Exception(error['detail'] ?? 'Error en el Try-On: ${response.statusCode}');
  }
}
