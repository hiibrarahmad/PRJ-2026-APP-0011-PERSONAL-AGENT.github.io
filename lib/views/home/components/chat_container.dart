import 'package:app/controllers/style_controller.dart';
import 'package:app/constants/theme_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

class ChatContainer extends StatelessWidget {
  final String role;
  final double radius;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final Widget? child;

  const ChatContainer({
    super.key,
    required this.role,
    this.radius = 12,
    this.margin,
    this.padding,
    this.child,
  });

  BoxDecoration _buildDecoration({required bool isLightMode}) {
    final isUser = role == 'user';
    final isAssistant = role == 'assistant';
    final baseColor = isUser
        ? ThemeConstants.primaryDark.withAlpha(150)
        : isAssistant
        ? ThemeConstants.panelElevated.withAlpha(220)
        : ThemeConstants.surface.withAlpha(220);

    final borderColor = isUser
        ? ThemeConstants.neonBlue.withAlpha(190)
        : isAssistant
        ? ThemeConstants.neonMint.withAlpha(130)
        : ThemeConstants.textSecondary.withAlpha(110);

    final gradient = isUser
        ? const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF09839A), Color(0xFF00B8D4), Color(0xFF00D4FF)],
          )
        : LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [baseColor, baseColor.withAlpha(190)],
          );

    return BoxDecoration(
      gradient: gradient,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(width: 0.8, color: borderColor),
      boxShadow: [
        BoxShadow(
          color: borderColor.withAlpha(isUser ? 65 : 45),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);
    bool isLightMode = themeNotifier.mode == Mode.light;
    final decoration = _buildDecoration(isLightMode: isLightMode);
    return Container(
      decoration: decoration,
      margin: margin,
      padding:
          padding ?? EdgeInsets.symmetric(horizontal: 18.sp, vertical: 12.sp),
      child: child,
    );
  }
}
