import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/reservation_service.dart';
import '../../core/theme/theme.dart';
import '../auth/login_screen.dart';
import 'reservation_detail_screen.dart';

class ReservationScreen extends StatefulWidget {
  const ReservationScreen({super.key});

  @override
  State<ReservationScreen> createState() => _ReservationScreenState();
}

class _ReservationScreenState extends State<ReservationScreen> {
  List<dynamic> _reservations = [];
  bool _isLoading = true;
  String? _error;
  String? _lastToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReservations();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final token = Provider.of<AuthService>(context).token;
    if (_lastToken != token) {
      _lastToken = token;
      _loadReservations();
    }
  }

  Future<void> _loadReservations() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!auth.isLoggedIn) {
      if (mounted) {
        setState(() {
          _reservations = [];
          _error = null;
          _isLoading = false;
        });
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await ReservationService.getMyReservations();
      if (mounted) {
        setState(() {
          _reservations = data;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'confirmed':
        return AppTheme.success;
      case 'cancelled':
        return AppTheme.danger;
      case 'completed':
        return AppTheme.primary;
      default:
        return AppTheme.accent;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return '⏳ Pendiente';
      case 'confirmed':
        return '✅ Confirmada';
      case 'cancelled':
        return '❌ Cancelada';
      case 'completed':
        return '🎉 Completada';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mis Reservas'),
        actions: [
          if (auth.isLoggedIn)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadReservations,
            )
        ],
      ),
      body: !auth.isLoggedIn
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('📅', style: TextStyle(fontSize: 64)),
                    const SizedBox(height: 16),
                    Text(
                      'Inicia sesión para ver tus reservas',
                      style: Theme.of(context).textTheme.titleLarge,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Puedes explorar el catálogo libremente y cuando desees reservar o comprar prendas, ingresa con tu cuenta.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.login),
                      label: const Text('Iniciar Sesión'),
                      onPressed: () async {
                        final ok = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(returnOnSuccess: true),
                          ),
                        );
                        if (ok == true && mounted) {
                          _loadReservations();
                        }
                      },
                    ),
                  ],
                ),
              ),
            )
          : _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Text('😕', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 12),
                          Text('Error al cargar reservas', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 8),
                          TextButton(onPressed: _loadReservations, child: const Text('Reintentar')),
                        ],
                      ),
                    )
                  : _reservations.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Text('📅', style: TextStyle(fontSize: 64)),
                              const SizedBox(height: 16),
                              Text('No tienes reservas aún', style: Theme.of(context).textTheme.titleLarge),
                              const SizedBox(height: 8),
                              const Text('Reserva productos desde el catálogo.', style: TextStyle(color: AppTheme.textSecondary)),
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadReservations,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _reservations.length,
                            itemBuilder: (context, index) {
                              final r = _reservations[index];
                              final status = r['status'] as String;
                              final itemCount = (r['items'] as List?)?.length ?? 0;
                              final createdAt = r['created_at'] != null
                                  ? DateTime.tryParse(r['created_at'])
                                  : null;

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  leading: CircleAvatar(
                                    backgroundColor: _statusColor(status).withOpacity(0.15),
                                    child: Icon(Icons.calendar_today, color: _statusColor(status), size: 20),
                                  ),
                                  title: Text(
                                    'Reserva #${r['id']}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _statusColor(status).withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          _statusLabel(status),
                                          style: TextStyle(color: _statusColor(status), fontSize: 12, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '$itemCount producto${itemCount != 1 ? 's' : ''}${createdAt != null ? ' · ${createdAt.day}/${createdAt.month}/${createdAt.year}' : ''}',
                                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                      ),
                                    ],
                                  ),
                                  trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ReservationDetailScreen(reservationId: r['id']),
                                      ),
                                    ).then((_) => _loadReservations());
                                  },
                                ),
                              );
                            },
                          ),
                        ),
    );
  }
}
