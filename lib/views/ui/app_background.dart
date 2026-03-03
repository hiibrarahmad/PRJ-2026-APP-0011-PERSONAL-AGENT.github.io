import 'package:app/controllers/style_controller.dart';
import 'package:app/constants/theme_constants.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AppBackground extends StatefulWidget {
  final Widget? child;

  const AppBackground({super.key, this.child});

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);
    final isLightMode = themeNotifier.mode == Mode.light;
    final topColor = isLightMode
        ? ThemeConstants.primaryDark.withAlpha(82)
        : const Color(0xFF0A1D2C);
    final midColor = isLightMode
        ? ThemeConstants.surface.withAlpha(242)
        : ThemeConstants.surface;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        return Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [topColor, midColor, ThemeConstants.background],
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: _CyberGridPainter(
                  lineColor: ThemeConstants.primary.withAlpha(26),
                ),
              ),
            ),
            Positioned(
              left: -120 + (t * 220),
              top: -80,
              child: _GlowOrb(
                size: 260,
                color: ThemeConstants.neonBlue.withAlpha(50),
              ),
            ),
            Positioned(
              right: -140 + ((1 - t) * 240),
              bottom: -90,
              child: _GlowOrb(
                size: 300,
                color: ThemeConstants.neonMint.withAlpha(40),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: (MediaQuery.of(context).size.height * t) - 70,
              child: IgnorePointer(
                child: Container(
                  height: 2,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        ThemeConstants.primary.withAlpha(130),
                        Colors.transparent,
                      ],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: ThemeConstants.primary.withAlpha(70),
                        blurRadius: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.child != null) widget.child!,
          ],
        );
      },
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withAlpha(0)]),
        ),
      ),
    );
  }
}

class _CyberGridPainter extends CustomPainter {
  final Color lineColor;

  const _CyberGridPainter({required this.lineColor});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.7;

    const spacing = 32.0;
    for (double x = 0; x <= size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _CyberGridPainter oldDelegate) {
    return oldDelegate.lineColor != lineColor;
  }
}
