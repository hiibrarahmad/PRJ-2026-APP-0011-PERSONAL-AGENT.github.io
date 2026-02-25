import 'dart:io';

import 'package:flutter/services.dart';

class HeadsetStatus {
  final bool connected;
  final String? name;
  final List<String> devices;
  final bool bluetoothEnabled;
  final bool routedToBluetooth;
  final String reason;

  const HeadsetStatus({
    required this.connected,
    required this.name,
    required this.devices,
    required this.bluetoothEnabled,
    required this.routedToBluetooth,
    required this.reason,
  });

  factory HeadsetStatus.fromMap(Map<dynamic, dynamic> map) {
    return HeadsetStatus(
      connected: map['connected'] == true,
      name: map['name']?.toString(),
      devices: (map['devices'] as List<dynamic>? ?? const [])
          .map((e) => e.toString())
          .toList(),
      bluetoothEnabled: map['bluetoothEnabled'] == true,
      routedToBluetooth: map['routedToBluetooth'] == true,
      reason: map['reason']?.toString() ?? 'unknown',
    );
  }
}

class HeadsetStatusService {
  static const MethodChannel _channel = MethodChannel(
    'inc.buddie.memx/headset',
  );

  static Future<HeadsetStatus?> getStatus() async {
    if (!Platform.isAndroid) return null;
    try {
      final map = await _channel.invokeMethod<Map<dynamic, dynamic>>(
        'getHeadsetStatus',
      );
      if (map == null) return null;
      return HeadsetStatus.fromMap(map);
    } catch (_) {
      return null;
    }
  }
}
