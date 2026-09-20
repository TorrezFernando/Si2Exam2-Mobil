import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/catalog_service.dart';
import '../../core/services/cart_service.dart';
import '../../core/services/api_service.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/product_image.dart';
import '../cart/cart_screen.dart';
import '../reservations/reservation_screen.dart';
import 'product_detail_screen.dart';
import '../chat/chat_screen.dart';

class CatalogScreen extends StatefulWidget {
  const CatalogScreen({super.key});

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  List<dynamic> _products = [];
  List<dynamic> _filteredProducts = [];
  List<dynamic> _recommendedProducts = [];
  bool _isLoading = true;
  bool _isLoadingRecommended = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchProducts();
    _searchController.addListener(_onSearchChanged);
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



  Future<void> _fetchProducts() async {
    try {
      final products = await CatalogService.getProducts();
      
      List<dynamic> recommended = [];
      final auth = Provider.of<AuthService>(context, listen: false);
      if (auth.token != null) {
        try {
          recommended = await CatalogService.getRecommendedProducts(limit: 4);
        } catch (_) {}
      }

      setState(() {
        _products = products;
        _filteredProducts = products;
        _recommendedProducts = recommended;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error cargando el catálogo')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartService>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Catálogo Exclusivo'),
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            tooltip: 'Mis Reservas',
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const ReservationScreen()));
            },
          ),
          IconButton(
            icon: Badge(
              label: Text(cart.totalItemsCount.toString()),
              isLabelVisible: cart.totalItemsCount > 0,
              child: const Icon(Icons.shopping_cart),
            ),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CartScreen()));
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppTheme.danger),
            onPressed: () => Provider.of<AuthService>(context, listen: false).logout(),
          ),
        ],
      ),
      body: Column(
        children: [
          // Barra de búsqueda
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Buscar productos...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear), onPressed: () { _searchController.clear(); })
                    : null,
                filled: true,
                fillColor: AppTheme.bgCard,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
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
                              _searchController.text.isEmpty ? 'No hay productos disponibles' : 'Sin resultados para "${_searchController.text}"',
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        children: [
                          if (_searchController.text.isEmpty && _recommendedProducts.isNotEmpty) ...[
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                              child: Text('✨ Para Ti', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            ),
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  childAspectRatio: 0.48,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                ),
                              itemCount: _recommendedProducts.length,
                              itemBuilder: (context, index) => _buildProductCard(_recommendedProducts[index]),
                            ),
                            const Padding(
                              padding: EdgeInsets.fromLTRB(16, 24, 16, 8),
                              child: Text('Todos los Productos', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                            ),
                          ],
                          GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            padding: EdgeInsets.symmetric(horizontal: 16, vertical: _searchController.text.isEmpty && _recommendedProducts.isNotEmpty ? 0 : 16),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2,
                              childAspectRatio: 0.48,
                              crossAxisSpacing: 16,
                              mainAxisSpacing: 16,
                            ),
                            itemCount: _filteredProducts.length,
                            itemBuilder: (context, index) => _buildProductCard(_filteredProducts[index]),
                          ),
                        ],
                      ),
          ),
        ],
      ),
      floatingActionButton: Provider.of<AuthService>(context).token != null ? FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const ChatScreen()));
        },
        backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.chat_bubble_outline, color: Colors.white),
        label: const Text('Asistente IA', style: TextStyle(color: Colors.white)),
      ) : null,
    );
  }

  Widget _buildProductCard(dynamic product) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: product['id'])));
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
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '\$${product['base_price'].toStringAsFixed(2)}',
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
                           Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: product['id'])));
                        },
                        child: const Text('Ver Detalles'),
                      ),
                    )
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
