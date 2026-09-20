import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/api_service.dart';
import '../theme/theme.dart';

class ProductImage extends StatelessWidget {
  final String? imageUrl;
  final BoxFit fit;

  const ProductImage({
    Key? key,
    this.imageUrl,
    this.fit = BoxFit.cover,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return _buildPlaceholder();
    }

    // Si es Base64
    if (imageUrl!.startsWith('data:image')) {
      try {
        final commaIndex = imageUrl!.indexOf(',');
        final base64String = imageUrl!.substring(commaIndex + 1);
        final bytes = base64Decode(base64String);
        return Image.memory(
          bytes,
          fit: fit,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
        );
      } catch (e) {
        return _buildPlaceholder();
      }
    }

    final fullUrl = ApiService.getFullImageUrl(imageUrl!);

    // Si es SVG
    if (fullUrl.toLowerCase().endsWith('.svg')) {
      return SvgPicture.network(
        fullUrl,
        fit: fit,
        placeholderBuilder: (BuildContext context) => const Center(
          child: CircularProgressIndicator(color: AppTheme.primary),
        ),
      );
    }

    // Imagen normal
    return Image.network(
      fullUrl,
      fit: fit,
      errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
    );
  }

  Widget _buildPlaceholder() {
    return const Center(
      child: Icon(Icons.image, size: 48, color: AppTheme.textMuted),
    );
  }
}
