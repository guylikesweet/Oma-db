import 'package:flutter/material.dart';

/// The OmaSales logo, gently breathing (scale + fade) with a soft rotating
/// ring behind it, in place of a bare spinner. Drop this in wherever the app
/// currently shows `Center(child: CircularProgressIndicator())` for a
/// full-page loading state — a slow connection then shows *the logo*
/// working on it, rather than a blank page with a generic dot.
///
/// Usage: `const Center(child: BrandLoader())` — same call shape as the
/// spinner it replaces.
class BrandLoader extends StatefulWidget {
  const BrandLoader({super.key, this.size = 84, this.label});

  /// Overall footprint (ring + logo). The logo itself renders a bit
  /// smaller than this so the ring has room to show around it.
  final double size;

  /// Optional caption shown under the mark, e.g. "Loading…" or
  /// "Connecting…" — omit for a bare mark.
  final String? label;

  @override
  State<BrandLoader> createState() => _BrandLoaderState();
}

class _BrandLoaderState extends State<BrandLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  late final Animation<double> _scale = Tween(
    begin: 0.86,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  late final Animation<double> _fade = Tween(
    begin: 0.55,
    end: 1.0,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // The green from the logo's cart/wordmark — used for the ring so it reads
  // as "the logo's own halo" rather than an unrelated theme color.
  static const _ringColor = Color(0xFF039664);

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: widget.size,
                height: widget.size,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: const AlwaysStoppedAnimation(_ringColor),
                  backgroundColor: _ringColor.withOpacity(0.12),
                ),
              ),
              FadeTransition(
                opacity: _fade,
                child: ScaleTransition(
                  scale: _scale,
                  child: Image.asset(
                    'assets/images/app_icon.png',
                    width: widget.size * 0.6,
                    height: widget.size * 0.6,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.label != null) ...[
          const SizedBox(height: 14),
          Text(
            widget.label!,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withOpacity(0.65),
                ),
          ),
        ],
      ],
    );
  }
}

/// A translucent scrim + [BrandLoader], for stacking on top of content
/// that's already on screen while an action is in flight (saving, syncing,
/// submitting) — as opposed to [BrandLoader] alone, which is for replacing
/// a page body that hasn't loaded anything yet.
///
/// Usage: wrap the page's body in a `Stack` and add this as the last child,
/// shown only while busy:
/// ```dart
/// Stack(
///   children: [
///     yourPageContent,
///     if (saving) const BrandLoadingOverlay(),
///   ],
/// )
/// ```
class BrandLoadingOverlay extends StatelessWidget {
  const BrandLoadingOverlay({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withOpacity(0.15),
        child: Center(child: BrandLoader(label: label)),
      ),
    );
  }
}
