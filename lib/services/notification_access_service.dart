import 'dart:io';

import 'package:flutter/services.dart';

class CapturedNotification {
  final String packageName;
  final String title;
  final String text;
  final DateTime postedAt;

  const CapturedNotification({
    required this.packageName,
    required this.title,
    required this.text,
    required this.postedAt,
  });

  factory CapturedNotification.fromMap(Map<dynamic, dynamic> map) {
    final millis = (map['postedAt'] as num?)?.toInt() ?? 0;
    return CapturedNotification(
      packageName: map['packageName']?.toString() ?? '',
      title: map['title']?.toString() ?? '',
      text: map['text']?.toString() ?? '',
      postedAt: DateTime.fromMillisecondsSinceEpoch(millis),
    );
  }
}

class NotificationAccessService {
  static const MethodChannel _channel = MethodChannel(
    'inc.buddie.memx/device_context',
  );

  Future<bool> isNotificationAccessEnabled() async {
    if (!Platform.isAndroid) return false;
    try {
      final enabled = await _channel.invokeMethod<bool>(
        'isNotificationAccessEnabled',
      );
      return enabled ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> openNotificationAccessSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      final opened = await _channel.invokeMethod<bool>(
        'openNotificationAccessSettings',
      );
      return opened ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<List<CapturedNotification>> getCapturedNotifications({
    int limit = 100,
  }) async {
    if (!Platform.isAndroid) return const [];
    try {
      final list = await _channel.invokeMethod<List<dynamic>>(
        'getCapturedNotifications',
        {'limit': limit},
      );
      if (list == null) return const [];
      return list
          .whereType<Map<dynamic, dynamic>>()
          .map(CapturedNotification.fromMap)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> clearCapturedNotifications() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('clearCapturedNotifications');
    } catch (_) {
      return;
    }
  }
}
