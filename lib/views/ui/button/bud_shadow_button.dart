import 'package:app/controllers/style_controller.dart';
import 'package:app/constants/theme_constants.dart';
import 'package:app/views/ui/bud_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

class BudShadowButton extends StatelessWidget {
  final String icon;
  final String? text;
  final GestureTapCallback? onTap;

  const BudShadowButton({super.key, required this.icon, this.text, this.onTap});

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);
    bool isLightMode = themeNotifier.mode == Mode.light;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        shape: text == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: text != null ? BorderRadius.circular(18.sp) : null,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ThemeConstants.panel.withAlpha(220),
            ThemeConstants.panelElevated.withAlpha(220),
          ],
        ),
        border: Border.all(
          color: isLightMode
              ? Colors.white.withAlpha(140)
              : ThemeConstants.neonBlue.withAlpha(130),
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: ThemeConstants.primary.withAlpha(40),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: InkWell(
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        borderRadius: text != null ? BorderRadius.circular(18.sp) : null,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 14.sp, vertical: 12.sp),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              BudIcon(icon: icon, size: 22.sp),
              if (text != null)
                Padding(
                  padding: EdgeInsets.only(left: 8.sp),
                  child: Text(
                    text!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.sp,
                      letterSpacing: 0.5,
                      color: isLightMode
                          ? const Color(0xFF333333)
                          : ThemeConstants.text,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
