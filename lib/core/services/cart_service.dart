import 'package:flutter/material.dart';

class CartItem {
  final dynamic product;
  final dynamic variant;
  int quantity;

  CartItem({
    required this.product,
    this.variant,
    this.quantity = 1,
  });

  double get unitPrice => (variant != null && variant['price_override'] != null)
      ? (variant['price_override'] as num).toDouble()
      : (product['base_price'] as num).toDouble();

  double get totalPrice => unitPrice * quantity;
}

class CartService extends ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => _items;

  int get totalItemsCount => _items.fold(0, (sum, item) => sum + item.quantity);

  double get totalAmount => _items.fold(0, (sum, item) => sum + item.totalPrice);

  void addToCart(dynamic product, dynamic variant, int quantity) {
    // Verificar si ya existe en el carrito
    final existingIndex = _items.indexWhere((item) =>
        item.product['id'] == product['id'] &&
        ((item.variant == null && variant == null) ||
            (item.variant != null && variant != null && item.variant['id'] == variant['id'])));

    if (existingIndex >= 0) {
      _items[existingIndex].quantity += quantity;
    } else {
      _items.add(CartItem(product: product, variant: variant, quantity: quantity));
    }
    notifyListeners();
  }

  void removeFromCart(int index) {
    if (index >= 0 && index < _items.length) {
      _items.removeAt(index);
      notifyListeners();
    }
  }

  void updateQuantity(int index, int delta) {
    if (index >= 0 && index < _items.length) {
      _items[index].quantity += delta;
      if (_items[index].quantity <= 0) {
        _items.removeAt(index);
      }
      notifyListeners();
    }
  }

  void clearCart() {
    _items.clear();
    notifyListeners();
  }

}
