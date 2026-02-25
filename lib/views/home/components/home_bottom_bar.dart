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
    return Column(
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
        SizedBox(height: 8.sp),
        if (onTapAsrMode != null)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.sp),
            child: GestureDetector(
              onTap: onTapAsrMode,
              child: Container(
                width: double.infinity,
                height: 36.sp,
                decoration: BoxDecoration(
                  color: ThemeConstants.primary.withAlpha(26),
                  borderRadius: BorderRadius.circular(18.sp),
                  border: Border.all(
                    color: ThemeConstants.primary.withAlpha(90),
                    width: 1,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.mic_external_on,
                      size: 16.sp,
                      color: ThemeConstants.primary,
                    ),
                    SizedBox(width: 8.sp),
                    Text(
                      'Switch ASR mode',
                      style: TextStyle(
                        fontSize: 14.sp,
                        color: ThemeConstants.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (onTapAsrMode != null) SizedBox(height: 8.sp),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.sp),
          child: ChatBottomButtons(
            onTapLeft: onTapLeft,
            onTapHelp: onTapHelp,
            onTapRight: onTapRight,
            isRecording: isRecording,
            isSpeakValueNotifier: isSpeakValueNotifier,
          ),
        ),
      ],
    );
  }
}
