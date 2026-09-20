import 'dart:convert';
import 'api_service.dart';

class OrderService {
  static Future<List<dynamic>> getMyOrders() async {
    final response = await ApiService.get('/orders/');
    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load orders: ${response.body}');
    }
  }

  static Future<dynamic> createOrder({
    required List<Map<String, dynamic>> items,
    required String paymentMethod,
    required String orderType,
    int? branchId,
  }) async {
    final body = {
      'items': items,
      'payment_method': paymentMethod,
      'order_type': orderType,
    };
    if (branchId != null) {
      body['branch_id'] = branchId;
    }

    final response = await ApiService.post('/orders/', body);
    if (response.statusCode == 201 || response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to create order: ${response.body}');
    }
  }
}
