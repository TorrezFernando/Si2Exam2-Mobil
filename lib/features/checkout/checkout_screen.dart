import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/services/api_service.dart';
import '../../core/services/cart_service.dart';
import '../../core/services/reservation_service.dart';

class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key});
  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends State<CheckoutScreen> {
  bool _reserve = false;
  bool _busy = false;
  List<dynamic> _branches = [];
  int? _branchId;
  DateTime? _pickup;
  final String _requestKey = 'mobile-${DateTime.now().microsecondsSinceEpoch}';
  String? _error;

  @override
  void initState() { super.initState(); _loadBranches(); }

  Future<void> _loadBranches() async {
    try {
      final response = await ApiService.get('/branches');
      if (response.statusCode != 200) throw Exception('No se pudieron cargar las sucursales');
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as List;
      if (mounted) setState(() => _branches = data);
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final day = await showDatePicker(context: context, initialDate: now, firstDate: now, lastDate: now.add(const Duration(days: 30)));
    if (day == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 10, minute: 0));
    if (time != null && mounted) setState(() => _pickup = DateTime(day.year, day.month, day.day, time.hour, time.minute));
  }

  Future<void> _submit() async {
    if (_busy) return;
    final cart = context.read<CartService>();
    if (cart.items.isEmpty) return;
    if (_reserve && (_branchId == null || _pickup == null || !_pickup!.isAfter(DateTime.now()))) {
      setState(() => _error = 'Selecciona una sucursal y un horario futuro.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    final items = cart.items.map((item) => <String,dynamic>{'variant_id': item.variant?['id'] ?? 0, 'quantity': item.quantity}).toList();
    try {
      if (_reserve) {
        await ReservationService.createReservation(branchId: _branchId!, items: items, pickupDate: _pickup!.toUtc().toIso8601String());
        cart.clearCart();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Reserva registrada. La sucursal puede preparar tus prendas.')));
        Navigator.popUntil(context, (route) => route.isFirst);
      } else {
        final response = await ApiService.post('/orders', {'items': items, 'order_type': 'online_delivery', 'payment_method': 'tarjeta', 'request_key': _requestKey});
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (response.statusCode != 201) throw Exception(data['detail'] ?? 'No se pudo crear la orden');
        cart.clearCart();
        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => PaymentScreen(orderId: data['id'])));
      }
    } catch (e) { if (mounted) setState(() => _error = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartService>();
    return Scaffold(appBar: AppBar(title: const Text('Finalizar compra')), body: ListView(padding: const EdgeInsets.all(24), children: [
      Text('Total: Bs ${cart.totalAmount.toStringAsFixed(2)}', style: Theme.of(context).textTheme.headlineSmall),
      SwitchListTile(title: const Text('Reservar para probar en tienda'), value: _reserve, onChanged: _busy ? null : (v) => setState(() => _reserve = v)),
      if (_reserve) ...[
        DropdownButtonFormField<int>(value: _branchId, decoration: const InputDecoration(labelText: 'Sucursal'),
          items: _branches.map((b) => DropdownMenuItem<int>(value: b['id'], child: Text(b['name']))).toList(),
          onChanged: _busy ? null : (v) => setState(() => _branchId = v)),
        TextButton.icon(onPressed: _busy ? null : _pickDate, icon: const Icon(Icons.calendar_today), label: Text(_pickup == null ? 'Elegir fecha y hora' : _pickup.toString().substring(0,16))),
      ] else const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('Paga en Libélula con los medios habilitados por el comercio. No ingreses datos de tarjeta en esta aplicación.')),
      if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
      const SizedBox(height: 20),
      ElevatedButton(onPressed: _busy ? null : _submit, child: Text(_busy ? 'Procesando...' : _reserve ? 'Reservar prendas' : 'Continuar al pago')),
    ]));
  }
}

class PaymentScreen extends StatefulWidget {
  final int orderId;
  const PaymentScreen({super.key, required this.orderId});
  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  bool _busy = false;
  bool _paid = false;
  String _message = 'La orden está pendiente de pago.';
  String? _paymentUrl;
  static const _channel = MethodChannel('fashionstore/payments');

  Future<void> _perform(bool verify) async {
    setState(() => _busy = true);
    try {
      final response = await ApiService.post('/payments/${widget.orderId}/${verify ? 'verify' : 'checkout'}', {});
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200) throw Exception(data['detail'] ?? 'Error al consultar el pago');
      if (!mounted) return;
      if (verify || data['paid'] == true) {
        setState(() { _paid = data['is_paid'] == true || data['paid'] == true; _message = _paid ? 'Pago confirmado. Gracias por tu compra.' : 'Libélula aún no confirma el pago.'; });
      } else {
        _paymentUrl = data['payment_url'];
        try { await _channel.invokeMethod('openUrl', _paymentUrl); }
        on PlatformException { setState(() => _message = 'Abre el enlace de pago en tu navegador.'); }
        on MissingPluginException { setState(() => _message = 'Abre el enlace de pago en tu navegador.'); }
      }
    } catch (e) { if (mounted) setState(() => _message = e.toString()); }
    finally { if (mounted) setState(() => _busy = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text('Pago · Orden #${widget.orderId}')),
    body: ListView(padding: const EdgeInsets.all(24), children: [
      Text(_message), const SizedBox(height: 24),
      if (!_paid) ...[
        ElevatedButton(onPressed: _busy ? null : () => _perform(false), child: const Text('Abrir Libélula')),
        OutlinedButton(onPressed: _busy ? null : () => _perform(true), child: const Text('Verificar pago')),
        if (_paymentUrl != null) SelectableText(_paymentUrl!),
      ],
    ]));
}
