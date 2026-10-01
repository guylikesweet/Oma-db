import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Animated sign-in backdrop: the Omabuy logo and a handful of e-commerce
/// icons (cart, parcel, tag, truck…) drift and tilt slowly across the screen.
/// A translucent wash sits over it so the animation stays in the background
/// and the sign-in card keeps the focus.
class LoginBackground extends StatefulWidget {
  const LoginBackground({super.key});

  @override
  State<LoginBackground> createState() => _LoginBackgroundState();
}

class _Drifter {
  const _Drifter({
    required this.x,
    required this.y,
    required this.size,
    required this.phase,
    required this.fx,
    required this.fy,
    required this.icon,
  });

  /// Resting position as a fraction of the screen (0–1).
  final double x;
  final double y;
  final double size;

  /// Offset in the loop (0–1) so items aren't all moving in step.
  final double phase;

  /// Whole number of back-and-forth swings per loop, so the loop is seamless.
  final int fx;
  final int fy;

  /// null = draw the Omabuy logo.
  final IconData? icon;
}

class _LoginBackgroundState extends State<LoginBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const _items = <_Drifter>[
    _Drifter(x: .12, y: .10, size: 64, phase: .00, fx: 1, fy: 2, icon: null),
    _Drifter(x: .78, y: .08, size: 54, phase: .35, fx: 2, fy: 1, icon: Icons.shopping_cart_outlined),
    _Drifter(x: .45, y: .20, size: 72, phase: .62, fx: 1, fy: 1, icon: null),
    _Drifter(x: .90, y: .30, size: 50, phase: .15, fx: 2, fy: 2, icon: Icons.inventory_2_outlined),
    _Drifter(x: .08, y: .38, size: 52, phase: .80, fx: 1, fy: 2, icon: Icons.local_offer_outlined),
    _Drifter(x: .62, y: .46, size: 60, phase: .28, fx: 2, fy: 1, icon: null),
    _Drifter(x: .25, y: .55, size: 56, phase: .50, fx: 1, fy: 1, icon: Icons.local_shipping_outlined),
    _Drifter(x: .85, y: .62, size: 66, phase: .90, fx: 1, fy: 2, icon: null),
    _Drifter(x: .50, y: .70, size: 52, phase: .08, fx: 2, fy: 2, icon: Icons.shopping_bag_outlined),
    _Drifter(x: .10, y: .78, size: 68, phase: .70, fx: 2, fy: 1, icon: null),
    _Drifter(x: .72, y: .84, size: 54, phase: .42, fx: 1, fy: 1, icon: Icons.payments_outlined),
    _Drifter(x: .38, y: .90, size: 58, phase: .20, fx: 1, fy: 2, icon: Icons.shopping_cart_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 36),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _drifter(_Drifter item, Size area, double t, Color iconColor) {
    final angle = 2 * math.pi * (t + item.phase);

    final dx = math.sin(angle * item.fx) * area.width * .07;
    final dy = math.cos(angle * item.fy) * area.height * .05;
    final tilt = math.sin(angle) * .35;

    final child = item.icon == null
        ? Image.asset(
            'assets/images/app_icon.png',
            width: item.size,
            height: item.size,
            cacheWidth: 192,
            errorBuilder: (_, __, ___) => Icon(
              Icons.storefront,
              size: item.size,
              color: iconColor,
            ),
          )
        : Icon(item.icon, size: item.size, color: iconColor);

    return Positioned(
      left: item.x * area.width - item.size / 2 + dx,
      top: item.y * area.height - item.size / 2 + dy,
      child: Transform.rotate(angle: tilt, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: scheme.surface),
          LayoutBuilder(
            builder: (context, box) {
              final area = Size(box.maxWidth, box.maxHeight);

              return AnimatedBuilder(
                animation: _controller,
                builder: (context, _) => Stack(
                  children: [
                    for (final item in _items)
                      _drifter(
                        item,
                        area,
                        _controller.value,
                        scheme.primary.withOpacity(.55),
                      ),
                  ],
                ),
              );
            },
          ),
          // The fade: keeps the animation soft so the form stands out.
          ColoredBox(color: scheme.surface.withOpacity(.62)),
        ],
      ),
    );
  }
}

/// Makes the sign-in form appear like a popup: it scales up and fades in
/// over the animated background.
class LoginPopIn extends StatelessWidget {
  const LoginPopIn({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Opacity(
        opacity: value.clamp(0.0, 1.0),
        child: Transform.scale(scale: .92 + .08 * value, child: child),
      ),
      child: child,
    );
  }
}
