import 'package:app/controllers/style_controller.dart';
import 'package:app/constants/theme_constants.dart';
import 'package:app/utils/assets_util.dart';
import 'package:app/utils/route_utils.dart';
import 'package:app/views/ui/bud_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../generated/l10n.dart';

class HomeAppBar extends StatelessWidget {
  final GestureTapCallback? onTapLogo;
  final BluetoothConnectionState bluetoothConnected;
  final GestureTapCallback? onTapBluetooth;

  const HomeAppBar({
    super.key,
    this.onTapLogo,
    this.bluetoothConnected = BluetoothConnectionState.disconnected,
    this.onTapBluetooth,
  });

  void _onClickSetting(BuildContext context) {
    context.pushNamed(RouteName.setting);
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);
    bool isLightMode = themeNotifier.mode == Mode.light;
    final isConnected =
        bluetoothConnected == BluetoothConnectionState.connected;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.sp, vertical: 10.sp),
      decoration: BoxDecoration(
        gradient: ThemeConstants.appBarGradient,
        borderRadius: BorderRadius.circular(16.sp),
        border: Border.all(color: ThemeConstants.outline),
        boxShadow: [
          BoxShadow(
            color: ThemeConstants.primary.withAlpha(28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          _buildIconShell(
            onTap: onTapLogo,
            icon: AssetsUtil.icon_chat_logo,
            size: 24.sp,
          ),
          SizedBox(width: 10.sp),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  S.of(context).appName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16.sp,
                    letterSpacing: 0.7,
                    color: isLightMode ? Colors.black : ThemeConstants.text,
                  ),
                ),
                SizedBox(height: 2.sp),
                Text(
                  isConnected ? 'Neural link active' : 'Neural link offline',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 11.sp,
                    color: isConnected
                        ? ThemeConstants.neonMint
                        : ThemeConstants.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          _StatusChip(isConnected: isConnected),
          SizedBox(width: 8.sp),
          _buildIconShell(
            onTap: onTapBluetooth,
            icon: isConnected
                ? AssetsUtil.icon_bluetooth_connected
                : AssetsUtil.icon_bluetooth_disconnected,
            size: 22.sp,
          ),
          SizedBox(width: 8.sp),
          _buildIconShell(
            onTap: () => _onClickSetting(context),
            icon: AssetsUtil.icon_btn_setting,
            size: 22.sp,
          ),
        ],
      ),
    );
  }

  Widget _buildIconShell({
    required String icon,
    required double size,
    GestureTapCallback? onTap,
  }) {
    return InkWell(
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 38.sp,
        height: 38.sp,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: ThemeConstants.panelElevated.withAlpha(210),
          border: Border.all(color: ThemeConstants.outline),
          boxShadow: [
            BoxShadow(
              color: ThemeConstants.primary.withAlpha(38),
              blurRadius: 10,
            ),
          ],
        ),
        child: Center(
          child: BudIcon(icon: icon, size: size),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool isConnected;

  const _StatusChip({required this.isConnected});

  @override
  Widget build(BuildContext context) {
    final color = isConnected
        ? ThemeConstants.neonMint
        : ThemeConstants.warning;
    final text = isConnected ? 'LIVE' : 'IDLE';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      padding: EdgeInsets.symmetric(horizontal: 9.sp, vertical: 5.sp),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withAlpha(28),
        border: Border.all(color: color.withAlpha(180)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10.sp,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9,
        ),
      ),
    );
  }
}
