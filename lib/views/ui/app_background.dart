import 'package:app/controllers/style_controller.dart';
import 'package:app/constants/theme_constants.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AppBackground extends StatelessWidget {
  final Widget? child;

  const AppBackground({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);
    final isLightMode = themeNotifier.mode == Mode.light;
    final topColor = isLightMode
        ? ThemeConstants.primaryDark.withAlpha(84)
        : ThemeConstants.primaryDark.withAlpha(56);
    final midColor = isLightMode
        ? ThemeConstants.surface.withAlpha(245)
        : ThemeConstants.surface;

    return Stack(
      children: [
        Container(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          decoration: const BoxDecoration(color: ThemeConstants.background),
        ),
        Container(
          width: MediaQuery.of(context).size.width,
          height: MediaQuery.of(context).size.height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [topColor, midColor, ThemeConstants.background],
            ),
          ),
        ),
        if (child != null) child!,
      ],
    );
  }
}
