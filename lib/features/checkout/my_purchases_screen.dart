import 'package:flutter/material.dart';
import '../../core/services/order_service.dart';
import '../../core/theme/theme.dart';
import 'package:intl/intl.dart';
import 'checkout_screen.dart';

class MyPurchasesScreen extends StatefulWidget {
  const MyPurchasesScreen({super.key});

  @override
  State<MyPurchasesScreen> createState() => _MyPurchasesScreenState();
}

class _MyPurchasesScreenState extends State<MyPurchasesScreen> {
  bool _isLoading = true;
  List<dynamic> _orders = [];

  @override
  void initState() {
    super.initState();
    _fetchOrders();
  }

  Future<void> _fetchOrders() async {
    try {
      final orders = await OrderService.getMyOrders();
      if (!mounted) return;
      setState(() {
        _orders = orders;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cargar pedidos: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Fecha desconocida';
    try {
      final dt = DateTime.parse(dateStr);
      return DateFormat('dd/MM/yyyy HH:mm').format(dt);
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Historial de Compras')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _orders.isEmpty
              ? const Center(child: Text('Aún no tienes compras.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _orders.length,
                  itemBuilder: (context, index) {
                    final order = _orders[index];
                    return Card(
                      color: AppTheme.bgElevated,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ExpansionTile(
                        title: Text('Orden #${order['id']}'),
                        subtitle: Text(
                          '${_formatDate(order['created_at'])} • \$${((order['total_amount'] ?? 0) as num).toStringAsFixed(2)}',
                        ),
                        trailing: _buildStatusBadge(order['payment_status'] ?? order['status']),
                        children: [
                          if (order['payment_status'] == 'pending')
                            TextButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PaymentScreen(orderId: order['id']))).then((_) => _fetchOrders()), child: const Text('Continuar o verificar pago')),
                          const Divider(height: 1),
                          ...((order['items'] as List?) ?? []).map((item) {
                            final variant = item['variant'] ?? {};
                            final product = variant['product'] ?? {};
                            final subtotal = (item['unit_price'] ?? 0) * (item['quantity'] ?? 1);
                            return ListTile(
                              title: Text('${product['name'] ?? 'Producto'}'),
                              subtitle: Text('Cant: ${item['quantity'] ?? 0} • Talla: ${variant['size'] ?? '-'} • Color: ${variant['color'] ?? '-'}'),
                              trailing: Text('\$${(subtotal as num).toStringAsFixed(2)}'),
                            );
                          }).toList(),
                          if (order['payment_status'] == 'completed' || order['status'] == 'completed') ...[
                            const Divider(height: 1),
                            Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.receipt_long),
                                label: const Text('Ver Factura'),
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Abriendo factura PDF...')),
                                  );
                                },
                              ),
                            )
                          ]
                        ],
                      ),
                    );
                  },
                ),
    );
  }

  Widget _buildStatusBadge(String? status) {
    Color color;
    String label;
    switch (status) {
      case 'paid':
      case 'completed':
        color = AppTheme.success;
        label = 'Completado';
        break;
      case 'pending':
        color = AppTheme.warning;
        label = 'Pendiente';
        break;
      case 'cancelled':
        color = AppTheme.danger;
        label = 'Cancelado';
        break;
      case 'failed':
        color = AppTheme.danger;
        label = 'Fallido';
        break;
      default:
        color = Colors.grey;
        label = status ?? 'Desconocido';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 12)),
    );
  }
}
