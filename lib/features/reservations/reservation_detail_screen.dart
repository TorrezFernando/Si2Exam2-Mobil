import 'package:flutter/material.dart';
import '../../core/services/reservation_service.dart';
import '../../core/theme/theme.dart';

class ReservationDetailScreen extends StatefulWidget {
  final int reservationId;

  const ReservationDetailScreen({super.key, required this.reservationId});

  @override
  State<ReservationDetailScreen> createState() => _ReservationDetailScreenState();
}

class _ReservationDetailScreenState extends State<ReservationDetailScreen> {
  dynamic _reservation;
  bool _isLoading = true;
  bool _isCancelling = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await ReservationService.getReservation(widget.reservationId);
      setState(() {
        _reservation = data;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _cancelReservation() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancelar Reserva'),
        content: const Text('¿Estás seguro de que deseas cancelar esta reserva?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.danger),
            child: const Text('Sí, cancelar'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isCancelling = true);
    final success = await ReservationService.cancelReservation(widget.reservationId);
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Reserva cancelada'), backgroundColor: AppTheme.danger),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo cancelar la reserva')),
        );
        setState(() => _isCancelling = false);
      }
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed': return AppTheme.success;
      case 'cancelled': return AppTheme.danger;
      case 'completed': return AppTheme.primary;
      default: return AppTheme.accent;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending': return '⏳ Pendiente';
      case 'confirmed': return '✅ Confirmada';
      case 'cancelled': return '❌ Cancelada';
      case 'completed': return '🎉 Completada';
      default: return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_reservation == null) return const Scaffold(body: Center(child: Text('No se encontró la reserva')));

    final status = _reservation['status'] as String;
    final items = _reservation['items'] as List? ?? [];
    final canCancel = status == 'pending' || status == 'confirmed';

    return Scaffold(
      appBar: AppBar(title: Text('Reserva #${_reservation['id']}')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Estado
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: _statusColor(status).withOpacity(0.15),
                      child: Icon(Icons.calendar_today, color: _statusColor(status)),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Estado', style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        Text(_statusLabel(status), style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Info reserva
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Información', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const Divider(),
                    if (_reservation['pickup_date'] != null)
                      _infoRow('📅 Fecha recojo', _reservation['pickup_date'].toString().substring(0, 10)),
                    _infoRow('🏢 Sucursal ID', _reservation['branch_id'].toString()),
                    if (_reservation['notes'] != null)
                      _infoRow('📝 Notas', _reservation['notes']),
                    _infoRow('📆 Creado', _reservation['created_at'].toString().substring(0, 10)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Items
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Productos (${items.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const Divider(),
                    ...items.map((item) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Variante #${item['variant_id']}', style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text('Cantidad: ${item['quantity']}', style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                            ],
                          ),
                          if (item['unit_price'] != null)
                            Text('\$${item['unit_price'].toStringAsFixed(2)}',
                              style: const TextStyle(color: AppTheme.primary, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            ),

            if (canCancel) ...[
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
                  onPressed: _isCancelling ? null : _cancelReservation,
                  child: _isCancelling
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Cancelar Reserva'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13))),
        ],
      ),
    );
  }
}
