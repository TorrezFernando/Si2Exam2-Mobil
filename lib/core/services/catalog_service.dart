import 'dart:convert';
import 'api_service.dart';

class CatalogService {
  static Future<List<dynamic>> getProducts() async {
    final response = await ApiService.get('/products/');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load products');
    }
  }

  static Future<dynamic> getProductDetails(int id) async {
    final response = await ApiService.get('/products/$id');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load product details');
    }
  }

  static Future<List<dynamic>> getStockByVariant(int variantId) async {
    final response = await ApiService.get('/inventory/variant/$variantId');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load stock');
    }
  }

  static Future<List<dynamic>> getRecommendedProducts({int limit = 10}) async {
    final response = await ApiService.get('/products/recommended?limit=$limit');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load recommended products');
    }
  }

  static Future<void> interactWithProduct(int productId) async {
    try {
      await ApiService.post('/products/$productId/interact', {});
    } catch (e) {
      print('Error interacting with product: $e');
    }
  }
}
