import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/theme.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.instance.markAllAsRead();
    });
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'purchase':
        return Icons.shopping_bag;
      case 'payment':
        return Icons.verified;
      case 'reservation':
        return Icons.event_available;
      case 'sync':
        return Icons.cloud_done;
      default:
        return Icons.notifications_active;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'purchase':
        return AppTheme.primary;
      case 'payment':
        return AppTheme.success;
      case 'reservation':
        return AppTheme.accent;
      case 'sync':
        return Colors.amber;
      default:
        return AppTheme.primary;
    }
  }

  String _formatDate(DateTime dt) {
    final two = (int n) => n.toString().padLeft(2, '0');
    return '${two(dt.day)}/${two(dt.month)}/${dt.year} ${two(dt.hour)}:${two(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final service = context.watch<NotificationService>();
    final items = service.items;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined),
            tooltip: 'Probar notificación',
            onPressed: () {
              NotificationService.instance.notify(
                title: '🛍️ FashionStore Activo',
                body: 'Las notificaciones de compras, pagos y reservas están habilitadas.',
                type: 'purchase',
              );
            },
          ),
          if (items.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Limpiar historial',
              onPressed: () => service.clearAll(),
            ),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.notifications_none,
                      size: 72,
                      color: AppTheme.textMuted,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No tienes notificaciones',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Aquí recibirás alertas de tus compras, pagos confirmados, reservas en tienda y sincronización offline.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.notifications_active),
                      label: const Text('Enviar notificación de prueba'),
                      onPressed: () {
                        NotificationService.instance.notify(
                          title: '🛍️ Compra de prueba confirmada',
                          body: 'Tu pedido de demostración fue procesado exitosamente en FashionStore.',
                          type: 'purchase',
                        );
                      },
                    ),
                  ],
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final n = items[index];
                final color = _colorForType(n.type);
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  color: AppTheme.bgCard,
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    leading: CircleAvatar(
                      backgroundColor: color.withOpacity(0.18),
                      child: Icon(_iconForType(n.type), color: color),
                    ),
                    title: Text(
                      n.title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text(n.body),
                        const SizedBox(height: 6),
                        Text(
                          _formatDate(n.createdAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
