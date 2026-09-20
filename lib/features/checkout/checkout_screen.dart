import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/cart_service.dart';
import '../../core/theme/theme.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  String _paymentMethod = 'tarjeta';
  final _cardNumberController = TextEditingController();
  bool _isProcessing = false;

  Future<void> _processPayment() async {
    if (_paymentMethod == 'tarjeta') {
      if (_cardNumberController.text.length < 14) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Por favor, ingresa un número de tarjeta válido'), backgroundColor: AppTheme.danger),
        );
        return;
      }
    }

    setState(() => _isProcessing = true);
    
    final cartService = Provider.of<CartService>(context, listen: false);
    final success = await cartService.submitOrder(
      paymentMethod: _paymentMethod,
      cardNumber: _paymentMethod == 'tarjeta' ? _cardNumberController.text : null,
    );

    if (!mounted) return;

    setState(() => _isProcessing = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('¡Pago completado con éxito!'), backgroundColor: AppTheme.success),
      );
      Navigator.popUntil(context, (route) => route.isFirst);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al procesar el pago. Intente de nuevo.'), backgroundColor: AppTheme.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartService>(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Finalizar Compra')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Total a pagar', style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text('\$${cart.totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppTheme.primary), textAlign: TextAlign.center),
            const SizedBox(height: 32),
            
            const Text('Método de Pago', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _buildMethodButton('tarjeta', '💳 Tarjeta')),
                const SizedBox(width: 8),
                Expanded(child: _buildMethodButton('qr', '📱 QR')),
                const SizedBox(width: 8),
                Expanded(child: _buildMethodButton('reserva', '🛍️ Reserva')),
              ],
            ),
            const SizedBox(height: 32),
            
            if (_paymentMethod == 'tarjeta') ...[
              TextField(
                controller: _cardNumberController,
                decoration: const InputDecoration(labelText: 'Número de Tarjeta'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Expanded(child: TextField(decoration: InputDecoration(labelText: 'Vencimiento'))),
                  SizedBox(width: 16),
                  Expanded(child: TextField(decoration: InputDecoration(labelText: 'CVV'), obscureText: true)),
                ],
              )
            ] else if (_paymentMethod == 'qr') ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(color: AppTheme.bgHover, borderRadius: BorderRadius.circular(16)),
                  child: const Icon(Icons.qr_code_2, size: 120),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Escanea este código con tu aplicación bancaria.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary)),
            ] else if (_paymentMethod == 'reserva') ...[
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: AppTheme.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.2)),
                ),
                child: const Column(
                  children: [
                    Text('🛍️', style: TextStyle(fontSize: 48)),
                    SizedBox(height: 16),
                    Text('Reserva en Tienda', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                    SizedBox(height: 8),
                    Text('Tus productos serán separados. Podrás pagarlos y recogerlos en la sucursal.', textAlign: TextAlign.center, style: TextStyle(color: AppTheme.textSecondary)),
                  ],
                ),
              )
            ],
            
            const SizedBox(height: 48),
            ElevatedButton(
              onPressed: _isProcessing ? null : _processPayment,
              child: _isProcessing 
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Pagar Ahora'),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildMethodButton(String method, String label) {
    final isSelected = _paymentMethod == method;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: isSelected ? AppTheme.primary : AppTheme.bgBase,
        foregroundColor: isSelected ? Colors.white : AppTheme.textPrimary,
        side: BorderSide(color: isSelected ? AppTheme.primary : const Color.fromRGBO(108, 99, 255, 0.25)),
      ),
      onPressed: () => setState(() => _paymentMethod = method),
      child: Text(label),
    );
  }
}
