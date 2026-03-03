import 'package:app/controllers/style_controller.dart';
import 'package:app/constants/theme_constants.dart';
import 'package:app/utils/assets_util.dart';
import 'package:app/views/home/components/chat_container.dart';
import 'package:app/views/ui/bud_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';

class ChatListTile extends StatelessWidget {
  final String role;
  final String text;
  final TextStyle? style;
  final EdgeInsetsGeometry? padding;
  final GestureLongPressCallback? onLongPress;

  const ChatListTile({
    super.key,
    required this.role,
    required this.text,
    this.style,
    this.padding,
    this.onLongPress,
  });

  static final double _iconSize = 24.sp;
  static final double _iconRight = 8.sp;
  static final double _containMarginHorizontal = 16.sp;
  static final double textWidthSpace =
      _iconSize + _iconRight + _containMarginHorizontal;

  static EdgeInsets _getChatContainerMargin(String role) {
    bool isUser = role == 'user';
    EdgeInsets margin = EdgeInsets.only(
      left: isUser ? (_iconSize + _iconRight + _containMarginHorizontal) : 0,
      right: isUser ? 0 : _containMarginHorizontal,
    );
    return margin;
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);
    bool isLightMode = themeNotifier.mode == Mode.light;
    bool isUser = role == 'user';
    bool isAssistant = role == 'assistant';
    TextStyle textStyle =
        style ?? const TextStyle(fontWeight: FontWeight.w600, fontSize: 14);
    final bubbleTextColor = isUser
        ? ThemeConstants.text
        : ThemeConstants.text.withAlpha(230);
    final maxWidth = MediaQuery.of(context).size.width * 0.76;

    return Row(
      mainAxisAlignment: isUser
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isUser)
          Padding(
            padding: EdgeInsets.only(right: _iconRight),
            child: Container(
              width: _iconSize + 10.sp,
              height: _iconSize + 10.sp,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: ThemeConstants.panelElevated,
                border: Border.all(
                  color:
                      (isAssistant
                              ? ThemeConstants.neonMint
                              : ThemeConstants.neonBlue)
                          .withAlpha(155),
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        (isAssistant
                                ? ThemeConstants.neonMint
                                : ThemeConstants.neonBlue)
                            .withAlpha(45),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: Center(
                child: BudIcon(
                  icon: isAssistant
                      ? AssetsUtil.icon_chat_logo
                      : AssetsUtil.icon_chat_meeting,
                  size: _iconSize,
                ),
              ),
            ),
          ),
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: GestureDetector(
            onLongPress: onLongPress,
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    bottom: 4.sp,
                    left: isUser ? 0 : 4.sp,
                    right: isUser ? 4.sp : 0,
                  ),
                  child: Text(
                    isUser ? 'YOU' : (isAssistant ? 'I.A AGENT' : 'TRANSCRIPT'),
                    style: TextStyle(
                      color: ThemeConstants.textSecondary,
                      fontSize: 10.sp,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                ChatContainer(
                  role: role,
                  margin: _getChatContainerMargin(role),
                  padding:
                      padding ??
                      EdgeInsets.symmetric(horizontal: 18.sp, vertical: 12.sp),
                  child: Text(
                    text,
                    style: textStyle.copyWith(
                      height: 1.4,
                      color: isLightMode
                          ? const Color(0xFF1D1F23)
                          : bubbleTextColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
