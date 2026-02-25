import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../constants/theme_constants.dart';
import '../../generated/l10n.dart';

class NotPairedNotice extends StatelessWidget {
  const NotPairedNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: EdgeInsets.all(20.sp),
        padding: EdgeInsets.all(20.sp),
        decoration: BoxDecoration(
          color: ThemeConstants.card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(70),
              blurRadius: 10.sp,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              S.of(context).notPairedNoticeText1,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20.sp,
                fontWeight: FontWeight.bold,
                color: ThemeConstants.text,
              ),
            ),
            SizedBox(height: 12.sp),
            Text(
              S.of(context).notPairedNoticeText2,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18.sp,
                height: 1.4,
                color: ThemeConstants.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
