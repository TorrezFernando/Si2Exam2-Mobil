import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/catalog_service.dart';
import '../../core/services/cart_service.dart';
import '../../core/services/reservation_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/theme/theme.dart';
import '../../core/widgets/product_image.dart';
import '../ar_fitting/ai_tryon_screen.dart';
import '../../core/db/database_helper.dart';
import '../../core/services/mobile_sync_service.dart';

class ProductDetailScreen extends StatefulWidget {
  final int productId;

  const ProductDetailScreen({super.key, required this.productId});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  bool _isLoading = true;
  dynamic _product;
  dynamic _selectedVariant;
  List<dynamic> _inventory = [];
  int _quantity = 1;

  @override
  void initState() {
    super.initState();
    _fetchDetails();
    _registerInteraction();
  }

  Future<void> _registerInteraction() async {
    try {
      final auth = Provider.of<AuthService>(context, listen: false);
      if (auth.token != null) {
        await CatalogService.interactWithProduct(widget.productId);
      }
    } catch (_) {}
  }

  Future<void> _fetchDetails() async {
    try {
      final product = await CatalogService.getProductDetails(widget.productId);
      dynamic variant = (product['variants'] != null && product['variants'].isNotEmpty)
          ? product['variants'][0]
          : null;
      
      if (mounted) {
        setState(() {
          _product = product;
          _selectedVariant = variant;
          _isLoading = false;
        });
      }

      if (variant != null) {
        _loadInventory(variant['id']);
      }
    } catch (e) {
      // Fallback a SQLite local si no hay conexión
      try {
        final db = await DatabaseHelper.instance.database;
        final prods = await db.query('products', where: 'id = ?', whereArgs: [widget.productId]);
        if (prods.isNotEmpty && mounted) {
          final vars = await db.query('variants', where: 'product_id = ?', whereArgs: [widget.productId]);
          final prod = Map<String, dynamic>.from(prods.first);
          prod['variants'] = vars;
          dynamic variant = vars.isNotEmpty ? vars.first : null;
          setState(() {
            _product = prod;
            _selectedVariant = variant;
            _isLoading = false;
          });
          return;
        }
      } catch (_) {}

      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadInventory(int variantId) async {
    try {
      final inv = await CatalogService.getStockByVariant(variantId);
      setState(() {
        _inventory = inv;
        _quantity = 1; // Reset quantity when inventory changes
      });
    } catch (e) {
      // Ignore
    }
  }

  void _updateQuantity(int delta) {
    setState(() {
      final newVal = _quantity + delta;
      if (newVal >= 1) {
        if (_selectedVariant != null && newVal > _totalStock) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Solo hay $_totalStock en stock'), duration: const Duration(seconds: 1)));
          _quantity = _totalStock;
        } else {
          _quantity = newVal;
        }
      }
    });
  }

  int get _totalStock {
    if (_selectedVariant != null && _selectedVariant['stock'] != null) {
      return (_selectedVariant['stock'] as num).toInt();
    }
    if (_inventory.isNotEmpty) {
      return _inventory.fold(0, (sum, inv) => sum + (inv['stock'] as int));
    }
    return 0;
  }

  void _addToCart() {
    if (_product == null) return;
    if (_product['variants'] != null && _product['variants'].isNotEmpty && _selectedVariant == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona una talla/color')));
      return;
    }
    if (_selectedVariant != null && _totalStock == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Este producto está fuera de stock.')));
      return;
    }

    if (_selectedVariant != null && _quantity > _totalStock) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Solo hay $_totalStock disponibles.')));
      return;
    }

    Provider.of<CartService>(context, listen: false).addToCart(_product, _selectedVariant, _quantity);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Se ha añadido al carrito'),
        backgroundColor: AppTheme.success,
        duration: Duration(seconds: 1),
      ),
    );
    setState(() {
      _quantity = 1;
    });
  }

  Future<void> _reserveProduct() async {
    if (_product == null) return;
    if (_product['variants'] != null && _product['variants'].isNotEmpty && _selectedVariant == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Selecciona una talla/color primero')));
      return;
    }

    final auth = Provider.of<AuthService>(context, listen: false);
    final syncService = MobileSyncService.instance;
    final int branchId = auth.currentUser?['branch_id'] ?? 1;
    final int tenantId = auth.currentUser?['tenant_id'] ?? 1;
    final int userId = auth.currentUser?['id'] ?? 1;
    final variantId = _selectedVariant != null ? _selectedVariant['id'] as int : (_product['variants'][0]['id'] as int);
    final unitPrice = (_selectedVariant?['price'] ?? _selectedVariant?['price_override'] ?? _product['base_price'] as num).toDouble();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reservar Prenda'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('¿Reservar $_quantity unidad(es) de "${_product['name']}"?'),
            const SizedBox(height: 8),
            Text(
              syncService.isOffline
                  ? 'Modo Offline: Se reservará localmente en SQLite y se sincronizará al conectar.'
                  : 'Se confirmará la reserva en la sucursal asignada.',
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirmed != true) return;

    final reservationItems = [{
      'variant_id': variantId,
      'quantity': _quantity,
      'unit_price': unitPrice,
      'product_name': _product['name'],
      'variant_label': '${_selectedVariant?['size'] ?? ''} ${_selectedVariant?['color'] ?? ''}'.trim(),
    }];

    if (syncService.isOffline) {
      try {
        await syncService.recordOfflineReservation(
          branchId: branchId,
          tenantId: tenantId,
          userId: userId,
          customerName: auth.currentUser?['full_name'] ?? 'Cliente Móvil',
          notes: 'Reserva directa desde app móvil (Offline)',
          items: reservationItems,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Reserva guardada localmente en SQLite (Offline)'),
              backgroundColor: Colors.amber,
            ),
          );
          setState(() => _quantity = 1);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error al reservar: $e'), backgroundColor: AppTheme.danger),
          );
        }
      }
      return;
    }

    try {
      await ReservationService.createReservation(
        branchId: branchId,
        items: reservationItems,
        notes: 'Reserva desde app móvil',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Reserva creada exitosamente en el servidor'), backgroundColor: AppTheme.success),
        );
        setState(() => _quantity = 1);
      }
    } catch (e) {
      // Fallback a SQLite si falló el transporte de red
      try {
        await syncService.recordOfflineReservation(
          branchId: branchId,
          tenantId: tenantId,
          userId: userId,
          customerName: auth.currentUser?['full_name'] ?? 'Cliente Móvil',
          notes: 'Reserva guardada tras fallo de conexión',
          items: reservationItems,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sin conexión al servidor: Reserva guardada localmente en SQLite'),
              backgroundColor: Colors.amber,
            ),
          );
          setState(() => _quantity = 1);
          return;
        }
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_product == null) return const Scaffold(body: Center(child: Text('Producto no encontrado')));

    final imageUrl = _selectedVariant?['image_url'] ?? _product['image_url'];
    final price = _selectedVariant?['price'] ?? _selectedVariant?['price_override'] ?? _product['base_price'];

    return Scaffold(
      appBar: AppBar(title: Text(_product['name'])),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 300,
              color: AppTheme.bgHover,
              child: ProductImage(
                imageUrl: imageUrl,
                fit: BoxFit.cover,
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_product['name'], style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  Text('\$${price.toStringAsFixed(2)}', style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: AppTheme.primary)),
                  const SizedBox(height: 16),
                  Text(_product['description'] ?? 'Sin descripción', style: const TextStyle(color: AppTheme.textSecondary, height: 1.5)),
                  
                  if (_product['variants'] != null && _product['variants'].isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Text('Variantes', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: (_product['variants'] as List).map((variant) {
                        final isSelected = _selectedVariant != null && _selectedVariant['id'] == variant['id'];
                        return ChoiceChip(
                          label: Text('${variant['size']} - ${variant['color']}'),
                          selected: isSelected,
                          onSelected: (selected) {
                            if (selected) {
                              setState(() => _selectedVariant = variant);
                              _loadInventory(variant['id']);
                            }
                          },
                          selectedColor: AppTheme.primary,
                          backgroundColor: AppTheme.bgCard,
                        );
                      }).toList(),
                    ),
                  ],

                  if (_selectedVariant != null) ...[
                    const SizedBox(height: 24),
                    const Text('Disponibilidad', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 8),
                    if (_inventory.isEmpty)
                      const Text('Consultando inventario...', style: TextStyle(color: AppTheme.textSecondary))
                    else
                      ..._inventory.map((inv) => Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(inv['branch']?['name'] ?? 'Sucursal ${inv['branch_id']}'),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: (inv['stock'] > 0) ? AppTheme.success.withOpacity(0.2) : AppTheme.danger.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    (inv['stock'] > 0) ? '${inv['stock']} en stock' : 'Agotado',
                                    style: TextStyle(color: (inv['stock'] > 0) ? AppTheme.success : AppTheme.danger, fontSize: 12),
                                  ),
                                ),
                              ],
                            ),
                          )),
                  ]
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Botón IA Try-On
              if (_product['image_url'] != null || _product['garment_image_url'] != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Text('✨', style: TextStyle(fontSize: 16)),
                      label: const Text('Pruébatelo con IA'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => AITryonScreen(
                              productId: _product['id'],
                              productName: _product['name'],
                              productImageUrl: _product['garment_image_url'] ?? _product['image_url'],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              // Fila botones Reservar + Añadir al Carrito
              Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: AppTheme.textMuted.withOpacity(0.2)),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove, size: 18),
                          onPressed: () => _updateQuantity(-1),
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          padding: EdgeInsets.zero,
                        ),
                        Text('$_quantity', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        IconButton(
                          icon: const Icon(Icons.add, size: 18),
                          onPressed: () => _updateQuantity(1),
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.accent,
                        side: const BorderSide(color: AppTheme.accent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: (_selectedVariant != null && _totalStock == 0) ? null : _reserveProduct,
                      child: const Text('Reservar', style: TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.accent,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: (_selectedVariant != null && _totalStock == 0) ? null : _addToCart,
                      child: const Text('Añadir al Carrito'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
