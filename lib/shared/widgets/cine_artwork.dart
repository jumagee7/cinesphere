import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Artwork image widget for Vyro.
///
/// Tries [imageUrl]; on failure retries it once (transient resets are common
/// while many posters load at once), then falls back to [fallbackUrl], then
/// to a cinematic placeholder card. Successful downloads are served from the
/// memory & disk cache when the card is rebuilt (e.g. on scroll-back).
///
/// Retry is capped at one per URL on purpose: an aggressive remount-retry
/// floods the browser's ~6-connections-per-host queue, and the resulting
/// cancelled loads surface as errors — blanking whole rows on scroll-back.
class CineArtwork extends StatefulWidget {
  final String imageUrl;
  final String? fallbackUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final String? title;
  final IconData icon;

  const CineArtwork({
    super.key,
    required this.imageUrl,
    this.fallbackUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.title,
    this.icon = Icons.movie_rounded,
  });

  static const Map<String, String> _networkHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Accept': 'image/webp,image/apng,image/*,*/*;q=0.8',
  };

  @override
  State<CineArtwork> createState() => _CineArtworkState();
}

class _CineArtworkState extends State<CineArtwork> {
  List<String> _urls = const [];
  int _urlIndex = 0;
  bool _failed = false;
  bool _retriedCurrent = false;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _buildUrlChain();
  }

  @override
  void didUpdateWidget(CineArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl ||
        oldWidget.fallbackUrl != widget.fallbackUrl) {
      _buildUrlChain();
    }
  }

  void _buildUrlChain() {
    _retryTimer?.cancel();
    _urls = [
      widget.imageUrl.trim(),
      if ((widget.fallbackUrl?.trim() ?? '').isNotEmpty &&
          widget.fallbackUrl!.trim() != widget.imageUrl.trim())
        widget.fallbackUrl!.trim(),
    ].where((u) => u.isNotEmpty).toList();
    _urlIndex = 0;
    _retriedCurrent = false;
    _failed = _urls.isEmpty;
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    super.dispose();
  }

  void _onError() {
    if (!mounted || _failed) return;
    if (!_retriedCurrent) {
      // One-shot retry for transient failures (browser connection resets,
      // CDN throttling while many posters load at once).
      _retriedCurrent = true;
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(milliseconds: 700), () {
        if (mounted) setState(() {});
      });
      return;
    }
    if (_urlIndex + 1 < _urls.length) {
      _urlIndex++;
      _retriedCurrent = false;
      setState(() {});
      return;
    }
    setState(() => _failed = true);
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_urls.isEmpty || _failed) {
      content = _buildFallbackCard();
    } else {
      content = CachedNetworkImage(
        // Keyed by URL + retry flag: stable across rebuilds so a recreated
        // card hits the memory cache, but changes once on retry to force a
        // fresh fetch.
        key: ValueKey('${_urls[_urlIndex]}#${_retriedCurrent ? 1 : 0}'),
        imageUrl: _urls[_urlIndex],
        httpHeaders: CineArtwork._networkHeaders,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (_, __) => _buildPlaceholder(),
        errorWidget: (_, __, ___) {
          // Schedule failover after this build passes (no setState during build).
          WidgetsBinding.instance.addPostFrameCallback((_) => _onError());
          return _buildPlaceholder();
        },
      );
    }

    if (widget.borderRadius != null) {
      return ClipRRect(borderRadius: widget.borderRadius!, child: content);
    }
    return content;
  }

  Widget _buildPlaceholder() {
    return Container(
      width: widget.width,
      height: widget.height,
      color: AppColors.surfaceContainerLow,
    );
  }

  Widget _buildFallbackCard() {
    return Container(
      width: widget.width,
      height: widget.height,
      decoration: const BoxDecoration(
        color: AppColors.surfaceContainerLow,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.surfaceContainerHigh,
            AppColors.surfaceContainerLow,
          ],
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(
            widget.icon,
            color: AppColors.outlineVariant.withValues(alpha: 0.5),
            size: (widget.width != null && widget.width! < 80) ? 20 : 34,
          ),
          if (widget.title != null &&
              widget.title!.isNotEmpty &&
              (widget.height == null || widget.height! > 80))
            Positioned(
              bottom: 8,
              left: 6,
              right: 6,
              child: Text(
                widget.title!,
                maxLines: 2,
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.metadata.copyWith(
                  fontSize: 10,
                  color: Colors.white54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
