import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../data/mock_data.dart';
import '../../services/api_service.dart';
import '../constants/api_constants.dart';
import '../../theme/ncst_theme.dart';

class DriverPhotoView extends StatelessWidget {
  final String photoUrl;
  final double size;

  const DriverPhotoView({
    super.key,
    required this.photoUrl,
    this.size = 190,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: NcstColors.slate200,
        border: Border.all(color: NcstColors.slate200, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildPhotoContent(),
    );
  }

  Widget _buildPhotoContent() {
    final raw = photoUrl.trim();
    if (raw.isEmpty) {
      return _buildPlaceholderPhoto();
    }

    // Dynamic cache target dimensions: decode at 2x logical size for crisp retina display
    // while preventing large raw camera images (4K/12MP) from occupying 30-50MB of RAM each.
    final targetPixelSize = (size * 2).round().clamp(80, 400);

    // 1. Decode Base64 data URL (e.g. data:image/png;base64,... or raw base64)
    if (raw.startsWith('data:image/') ||
        raw.startsWith('/9j/') ||
        raw.startsWith('iVBORw') ||
        (raw.length > 200 && !raw.startsWith('http') && !raw.startsWith('assets/'))) {
      try {
        final commaIdx = raw.indexOf(',');
        final base64Str = commaIdx != -1 ? raw.substring(commaIdx + 1) : raw;
        final cleanBase64 = base64Str.trim().replaceAll('\n', '').replaceAll('\r', '').replaceAll(' ', '+');
        final padded = cleanBase64.padRight((cleanBase64.length + 3) ~/ 4 * 4, '=');
        final bytes = base64Decode(padded);
        return Image.memory(
          bytes,
          cacheWidth: targetPixelSize,
          cacheHeight: targetPixelSize,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildPlaceholderPhoto(),
        );
      } catch (_) {
        return _buildPlaceholderPhoto();
      }
    }

    // 2. Bundled Flutter asset
    if (raw.startsWith('assets/')) {
      return Image.asset(
        raw,
        cacheWidth: targetPixelSize,
        cacheHeight: targetPixelSize,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _buildPlaceholderPhoto(),
      );
    }

    // 3. Web server network image (HTTP/HTTPS or relative server path)
    final resolvedUrl = ApiConstants.resolveImageUrl(raw);
    if (MockData.useNetworkImages && (resolvedUrl.startsWith('http://') || resolvedUrl.startsWith('https://'))) {
      return Image.network(
        resolvedUrl,
        headers: ApiService.imageHeaders,
        cacheWidth: targetPixelSize,
        cacheHeight: targetPixelSize,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return Container(
            color: NcstColors.slate100,
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: const AlwaysStoppedAnimation<Color>(NcstColors.navy),
                value: progress.expectedTotalBytes != null
                    ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                    : null,
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) {
          // If Image.network fails (e.g. anti-bot challenge on InfinityFree),
          // fallback to ApiService byte fetcher which solves the challenge
          return _NetworkImageWithFallback(
            url: resolvedUrl,
            width: size,
            height: size,
            fallback: _buildPlaceholderPhoto(),
          );
        },
      );
    }

    return _buildPlaceholderPhoto();
  }

  Widget _buildPlaceholderPhoto() {
    return Container(
      color: NcstColors.slate100,
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NcstColors.navy.withValues(alpha: 0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.person, size: 54, color: NcstColors.navy),
        ),
      ),
    );
  }
}

class VehiclePhotoThumb extends StatelessWidget {
  final String photoData;
  final double width;
  final double height;

  const VehiclePhotoThumb({
    super.key,
    required this.photoData,
    this.width = 64,
    this.height = 48,
  });

  @override
  Widget build(BuildContext context) {
    final raw = photoData.trim();
    Widget content;
    final targetW = (width * 2).round().clamp(60, 240);
    final targetH = (height * 2).round().clamp(48, 240);

    if (raw.startsWith('data:image/') ||
        raw.startsWith('/9j/') ||
        raw.startsWith('iVBORw') ||
        (raw.length > 100 && !raw.startsWith('http') && !raw.startsWith('assets/'))) {
      try {
        final commaIdx = raw.indexOf(',');
        final base64Str = commaIdx != -1 ? raw.substring(commaIdx + 1) : raw;
        final cleanBase64 = base64Str.trim().replaceAll('\n', '').replaceAll('\r', '').replaceAll(' ', '+');
        final padded = cleanBase64.padRight((cleanBase64.length + 3) ~/ 4 * 4, '=');
        final bytes = base64Decode(padded);
        content = Image.memory(
          bytes,
          width: width,
          height: height,
          cacheWidth: targetW,
          cacheHeight: targetH,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _fallback(),
        );
      } catch (_) {
        content = _fallback();
      }
    } else if (raw.startsWith('assets/')) {
      content = Image.asset(
        raw,
        width: width,
        height: height,
        cacheWidth: targetW,
        cacheHeight: targetH,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => _fallback(),
      );
    } else {
      final resolvedUrl = ApiConstants.resolveImageUrl(raw);
      if (MockData.useNetworkImages && (resolvedUrl.startsWith('http://') || resolvedUrl.startsWith('https://'))) {
        content = Image.network(
          resolvedUrl,
          headers: ApiService.imageHeaders,
          width: width,
          height: height,
          cacheWidth: targetW,
          cacheHeight: targetH,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _NetworkImageWithFallback(
              url: resolvedUrl,
              width: width,
              height: height,
              fallback: _fallback(),
            );
          },
        );
      } else {
        content = _fallback();
      }
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: NcstColors.slate100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: NcstColors.slate200),
      ),
      clipBehavior: Clip.antiAlias,
      child: content,
    );
  }

  Widget _fallback() {
    return Container(
      color: NcstColors.slate100,
      child: const Center(
        child: Icon(Icons.directions_car, size: 22, color: NcstColors.slate400),
      ),
    );
  }
}

/// Fallback widget that fetches image bytes using ApiService (solving anti-bot challenges if needed)
class _NetworkImageWithFallback extends StatefulWidget {
  final String url;
  final Widget fallback;
  final double? width;
  final double? height;

  const _NetworkImageWithFallback({
    required this.url,
    required this.fallback,
    this.width,
    this.height,
  });

  @override
  State<_NetworkImageWithFallback> createState() => _NetworkImageWithFallbackState();
}

class _NetworkImageWithFallbackState extends State<_NetworkImageWithFallback> {
  Uint8List? _bytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  void _loadImage() async {
    final bytes = await ApiService.fetchImageBytes(widget.url);
    if (mounted) {
      setState(() {
        _bytes = bytes;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Container(
        color: NcstColors.slate100,
        child: const Center(
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2, color: NcstColors.navy),
          ),
        ),
      );
    }
    if (_bytes != null) {
      final targetW = widget.width != null ? (widget.width! * 2).round().clamp(60, 400) : 380;
      final targetH = widget.height != null ? (widget.height! * 2).round().clamp(48, 400) : 380;
      return Image.memory(
        _bytes!,
        width: widget.width,
        height: widget.height,
        cacheWidth: targetW,
        cacheHeight: targetH,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => widget.fallback,
      );
    }
    return widget.fallback;
  }
}
