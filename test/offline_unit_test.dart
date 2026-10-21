import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fashionstore_mobile/core/services/cart_service.dart';
import 'package:fashionstore_mobile/core/services/auth_service.dart';
import 'package:fashionstore_mobile/core/services/mobile_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CartService Pricing & Stock Ceiling Tests', () {
    test('Calculates unitPrice following priority: price -> price_override -> base_price', () {
      final product = {'id': 1, 'base_price': 100.0};

      // Case 1: Variant with 'price' (SQLite schema)
      final cartItemWithPrice = CartItem(
        product: product,
        variant: {'id': 10, 'price': 120.0, 'stock': 5},
        quantity: 2,
      );
      expect(cartItemWithPrice.unitPrice, 120.0);
      expect(cartItemWithPrice.totalPrice, 240.0);

      // Case 2: Variant with 'price_override' (Backend API format)
      final cartItemWithOverride = CartItem(
        product: product,
        variant: {'id': 11, 'price_override': 150.0, 'stock': 5},
        quantity: 1,
      );
      expect(cartItemWithOverride.unitPrice, 150.0);
      expect(cartItemWithOverride.totalPrice, 150.0);

      // Case 3: Variant without specific price (falls back to base_price)
      final cartItemBase = CartItem(
        product: product,
        variant: {'id': 12, 'stock': 5},
        quantity: 3,
      );
      expect(cartItemBase.unitPrice, 100.0);
      expect(cartItemBase.totalPrice, 300.0);
    });

    test('Caps item quantity at available variant stock ceiling', () {
      final cart = CartService();
      final product = {'id': 1, 'name': 'Camisa Elegante', 'base_price': 50.0};
      final variant = {'id': 101, 'stock': 3, 'price': 55.0};

      // Try adding 5 units when only 3 are available
      cart.addToCart(product, variant, 5);

      expect(cart.items.length, 1);
      expect(cart.items.first.quantity, 3, reason: 'Quantity must be capped at variant stock');
      expect(cart.totalAmount, 165.0);

      // Try adding more units - should stay capped at 3
      cart.addToCart(product, variant, 2);
      expect(cart.items.first.quantity, 3);
    });

    test('Rejects adding variant with zero stock', () {
      final cart = CartService();
      final product = {'id': 2, 'base_price': 40.0};
      final outOfStockVariant = {'id': 102, 'stock': 0, 'price': 40.0};

      cart.addToCart(product, outOfStockVariant, 1);
      expect(cart.items.isEmpty, isTrue);
    });
  });

  group('AuthService Offline Resilience Tests', () {
    test('Restores session from local cache when offline', () async {
      SharedPreferences.setMockInitialValues({
        'auth_token': 'fake-jwt-token-12345',
        'cached_user_profile': jsonEncode({
          'id': 42,
          'email': 'vendedor@tenant1.com',
          'full_name': 'Vendedor Offline',
          'role': {'id': 2, 'name': 'vendedor'},
          'tenant_id': 1,
          'branch_id': 3,
        }),
      });

      final authService = AuthService();
      // Give asynchronous _checkLoginStatus time to complete
      await Future.delayed(const Duration(milliseconds: 100));

      expect(authService.isLoggedIn, isTrue);
      expect(authService.token, 'fake-jwt-token-12345');
      expect(authService.currentUser, isNotNull);
      expect(authService.currentUser!['email'], 'vendedor@tenant1.com');
      expect(authService.currentUser!['tenant_id'], 1);
      expect(authService.currentUser!['branch_id'], 3);
    });
  });

  group('MobileSyncService Validation Tests', () {
    test('ValidationException and InsufficientStockException work as expected', () {
      final vEx = ValidationException('Cantidad inválida');
      expect(vEx.message, 'Cantidad inválida');
      expect(vEx.toString(), 'Cantidad inválida');

      final stockEx = InsufficientStockException('Stock agotado');
      expect(stockEx.message, 'Stock agotado');
      expect(stockEx.toString(), 'Stock agotado');
    });
  });
}
