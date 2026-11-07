import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class CatalogService {
  static String? selectedStoreSlug;
  static String? selectedStoreName;

  static Future<void> setSelectedStore(String? slug, [String? name]) async {
    selectedStoreSlug = (slug != null && slug.trim().isNotEmpty) ? slug.trim() : null;
    selectedStoreName = name;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (selectedStoreSlug != null) {
        await prefs.setString('selected_store_slug', selectedStoreSlug!);
      } else {
        await prefs.remove('selected_store_slug');
      }
    } catch (_) {}
  }

  static Future<String?> loadSavedStoreSlug() async {
    if (selectedStoreSlug != null && selectedStoreSlug!.isNotEmpty) {
      return selectedStoreSlug;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      selectedStoreSlug = prefs.getString('selected_store_slug');
    } catch (_) {}
    return selectedStoreSlug;
  }

  static Future<Map<String, dynamic>> getStorefront({String? store}) async {
    final slug = store ?? selectedStoreSlug;
    final query = (slug != null && slug.isNotEmpty)
        ? '?store=${Uri.encodeQueryComponent(slug)}'
        : '';
    final response = await ApiService.get('/products/storefront$query');
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(jsonDecode(response.body));
    } else {
      throw Exception('Failed to load storefront');
    }
  }

  static Future<List<dynamic>> getProducts({String? store}) async {
    final slug = store ?? selectedStoreSlug;
    final query = (slug != null && slug.isNotEmpty)
        ? '?store=${Uri.encodeQueryComponent(slug)}'
        : '';
    final response = await ApiService.get('/products$query');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load products');
    }
  }

  static Future<dynamic> getProductDetails(int id, {String? store}) async {
    final slug = store ?? selectedStoreSlug;
    final query = (slug != null && slug.isNotEmpty)
        ? '?store=${Uri.encodeQueryComponent(slug)}'
        : '';
    final response = await ApiService.get('/products/$id$query');
    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      throw Exception('Failed to load product details');
    }
  }

  static Future<List<dynamic>> getStockByVariant(
    int variantId, {
    String? store,
  }) async {
    final slug = store ?? selectedStoreSlug;
    final query = (slug != null && slug.isNotEmpty)
        ? '?store=${Uri.encodeQueryComponent(slug)}'
        : '';
    final response = await ApiService.get('/inventory/variant/$variantId$query');
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
      // Ignore interaction tracking failures
    }
  }
}
