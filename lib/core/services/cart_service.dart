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

  double get unitPrice {
    if (variant != null) {
      if (variant['price'] != null) {
        return (variant['price'] as num).toDouble();
      }
      if (variant['price_override'] != null) {
        return (variant['price_override'] as num).toDouble();
      }
    }
    return (product['base_price'] as num).toDouble();
  }

  double get totalPrice => unitPrice * quantity;
}

class CartService extends ChangeNotifier {
  final List<CartItem> _items = [];

  List<CartItem> get items => _items;

  int get totalItemsCount => _items.fold(0, (sum, item) => sum + item.quantity);

  double get totalAmount => _items.fold(0, (sum, item) => sum + item.totalPrice);

  void addToCart(dynamic product, dynamic variant, int quantity) {
    int availableStock = 9999;
    if (variant != null && variant['stock'] != null) {
      availableStock = (variant['stock'] as num).toInt();
    }
    if (availableStock <= 0) return;

    final existingIndex = _items.indexWhere((item) =>
        item.product['id'] == product['id'] &&
        ((item.variant == null && variant == null) ||
            (item.variant != null && variant != null && item.variant['id'] == variant['id'])));

    if (existingIndex >= 0) {
      final newQty = _items[existingIndex].quantity + quantity;
      _items[existingIndex].quantity = newQty > availableStock ? availableStock : newQty;
    } else {
      final initialQty = quantity > availableStock ? availableStock : quantity;
      _items.add(CartItem(product: product, variant: variant, quantity: initialQty));
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
      final item = _items[index];
      int availableStock = 9999;
      if (item.variant != null && item.variant['stock'] != null) {
        availableStock = (item.variant['stock'] as num).toInt();
      }
      final newQty = item.quantity + delta;
      if (newQty > availableStock) {
        item.quantity = availableStock;
      } else {
        item.quantity = newQty;
      }
      if (item.quantity <= 0) {
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
