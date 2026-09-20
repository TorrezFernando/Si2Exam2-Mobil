import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/cart_service.dart';
import '../../core/theme/theme.dart';
import '../checkout/checkout_screen.dart';

class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartService>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Tu Carrito')),
      body: cart.items.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🛒', style: TextStyle(fontSize: 64)),
                  const SizedBox(height: 16),
                  Text('Tu carrito está vacío', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  const Text('Agrega algunos productos increíbles.', style: TextStyle(color: AppTheme.textSecondary)),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    itemCount: cart.items.length,
                    itemBuilder: (context, index) {
                      final item = cart.items[index];
                      final imageUrl = item.variant?['image_url'] ?? item.product['image_url'];
                      return ListTile(
                        leading: Container(
                          width: 50,
                          height: 50,
                          color: AppTheme.bgHover,
                          child: imageUrl != null
                              ? Image.network(imageUrl, fit: BoxFit.cover)
                              : const Icon(Icons.image, color: AppTheme.textMuted),
                        ),
                        title: Text(item.product['name']),
                        subtitle: Text(
                          item.variant != null
                              ? 'Talla: ${item.variant['size']} | ${item.variant['color']}'
                              : 'Variante Base',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, size: 20),
                              onPressed: () => cart.updateQuantity(index, -1),
                            ),
                            Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, size: 20),
                              onPressed: () => cart.updateQuantity(index, 1),
                            ),
                            const SizedBox(width: 8),
                            Text('\$${item.totalPrice.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppTheme.primary)),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: const BoxDecoration(
                    color: AppTheme.bgCard,
                    border: Border(top: BorderSide(color: Color.fromRGBO(108, 99, 255, 0.12))),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          Text('\$${cart.totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                        ],
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(builder: (_) => const CheckoutScreen()));
                          },
                          child: const Text('Proceder al Pago'),
                        ),
                      )
                    ],
                  ),
                )
              ],
            ),
    );
  }
}
