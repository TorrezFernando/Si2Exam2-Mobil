import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final String type; // 'purchase', 'payment', 'reservation', 'sync', 'info'
  final DateTime createdAt;
  bool isRead;

  AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.type = 'info',
    required this.createdAt,
    this.isRead = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'body': body,
        'type': type,
        'created_at': createdAt.toIso8601String(),
        'is_read': isRead,
      };

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id']?.toString() ?? DateTime.now().microsecondsSinceEpoch.toString(),
      title: json['title']?.toString() ?? 'FashionStore',
      body: json['body']?.toString() ?? '',
      type: json['type']?.toString() ?? 'info',
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      isRead: json['is_read'] == true,
    );
  }
}

class NotificationService extends ChangeNotifier {
  static final NotificationService instance = NotificationService._();
  factory NotificationService() => instance;

  NotificationService._() {
    _load();
  }

  static const MethodChannel _channel = MethodChannel('fashionstore/notifications');
  static const String _storageKey = 'app_notifications_v1';

  final List<AppNotification> _items = [];
  List<AppNotification> get items => List.unmodifiable(_items);

  int get unreadCount => _items.where((n) => !n.isRead).length;

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as List;
        _items
          ..clear()
          ..addAll(decoded.map((e) => AppNotification.fromJson(Map<String, dynamic>.from(e))));
        notifyListeners();
      }
      await requestPermission();
    } catch (e) {
      debugPrint('Error cargando notificaciones: $e');
    }
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(_items.take(50).map((e) => e.toJson()).toList());
      await prefs.setString(_storageKey, encoded);
    } catch (_) {}
  }

  Future<void> requestPermission() async {
    try {
      await _channel.invokeMethod('requestPermission');
    } catch (_) {}
  }

  Future<void> notify({
    required String title,
    required String body,
    String type = 'info',
  }) async {
    final item = AppNotification(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      title: title,
      body: body,
      type: type,
      createdAt: DateTime.now(),
      isRead: false,
    );
    _items.insert(0, item);
    notifyListeners();
    await _save();

    try {
      await _channel.invokeMethod('show', {
        'id': DateTime.now().millisecondsSinceEpoch % 2147483647,
        'title': title,
        'body': body,
      });
    } catch (_) {}
  }

  Future<void> markAllAsRead() async {
    var changed = false;
    for (final item in _items) {
      if (!item.isRead) {
        item.isRead = true;
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      await _save();
    }
  }

  Future<void> markAsRead(String id) async {
    for (final item in _items) {
      if (item.id == id && !item.isRead) {
        item.isRead = true;
        notifyListeners();
        await _save();
        break;
      }
    }
  }

  Future<void> clearAll() async {
    _items.clear();
    notifyListeners();
    await _save();
  }
}
