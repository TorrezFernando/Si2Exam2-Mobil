import 'dart:convert';
import 'package:flutter/material.dart';
import 'api_service.dart';

class ReservationService {
  /// Lista las reservas del usuario autenticado
  static Future<List<dynamic>> getMyReservations() async {
    final response = await ApiService.get('/reservations/');
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
    }
    throw Exception('Error al cargar reservas: ${response.statusCode}');
  }

  /// Obtiene el detalle de una reserva
  static Future<Map<String, dynamic>> getReservation(int id) async {
    final response = await ApiService.get('/reservations/$id');
    if (response.statusCode == 200) {
      return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    }
    throw Exception('Reserva no encontrada');
  }

  /// Crea una nueva reserva
  static Future<Map<String, dynamic>> createReservation({
    required int branchId,
    required List<Map<String, dynamic>> items,
    String? notes,
    String? pickupDate,
  }) async {
    final body = {
      'branch_id': branchId,
      'items': items,
      if (notes != null) 'notes': notes,
      if (pickupDate != null) 'pickup_date': pickupDate,
    };
    final response = await ApiService.post('/reservations/', body);
    if (response.statusCode == 201) {
      return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    }
    final error = jsonDecode(utf8.decode(response.bodyBytes));
    throw Exception(error['detail'] ?? 'Error al crear reserva');
  }

  /// Cancela una reserva
  static Future<bool> cancelReservation(int id) async {
    final response = await ApiService.patch('/reservations/$id/cancel', {});
    return response.statusCode == 200;
  }
}
