import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/cart_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/theme.dart';
import '../auth/login_screen.dart';
import '../auth/register_screen.dart';
import '../checkout/my_purchases_screen.dart';
import '../notifications/notifications_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final notif = Provider.of<NotificationService>(context);
    final user = auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Perfil'),
        actions: [
          if (auth.isLoggedIn)
            IconButton(
              icon: const Icon(Icons.logout, color: AppTheme.danger),
              tooltip: 'Cerrar Sesión',
              onPressed: () async {
                Provider.of<CartService>(context, listen: false).clearCart();
                await auth.logout();
              },
            ),
        ],
      ),
      body: user == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.account_circle_outlined,
                      size: 80,
                      color: AppTheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Bienvenido a FashionStore',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Inicia sesión o regístrate para realizar compras, reservar prendas en tienda y consultar tu historial.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppTheme.textSecondary),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: 240,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.login),
                        label: const Text('Iniciar Sesión'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(returnOnSuccess: true),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: 240,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.person_add_outlined),
                        label: const Text('Crear Cuenta'),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const RegisterScreen(),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton.icon(
                      icon: const Icon(Icons.notifications_outlined),
                      label: Text(
                        notif.unreadCount > 0
                            ? 'Ver Notificaciones (${notif.unreadCount})'
                            : 'Ver Notificaciones',
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const NotificationsScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: AppTheme.primary,
                    child: Text(
                      (user['full_name'] != null &&
                              user['full_name'].toString().isNotEmpty)
                          ? user['full_name'][0].toUpperCase()
                          : 'U',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    user['full_name'] ?? 'Usuario',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Center(
                  child: Text(
                    user['email'] ?? '',
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
                if (user['role']?['name'] != null) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withOpacity(0.18),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'Rol: ${user['role']['name']}',
                        style: const TextStyle(
                          color: AppTheme.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 32),
                const Text(
                  'Mi Cuenta',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Card(
                  color: AppTheme.bgCard,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(
                          Icons.shopping_bag,
                          color: AppTheme.primary,
                        ),
                        title: const Text('Historial de Compras'),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: AppTheme.textMuted,
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const MyPurchasesScreen(),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: Badge(
                          label: Text('${notif.unreadCount}'),
                          isLabelVisible: notif.unreadCount > 0,
                          child: const Icon(
                            Icons.notifications_active_outlined,
                            color: AppTheme.accent,
                          ),
                        ),
                        title: const Text('Mis Notificaciones'),
                        subtitle: const Text(
                          'Alertas de compras, pagos y reservas',
                          style: TextStyle(fontSize: 12),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: AppTheme.textMuted,
                        ),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const NotificationsScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
