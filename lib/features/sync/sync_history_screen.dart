import 'dart:convert';

import '../../core/services/api_service.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/mobile_sync_service.dart';
import '../../core/theme/theme.dart';

class SyncHistoryScreen extends StatefulWidget {
  const SyncHistoryScreen({super.key});

  @override
  State<SyncHistoryScreen> createState() => _SyncHistoryScreenState();
}

class _SyncHistoryScreenState extends State<SyncHistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    MobileSyncService.instance.addListener(_onSyncChanged);
  }

  void _onSyncChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadHistory();
    });
  }

  @override
  void dispose() {
    MobileSyncService.instance.removeListener(_onSyncChanged);
    super.dispose();
  }

  Future<void> _loadHistory() async {
    if (!mounted) return;
    try {
      final list = await MobileSyncService.instance.getSyncHistory();
      if (mounted)
        setState(() {
          _history = list;
          _loading = false;
        });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _download() async {
    final sync = MobileSyncService.instance;
    try {
      final response = await ApiService.get('/branches');
      if (response.statusCode != 200)
        throw Exception('No se pudieron consultar las sucursales.');
      final branches = jsonDecode(response.body) as List;
      final permitted = branches
          .where(
            (b) =>
                b['tenant_id'] == sync.tenantId &&
                (sync.permissions.contains('branches:write') ||
                    !sync.canSell ||
                    b['id'] == sync.assignedBranch),
          )
          .toList();
      if (!mounted) return;
      final branchId = await showDialog<int>(
        context: context,
        builder: (ctx) => SimpleDialog(
          title: const Text('Sucursal del catálogo'),
          children: permitted
              .map(
                (b) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, b['id'] as int),
                  child: Text(b['name']),
                ),
              )
              .toList(),
        ),
      );
      if (branchId == null) return;
      final ok = await sync.downloadCatalog(branchId);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Catálogo actualizado.'
                  : sync.message ?? 'No se pudo actualizar.',
            ),
          ),
        );
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MobileSyncService>(
      builder: (context, syncService, _) {
        final confirmed = _history
            .where((i) => i['status'] == 'CONFIRMADA')
            .length;
        final conflicts = _history
            .where((i) => i['status'] == 'RECHAZADA_CONFLICTO')
            .length;
        final pending = syncService.pendingCount;

        return Scaffold(
          backgroundColor: AppTheme.bgBase,
          appBar: AppBar(
            title: const Text('Sincronización Offline'),
            backgroundColor: AppTheme.bgCard,
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Recargar historial',
                onPressed: _loadHistory,
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: _loadHistory,
            color: AppTheme.primary,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (syncService.legacyData)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Existen datos anteriores sin propietario verificable. Se conservaron intactos y requieren conciliación administrativa antes de importarlos.',
                    ),
                  ),
                if (syncService.message != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(syncService.message!),
                  ),
                // 1. Estado de Conexión
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: syncService.isOnline
                        ? const Color(0xFF10B981).withOpacity(0.12)
                        : Colors.amber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: syncService.isOnline ? Colors.green : Colors.amber,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        syncService.isOnline ? Icons.wifi : Icons.wifi_off,
                        color: syncService.isOnline
                            ? Colors.green
                            : Colors.amber,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              syncService.isOnline
                                  ? 'En Línea (Conectado)'
                                  : 'Modo Sin Conexión (SQLite)',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: syncService.isOnline
                                    ? Colors.green
                                    : Colors.amber,
                              ),
                            ),
                            Text(
                              syncService.isOnline
                                  ? 'Las ventas locales se sincronizan automáticamente con el servidor.'
                                  : 'Operando localmente. Las operaciones se enviarán al reconectar.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // 2. Tarjetas de Métricas
                Row(
                  children: [
                    _buildStatCard(
                      'Pendientes',
                      '$pending',
                      Colors.amber,
                      Icons.hourglass_top,
                    ),
                    const SizedBox(width: 8),
                    _buildStatCard(
                      'Confirmadas',
                      '$confirmed',
                      Colors.green,
                      Icons.check_circle,
                    ),
                    const SizedBox(width: 8),
                    _buildStatCard(
                      'Conflictos',
                      '$conflicts',
                      Colors.red,
                      Icons.warning_amber,
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // 3. Botones de Acción
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primary,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed:
                            syncService.isSyncing ||
                                syncService.isOffline ||
                                pending == 0
                            ? null
                            : () async {
                                final res = await syncService.syncBatch(
                                  manual: true,
                                );
                                if (context.mounted && res != null) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        'Sincronizado: ${res['confirmed_count']} confirmadas, ${res['conflict_count']} conflictos',
                                      ),
                                    ),
                                  );
                                }
                                await _loadHistory();
                              },
                        icon: syncService.isSyncing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.sync, color: Colors.white),
                        label: Text(
                          syncService.isSyncing
                              ? 'Sincronizando...'
                              : 'Sincronizar Lote',
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          vertical: 12,
                          horizontal: 14,
                        ),
                        side: const BorderSide(color: AppTheme.textMuted),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: syncService.isOffline || syncService.isSyncing
                          ? null
                          : _download,
                      icon: const Icon(Icons.download, size: 18),
                      label: const Text('Catálogo'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // 4. Lista de Operaciones Históricas
                const Text(
                  'Cola y Registro de Operaciones Locales',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),

                if (_loading)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: CircularProgressIndicator(color: AppTheme.primary),
                    ),
                  )
                else if (_history.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(32),
                    alignment: Alignment.center,
                    child: const Column(
                      children: [
                        Icon(
                          Icons.inbox_outlined,
                          size: 48,
                          color: AppTheme.textMuted,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Sin operaciones locales registradas',
                          style: TextStyle(color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  )
                else
                  ..._history.map((op) => _buildOperationItem(op)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatCard(
    String label,
    String value,
    Color color,
    IconData icon,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOperationItem(Map<String, dynamic> op) {
    final status = op['status'] as String;
    final isSale = op['operation_type'] == 'sale';
    final uuid = op['client_operation_uuid'] as String;
    final error = op['error_message'] as String?;

    Color badgeColor;
    Color badgeBg;
    switch (status) {
      case 'CONFIRMADA':
        badgeColor = Colors.green;
        badgeBg = Colors.green.withOpacity(0.12);
        break;
      case 'RECHAZADA_CONFLICTO':
        badgeColor = Colors.red;
        badgeBg = Colors.red.withOpacity(0.15);
        break;
      case 'ENVIANDO':
        badgeColor = Colors.blue;
        badgeBg = Colors.blue.withOpacity(0.15);
        break;
      default:
        badgeColor = Colors.amber;
        badgeBg = Colors.amber.withOpacity(0.15);
    }

    return Card(
      color: AppTheme.bgCard,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: status == 'RECHAZADA_CONFLICTO'
              ? Colors.red.withOpacity(0.4)
              : Colors.transparent,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isSale
                        ? Colors.blue.withOpacity(0.15)
                        : Colors.purple.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isSale ? 'Venta Contado' : 'Reserva',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSale ? Colors.blue : Colors.purpleAccent,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    status,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'UUID: ${uuid.substring(0, 16)}...',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: AppTheme.textMuted,
              ),
            ),
            if (op['created_at'] != null)
              Text(
                'Fecha: ${op['created_at'].toString().replaceFirst('T', ' ').substring(0, 19)}',
                style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
              ),
            if (error != null && error.isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'Motivo: $error',
                  style: const TextStyle(fontSize: 11, color: Colors.redAccent),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
