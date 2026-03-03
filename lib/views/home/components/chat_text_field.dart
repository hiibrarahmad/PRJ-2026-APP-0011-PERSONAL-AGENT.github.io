import 'package:app/controllers/style_controller.dart';
import 'package:app/constants/theme_constants.dart';
import 'package:app/utils/assets_util.dart';
import 'package:app/views/ui/bud_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

import '../../../generated/l10n.dart';

class ChatTextField extends StatelessWidget {
  final FocusNode? focusNode;
  final TextEditingController? controller;

  final ValueChanged<String>? onSubmitted;
  final GestureTapCallback? onTapKeyboard;
  final GestureTapCallback? onTapSend;

  const ChatTextField({
    super.key,
    this.focusNode,
    this.controller,
    this.onSubmitted,
    this.onTapKeyboard,
    this.onTapSend,
  });

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);
    bool isLightMode = themeNotifier.mode == Mode.light;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16.sp),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            ThemeConstants.panel.withAlpha(220),
            ThemeConstants.panelElevated.withAlpha(210),
          ],
        ),
        border: Border.all(
          color: isLightMode
              ? Colors.white.withAlpha(140)
              : ThemeConstants.neonBlue.withAlpha(110),
          width: 0.85,
        ),
        boxShadow: [
          BoxShadow(
            color: ThemeConstants.primary.withAlpha(24),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: EdgeInsets.only(left: 10.sp, right: 10.sp, top: 4.sp),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 13.sp),
            child: InkWell(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              onTap: onTapKeyboard,
              child: Container(
                width: 32.sp,
                height: 32.sp,
                decoration: BoxDecoration(
                  color: ThemeConstants.panel,
                  borderRadius: BorderRadius.circular(10.sp),
                  border: Border.all(color: ThemeConstants.outline),
                ),
                child: const Center(
                  child: BudIcon(icon: AssetsUtil.icon_keyboard, size: 18),
                ),
              ),
            ),
          ),
          SizedBox(width: 12.sp),
          Expanded(
            child: TextField(
              focusNode: focusNode,
              controller: controller,
              onSubmitted: onSubmitted,
              minLines: 1,
              maxLines: 9,
              textInputAction: TextInputAction.send,
              style: TextStyle(
                fontSize: 14.sp,
                fontWeight: FontWeight.w500,
                color: isLightMode ? Colors.black : ThemeConstants.text,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: S.of(context).pageHomeTextFieldHint,
                hintStyle: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13.sp,
                  color: isLightMode
                      ? const Color(0xFF999999)
                      : ThemeConstants.textSecondary,
                ),
              ),
            ),
          ),
          SizedBox(width: 12.sp),
          Padding(
            padding: EdgeInsets.only(bottom: 8.sp),
            child: InkWell(
              splashColor: Colors.transparent,
              highlightColor: Colors.transparent,
              onTap: onTapSend,
              child: Container(
                width: 34.sp,
                height: 34.sp,
                decoration: BoxDecoration(
                  gradient: ThemeConstants.primaryGlowGradient,
                  borderRadius: BorderRadius.circular(12.sp),
                  boxShadow: [
                    BoxShadow(
                      color: ThemeConstants.primary.withAlpha(95),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Center(
                  child: BudIcon(icon: AssetsUtil.icon_send_message, size: 18),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
