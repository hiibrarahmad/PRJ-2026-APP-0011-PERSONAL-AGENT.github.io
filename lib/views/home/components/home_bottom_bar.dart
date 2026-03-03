import 'package:app/views/home/components/chat_bottom_buttons.dart';
import 'package:app/views/home/components/chat_text_field.dart';
import 'package:app/constants/theme_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class HomeBottomBar extends StatelessWidget {
  final FocusNode? focusNode;
  final TextEditingController? controller;
  final ValueChanged<String>? onSubmitted;

  final GestureTapCallback? onTapSend;
  final GestureTapCallback? onTapKeyboard;
  final GestureTapCallback? onTapAsrMode;

  final GestureTapCallback? onTapLeft;
  final GestureTapCallback? onTapHelp;
  final GestureTapCallback? onTapRight;

  final bool isRecording;
  final ValueNotifier<bool> isSpeakValueNotifier;

  const HomeBottomBar({
    super.key,
    this.focusNode,
    this.controller,
    this.onSubmitted,
    this.onTapSend,
    this.onTapKeyboard,
    this.onTapAsrMode,
    this.onTapLeft,
    this.onTapHelp,
    this.onTapRight,
    required this.isRecording,
    required this.isSpeakValueNotifier,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(8.sp, 10.sp, 8.sp, 8.sp),
      decoration: BoxDecoration(
        color: ThemeConstants.panel.withAlpha(196),
        borderRadius: BorderRadius.circular(20.sp),
        border: Border.all(color: ThemeConstants.outline),
        boxShadow: [
          BoxShadow(
            color: ThemeConstants.primary.withAlpha(38),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ChatTextField(
            focusNode: focusNode,
            controller: controller,
            onTapKeyboard: onTapKeyboard,
            onSubmitted: onSubmitted,
            onTapSend: onTapSend,
          ),
          SizedBox(height: 10.sp),
          if (onTapAsrMode != null)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 6.sp),
              child: GestureDetector(
                onTap: onTapAsrMode,
                child: Container(
                  width: double.infinity,
                  height: 34.sp,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        ThemeConstants.primary.withAlpha(32),
                        ThemeConstants.accent.withAlpha(32),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: ThemeConstants.neonBlue.withAlpha(128),
                      width: 0.9,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.mic_external_on,
                        size: 15.sp,
                        color: ThemeConstants.neonBlue,
                      ),
                      SizedBox(width: 8.sp),
                      Text(
                        'Switch ASR mode',
                        style: TextStyle(
                          fontSize: 12.sp,
                          color: ThemeConstants.neonBlue,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (onTapAsrMode != null) SizedBox(height: 10.sp),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 4.sp),
            child: ChatBottomButtons(
              onTapLeft: onTapLeft,
              onTapHelp: onTapHelp,
              onTapRight: onTapRight,
              isRecording: isRecording,
              isSpeakValueNotifier: isSpeakValueNotifier,
            ),
          ),
        ],
      ),
    );
  }
}
