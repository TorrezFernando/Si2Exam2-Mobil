import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/auth_service.dart';
import '../../core/services/catalog_service.dart';
import '../../core/services/cart_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/product_image.dart';
import '../auth/login_screen.dart';
import '../cart/cart_screen.dart';
import '../notifications/notifications_screen.dart';
import '../reservations/reservation_screen.dart';
import 'product_detail_screen.dart';
import '../chat/chat_screen.dart';
import '../../core/services/mobile_sync_service.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  List<dynamic> _products = [];
  List<dynamic> _filteredProducts = [];
  List<dynamic> _recommendedProducts = [];
  List<Map<String, dynamic>> _stores = [];
  String? _selectedStoreSlug;
  String? _selectedStoreName;
  String? _lastAuthKey;
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchProducts();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = Provider.of<AuthService>(context);
    final authKey = '${auth.token ?? "anon"}:${auth.currentUser?['id'] ?? ""}:${auth.currentUser?['tenant_id'] ?? ""}';
    if (_lastAuthKey != null && _lastAuthKey != authKey) {
      _lastAuthKey = authKey;
      _fetchProducts();
    } else {
      _lastAuthKey = authKey;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final q = _searchController.text.toLowerCase().trim();
    setState(() {
      _filteredProducts = q.isEmpty
          ? _products
          : _products.where((p) {
              final name = (p['name'] as String).toLowerCase();
              final desc = ((p['description'] ?? '') as String).toLowerCase();
              return name.contains(q) || desc.contains(q);
            }).toList();
    });
  }

  Future<void> _onStoreChanged(String? slug) async {
    if (slug == null || slug.isEmpty || slug == _selectedStoreSlug) return;
    final storeObj = _stores.firstWhere(
      (s) => s['slug'] == slug,
      orElse: () => {'slug': slug, 'name': slug},
    );
    await CatalogService.setSelectedStore(slug, storeObj['name']?.toString());
    if (!mounted) return;
    Provider.of<CartService>(context, listen: false).clearCart();
    setState(() {
      _selectedStoreSlug = slug;
      _selectedStoreName = storeObj['name']?.toString();
      _isLoading = true;
    });
    await _fetchProducts(forceSlug: slug);
  }

  Future<void> _fetchProducts({String? forceSlug}) async {
    final syncService = MobileSyncService.instance;
    if (syncService.isOffline) {
      try {
        final localProds = await syncService.getLocalProducts();
        if (!mounted) return;
        setState(() {
          _products = localProds;
          _filteredProducts = localProds;
          _recommendedProducts = [];
          _isLoading = false;
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _products = [];
          _filteredProducts = [];
          _recommendedProducts = [];
          _isLoading = false;
        });
      }
      return;
    }

    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      final userTenantId = auth.currentUser?['tenant_id'];

      String? slugToUse = forceSlug ?? _selectedStoreSlug ?? await CatalogService.loadSavedStoreSlug();
      if (userTenantId != null) {
        slugToUse = null;
      }

      final storefront = await CatalogService.getStorefront(store: slugToUse);
      final rawStores = (storefront['stores'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      Map<String, dynamic>? selected = storefront['selected'] != null
          ? Map<String, dynamic>.from(storefront['selected'] as Map)
          : null;

      // Si es superadmin o visitante sin tienda elegida, seleccionar por defecto FashionStore Corp o la primera disponible
      if (selected == null && rawStores.isNotEmpty) {
        selected = rawStores.firstWhere(
          (s) => s['slug'] == 'fashionstore',
          orElse: () => rawStores.first,
        );
        slugToUse = selected['slug']?.toString();
      } else if (selected != null) {
        slugToUse = selected['slug']?.toString();
      }

      await CatalogService.setSelectedStore(slugToUse, selected?['name']?.toString());

      final products = await CatalogService.getProducts(store: slugToUse);

      List<dynamic> recommended = [];
      if (auth.token != null && userTenantId != null) {
        try {
          recommended = await CatalogService.getRecommendedProducts(limit: 4);
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _stores = rawStores;
        _selectedStoreSlug = slugToUse;
        _selectedStoreName = selected?['name']?.toString();
        _products = products;
        _filteredProducts = products;
        _recommendedProducts = recommended;
        _isLoading = false;
      });
      _onSearchChanged();

      if (auth.token != null && userTenantId != null) {
        final branchId =
            await syncService.cachedBranch() ??
            auth.currentUser?['branch_id'] as int?;
        if (branchId != null &&
            (syncService.lastSyncTimestamp == null ||
                DateTime.now()
                        .difference(
                          DateTime.parse(syncService.lastSyncTimestamp!),
                        )
                        .inMinutes >=
                    15)) {
          syncService.downloadCatalog(branchId);
        }
      }
    } catch (e) {
      try {
        final localProds = await syncService.getLocalProducts();
        if (localProds.isNotEmpty && mounted) {
          setState(() {
            _products = localProds;
            _filteredProducts = localProds;
            _recommendedProducts = [];
            _isLoading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Colors.amber,
              content: Text(
                'Sin conexión al servidor: Mostrando catálogo guardado en SQLite local',
              ),
            ),
          );
          return;
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error cargando el catálogo')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartService>(context);
    final auth = Provider.of<AuthService>(context);
    final notif = Provider.of<NotificationService>(context);
    final canSwitchStore = _stores.length > 1 && auth.currentUser?['tenant_id'] == null;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          auth.currentUser?['tenant_name'] ??
              _selectedStoreName ??
              'Catálogo FashionStore',
        ),
        actions: [
          IconButton(
            icon: Badge(
              label: Text('${notif.unreadCount}'),
              isLabelVisible: notif.unreadCount > 0,
              child: const Icon(Icons.notifications_outlined),
            ),
            tooltip: 'Notificaciones',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationsScreen()),
              );
            },
          ),
          IconButton(
            icon: Badge(
              label: Text(cart.totalItemsCount.toString()),
              isLabelVisible: cart.totalItemsCount > 0,
              child: const Icon(Icons.shopping_cart),
            ),
            tooltip: 'Carrito',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const CartScreen()),
              );
            },
          ),
          if (auth.isLoggedIn)
            IconButton(
              icon: const Icon(Icons.logout, color: AppTheme.danger),
              tooltip: 'Cerrar Sesión',
              onPressed: () async {
                cart.clearCart();
                await auth.logout();
                if (mounted) {
                  _fetchProducts();
                }
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.login, color: AppTheme.primary),
              tooltip: 'Iniciar Sesión',
              onPressed: () async {
                final loggedIn = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const LoginScreen(returnOnSuccess: true),
                  ),
                );
                if (loggedIn == true && mounted) {
                  _fetchProducts();
                }
              },
            ),
        ],
      ),
      body: Column(
        children: [
          if (canSwitchStore)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.bgCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.primary.withOpacity(0.35)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.storefront, color: AppTheme.primary, size: 20),
                    const SizedBox(width: 10),
                    const Text(
                      'Tienda:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _stores.any((s) => s['slug'] == _selectedStoreSlug)
                              ? _selectedStoreSlug
                              : (_stores.isNotEmpty ? _stores.first['slug'] as String : null),
                          isExpanded: true,
                          dropdownColor: AppTheme.bgCard,
                          items: _stores
                              .map(
                                (s) => DropdownMenuItem<String>(
                                  value: s['slug']?.toString(),
                                  child: Text(
                                    s['name']?.toString() ?? '',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: _onStoreChanged,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Barra de búsqueda
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar productos...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                filled: true,
                fillColor: AppTheme.bgCard,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          // Resultados
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredProducts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text('🔍', style: TextStyle(fontSize: 48)),
                        const SizedBox(height: 12),
                        Text(
                          _searchController.text.isEmpty
                              ? 'No hay productos disponibles'
                              : 'Sin resultados para "${_searchController.text}"',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('Recargar catálogo'),
                          onPressed: () {
                            setState(() => _isLoading = true);
                            _fetchProducts();
                          },
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _fetchProducts(),
                    child: ListView(
                      children: [
                        if (_searchController.text.isEmpty &&
                            _recommendedProducts.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text(
                              '✨ Para Ti',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  childAspectRatio: 0.48,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                ),
                            itemCount: _recommendedProducts.length,
                            itemBuilder: (context, index) =>
                                _buildProductCard(_recommendedProducts[index]),
                          ),
                          const Padding(
                            padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                            child: Text(
                              'Todos los Productos',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical:
                                _searchController.text.isEmpty &&
                                    _recommendedProducts.isNotEmpty
                                ? 0
                                : 16,
                          ),
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                childAspectRatio: 0.48,
                                crossAxisSpacing: 16,
                                mainAxisSpacing: 16,
                              ),
                          itemCount: _filteredProducts.length,
                          itemBuilder: (context, index) =>
                              _buildProductCard(_filteredProducts[index]),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ChatScreen()),
          );
        },
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
        label: const Text(
          'Asistente IA',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }

  Widget _buildProductCard(dynamic product) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProductDetailScreen(productId: product['id']),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              flex: 3,
              child: Container(
                color: AppTheme.bgHover,
                child: ProductImage(
                  imageUrl: product['image_url'],
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      product['name'],
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '\$${(product['effective_price'] ?? product['base_price']).toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: AppTheme.primary,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          backgroundColor: AppTheme.accent,
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  ProductDetailScreen(productId: product['id']),
                            ),
                          );
                        },
                        child: const Text('Ver Detalles'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
