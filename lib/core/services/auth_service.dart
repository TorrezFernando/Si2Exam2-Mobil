import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AuthRejectedException implements Exception {
  final String message;
  AuthRejectedException([this.message = 'Credenciales no autorizadas o sesión expirada']);
  @override
  String toString() => message;
}

class AuthService extends ChangeNotifier {
  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;
  
  Map<String, dynamic>? _user;
  Map<String, dynamic>? get user => _user;
  Map<String, dynamic>? get currentUser => _user;
  
  String? get token => _token;
  String? _token;

  AuthService() {
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    final cachedProfileStr = prefs.getString('cached_user_profile');

    if (token != null) {
      _token = token;
      _isLoggedIn = true;
      if (cachedProfileStr != null) {
        try {
          _user = jsonDecode(cachedProfileStr);
        } catch (_) {}
      }
      notifyListeners();

      // Intentar refrescar perfil en segundo plano sin destruir la sesión offline si no hay red
      try {
        await fetchUser();
      } on AuthRejectedException {
        // Solo si el servidor rechazó explícitamente el token (401/403)
        await logout();
      } catch (e) {
        // Error de red / timeout: Mantener sesión offline con datos cacheados
        debugPrint('[AUTH] Sin conexión al reanudar sesión. Operando con perfil en caché local.');
      }
    }
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    try {
      final response = await ApiService.postForm('/auth/login', {
        'username': email,
        'password': password,
      });

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_token', data['access_token']);
        _token = data['access_token'];
        _isLoggedIn = true;
        
        await fetchUser();
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> register(String firstName, String lastName, String email, String password) async {
    try {
      final response = await ApiService.post('/auth/register', {
        'full_name': '$firstName $lastName'.trim(),
        'email': email,
        'password': password,
      });

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<void> fetchUser() async {
    try {
      final response = await ApiService.get('/auth/me');
      if (response.statusCode == 200) {
        _user = jsonDecode(response.body);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('cached_user_profile', response.body);
        notifyListeners();
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        throw AuthRejectedException('Sesión rechazada por el servidor: HTTP ${response.statusCode}');
      } else {
        throw Exception('HTTP ${response.statusCode} al obtener usuario');
      }
    } on AuthRejectedException {
      rethrow;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    await prefs.remove('cached_user_profile');
    _token = null;
    _isLoggedIn = false;
    _user = null;
    notifyListeners();
  }
}
