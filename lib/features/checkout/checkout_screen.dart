import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/db/database_helper.dart';
import '../../core/services/api_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/cart_service.dart';
import '../../core/services/mobile_sync_service.dart';

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
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    try {
      final response = await ApiService.get('/branches');
      if (response.statusCode != 200)
        throw Exception('No se pudieron cargar las sucursales');
      final data = jsonDecode(utf8.decode(response.bodyBytes)) as List;
      if (mounted) {
        setState(() {
          _branches = data;
          if (_branches.isNotEmpty && _branchId == null) {
            _branchId = _branches.first['id'];
          }
        });
      }
    } catch (e) {
      // Fallback a SQLite local si estamos sin conexión
      try {
        final db = await DatabaseHelper.instance.database;
        final localBranches = await db.query('branches');
        if (localBranches.isNotEmpty && mounted) {
          setState(() {
            _branches = localBranches;
            _branchId ??= localBranches.first['id'] as int;
          });
          return;
        }
      } catch (_) {}
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
    );
    if (time != null && mounted) {
      setState(
        () => _pickup = DateTime(
          day.year,
          day.month,
          day.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    final cart = context.read<CartService>();
    final syncService = MobileSyncService.instance;
    final auth = context.read<AuthService>();

    if (cart.items.isEmpty) return;
    if (syncService.isOffline && !_reserve && !syncService.canSell) {
      setState(
        () => _error = 'La compra con tarjeta necesita conexión. La caja offline es solo para personal autorizado.',
      );
      return;
    }
    if (_branchId == null && (_reserve || syncService.isOffline)) {
      setState(
        () => _error = 'Selecciona una sucursal con catálogo descargado.',
      );
      return;
    }
    bool cashConfirmed = false;
    if (syncService.isOffline && !_reserve) {
      cashConfirmed =
          await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Confirmar cobro en efectivo'),
              content: Text(
                '¿Recibiste Bs ${cart.totalAmount.toStringAsFixed(2)} del cliente?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancelar'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Efectivo recibido'),
                ),
              ],
            ),
          ) ??
          false;
      if (!cashConfirmed || !mounted) return;
    }
    if (_reserve &&
        (_branchId == null ||
            _pickup == null ||
            !_pickup!.isAfter(DateTime.now()))) {
      setState(() => _error = 'Selecciona una sucursal y un horario futuro.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });

    final items = cart.items
        .map(
          (item) => <String, dynamic>{
            'variant_id': item.variant?['id'] ?? 0,
            'quantity': item.quantity,
          },
        )
        .toList();

    final offlineItems = cart.items
        .map(
          (i) => {
            'variant_id': i.variant?['id'] ?? 0,
            'quantity': i.quantity,
            'unit_price': i.unitPrice,
            'product_name': i.product['name'] ?? '',
            'variant_label':
                '${i.variant?['size'] ?? ''} ${i.variant?['color'] ?? ''}'
                    .trim(),
          },
        )
        .toList();

    // ── MODO OFFLINE EXPLICITO ──
    if (syncService.isOffline) {
      try {
        if (_reserve) {
          await syncService.recordOfflineReservation(
            branchId: _branchId!,
            tenantId: auth.currentUser?['tenant_id'],
            userId: auth.currentUser!['id'],
            customerName: auth.currentUser?['full_name'] ?? 'Cliente Móvil',
            pickupDate: _pickup?.toUtc().toIso8601String(),
            notes: 'Reserva guardada offline en SQLite',
            items: offlineItems,
          );
          cart.clearCart();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.amber,
              content: Text(
                'Modo Offline: Reserva guardada en SQLite. Se sincronizará al conectar.',
              ),
            ),
          );
          Navigator.popUntil(context, (route) => route.isFirst);
        } else {
          await syncService.recordOfflineSale(
            branchId: _branchId!,
            tenantId: auth.currentUser?['tenant_id'],
            userId: auth.currentUser?['id'],
            customerName: auth.currentUser?['full_name'] ?? 'Cliente Móvil',
            paymentMethod: 'efectivo',
            cashConfirmed: cashConfirmed,
            totalAmount: cart.totalAmount,
            items: offlineItems,
          );
          cart.clearCart();
          if (!mounted) return;
          showDialog(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.offline_pin, color: Colors.amber),
                  SizedBox(width: 8),
                  Text('Venta Offline Registrada'),
                ],
              ),
              content: const Text(
                'La compra se guardó en la base de datos local SQLite y se descontó del stock local.\n\nSe enviará automáticamente al servidor cuando recuperes la conexión a Internet.',
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    Navigator.popUntil(context, (route) => route.isFirst);
                  },
                  child: const Text('Entendido'),
                ),
              ],
            ),
          );
        }
      } catch (e) {
        if (mounted) setState(() => _error = 'Error registrando offline: $e');
      } finally {
        if (mounted) setState(() => _busy = false);
      }
      return;
    }

    // ── MODO ONLINE ──
    try {
      if (_reserve) {
        if (await syncService.cachedBranch() != _branchId) {
          if (!await syncService.downloadCatalog(_branchId!))
            throw Exception(
              syncService.message ?? 'Descarga el catálogo de la sucursal.',
            );
        }
        await syncService.recordOfflineReservation(
          branchId: _branchId!,
          tenantId: auth.currentUser?['tenant_id'],
          userId: auth.currentUser!['id'],
          items: offlineItems,
          pickupDate: _pickup!.toUtc().toIso8601String(),
        );
        cart.clearCart();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Reserva guardada; revisa su confirmación en Sincronización.',
            ),
          ),
        );
        Navigator.popUntil(context, (route) => route.isFirst);
      } else {
        final response = await ApiService.post('/orders', {
          'items': items,
          'order_type': 'online_delivery',
          'payment_method': 'tarjeta',
          'request_key': _requestKey,
        });
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        if (response.statusCode != 201) {
          // Error explícito del servidor (400, 401, 403, 422). NO convertir a venta offline en efectivo.
          if (mounted) {
            setState(
              () => _error =
                  data['detail'] ?? 'No se pudo crear la orden en el servidor.',
            );
          }
          return;
        }
        cart.clearCart();
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => PaymentScreen(orderId: data['id'])),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartService>();
    final syncService = context.watch<MobileSyncService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Finalizar compra'),
        actions: [
          if (syncService.isOffline)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Icon(Icons.wifi_off, color: Colors.amber),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          if (syncService.isOffline)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Operando sin conexión. Tu compra o reserva se guardará en SQLite y se sincronizará automáticamente.',
                      style: TextStyle(color: Colors.amber, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          Text(
            'Total: Bs ${cart.totalAmount.toStringAsFixed(2)}',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          SwitchListTile(
            title: const Text('Reservar para probar en tienda'),
            value: _reserve,
            onChanged: _busy ? null : (v) => setState(() => _reserve = v),
          ),
          if (_reserve) ...[
            DropdownButtonFormField<int>(
              value: _branchId,
              decoration: const InputDecoration(labelText: 'Sucursal'),
              items: _branches
                  .map(
                    (b) => DropdownMenuItem<int>(
                      value: b['id'],
                      child: Text(b['name'] ?? 'Sucursal ${b['id']}'),
                    ),
                  )
                  .toList(),
              onChanged: _busy ? null : (v) => setState(() => _branchId = v),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _pickDate,
              icon: const Icon(Icons.calendar_today),
              label: Text(
                _pickup == null
                    ? 'Elegir fecha y hora'
                    : _pickup.toString().substring(0, 16),
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                syncService.isOffline
                    ? 'Modo Offline: La venta se registrará como pago en efectivo y se sincronizará con el inventario central.'
                    : 'Paga en Libélula con los medios habilitados por el comercio. No ingreses datos de tarjeta en esta aplicación.',
              ),
            ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _busy ? null : _submit,
            child: Text(
              _busy
                  ? 'Procesando...'
                  : _reserve
                  ? 'Reservar prendas'
                  : syncService.isOffline
                  ? 'Guardar venta offline (SQLite)'
                  : 'Continuar al pago',
            ),
          ),
        ],
      ),
    );
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
      final response = await ApiService.post(
        '/payments/${widget.orderId}/${verify ? 'verify' : 'checkout'}',
        {},
      );
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200)
        throw Exception(data['detail'] ?? 'Error al consultar el pago');
      if (!mounted) return;
      if (verify || data['paid'] == true) {
        setState(() {
          _paid = data['is_paid'] == true || data['paid'] == true;
          _message = _paid
              ? 'Pago confirmado. Gracias por tu compra.'
              : 'Libélula aún no confirma el pago.';
        });
      } else {
        _paymentUrl = data['payment_url'];
        try {
          await _channel.invokeMethod('openUrl', _paymentUrl);
        } on PlatformException {
          setState(() => _message = 'Abre el enlace de pago en tu navegador.');
        } on MissingPluginException {
          setState(() => _message = 'Abre el enlace de pago en tu navegador.');
        }
      }
    } catch (e) {
      if (mounted) setState(() => _message = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Pago · Orden #${widget.orderId}')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Text(_message),
        const SizedBox(height: 24),
        if (!_paid) ...[
          ElevatedButton(
            onPressed: _busy ? null : () => _perform(false),
            child: const Text('Abrir Libélula'),
          ),
          OutlinedButton(
            onPressed: _busy ? null : () => _perform(true),
            child: const Text('Verificar pago'),
          ),
          if (_paymentUrl != null) SelectableText(_paymentUrl!),
        ],
      ],
    ),
  );
}
