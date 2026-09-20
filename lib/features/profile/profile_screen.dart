import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/theme.dart';
import '../auth/login_screen.dart';
import '../checkout/my_purchases_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthService>(context);
    final user = auth.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Mi Perfil'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: AppTheme.danger),
            onPressed: () async {
              await auth.logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      body: user == null
          ? const Center(child: Text('No hay sesión activa'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // User Info Header
                Center(
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: AppTheme.primary,
                    child: Text(
                      (user['full_name'] != null && user['full_name'].toString().isNotEmpty) ? user['full_name'][0].toUpperCase() : 'U',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text(
                    user['full_name'] ?? 'Usuario',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                Center(
                  child: Text(
                    user['email'],
                    style: const TextStyle(color: AppTheme.textSecondary),
                  ),
                ),
                const SizedBox(height: 32),
                
                // Options
                const Text('Mi Cuenta', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Card(
                  color: AppTheme.bgCard,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.shopping_bag, color: AppTheme.primary),
                        title: const Text('Historial de Compras'),
                        trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (_) => const MyPurchasesScreen()));
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.edit, color: AppTheme.primary),
                        title: const Text('Editar Perfil'),
                        trailing: const Icon(Icons.chevron_right, color: AppTheme.textMuted),
                        onTap: () {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Próximamente...')));
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
