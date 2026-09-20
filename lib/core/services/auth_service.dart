import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class AuthService extends ChangeNotifier {
  bool _isLoggedIn = false;
  bool get isLoggedIn => _isLoggedIn;
  
  Map<String, dynamic>? _user;
  Map<String, dynamic>? get user => _user;
  Map<String, dynamic>? get currentUser => _user;
  
  String? get token {
    // Necesitamos el token síncrono, se puede obtener de prefs pero lo guardaremos en memoria
    return _token;
  }
  String? _token;

  AuthService() {
    _checkLoginStatus();
  }

  Future<void> _checkLoginStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('auth_token');
    if (token != null) {
      _token = token;
      _isLoggedIn = true;
      try {
        await fetchUser();
      } catch (e) {
        await logout();
      }
    }
    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    try {
      final response = await ApiService.postForm('/auth/login', {
        'username': email, // FastAPI OAuth2 expects 'username'
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
        notifyListeners();
      } else {
        throw Exception('Failed to load user');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_token');
    _token = null;
    _isLoggedIn = false;
    _user = null;
    notifyListeners();
  }
}
