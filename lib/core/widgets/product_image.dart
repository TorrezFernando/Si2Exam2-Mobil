import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../services/api_service.dart';
import '../theme/theme.dart';

class ProductImage extends StatelessWidget {
  final String? imageUrl;
  final BoxFit? fit;
  final double? width;
  final double? height;

  const ProductImage({
    super.key,
    this.imageUrl,
    this.fit,
    this.width,
    this.height,
  });

  @override
  Widget build(BuildContext context) {
    if (imageUrl == null || imageUrl!.isEmpty) {
      return Container(
        width: width,
        height: height,
        color: AppTheme.bgCard,
        child: const Icon(Icons.image, size: 48, color: AppTheme.textMuted),
      );
    }

    if (imageUrl!.startsWith('data:image')) {
      try {
        final commaIndex = imageUrl!.indexOf(',');
        final base64String = imageUrl!.substring(commaIndex + 1);
        return Image.memory(
          base64Decode(base64String),
          fit: fit ?? BoxFit.cover,
          width: width,
          height: height,
        );
      } catch (e) {
        return Container(
          width: width,
          height: height,
          color: AppTheme.bgCard,
          child: const Icon(Icons.error, color: AppTheme.danger),
        );
      }
    }

    final fullUrl = ApiService.getFullImageUrl(imageUrl!);

    // Soporte para imágenes SVG (usado en los placeholders de la BD)
    if (fullUrl.toLowerCase().endsWith('.svg')) {
      return SvgPicture.network(
        fullUrl,
        fit: fit ?? BoxFit.cover,
        width: width,
        height: height,
        placeholderBuilder: (BuildContext context) => Container(
          color: AppTheme.bgCard,
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    // Imagen normal (PNG, JPG, WebP)
    return Image.network(
      fullUrl,
      fit: fit ?? BoxFit.cover,
      width: width,
      height: height,
      errorBuilder: (context, error, stackTrace) {
        return Container(
          width: width,
          height: height,
          color: AppTheme.bgCard,
          child: const Icon(Icons.image, size: 48, color: AppTheme.textMuted),
        );
      },
    );
  }
}
