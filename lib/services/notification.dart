import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../main.dart';

const int summaryNotificationId = 100;

AndroidNotificationDetails taskChannel = AndroidNotificationDetails(
  'task_channel',
  'messages',
  importance: Importance.max,
  priority: Priority.max,
  enableVibration: true,
  playSound: true,
  when: DateTime.now().millisecondsSinceEpoch,
  showWhen: true,
);

Future<void> showNotificationOfSummaryStarted() async {
  const DarwinNotificationDetails iosPlatformChannelSpecifics =
      DarwinNotificationDetails();
  NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: taskChannel,
    iOS: iosPlatformChannelSpecifics,
  );

  await flutterLocalNotificationsPlugin.show(
    summaryNotificationId,
    'I.A agent',
    'Generating your meeting summary...',
    platformChannelSpecifics,
  );
}

Future<void> showNotificationOfSummaryFinished() async {
  const DarwinNotificationDetails iosPlatformChannelSpecifics =
      DarwinNotificationDetails();
  NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: taskChannel,
    iOS: iosPlatformChannelSpecifics,
  );

  await flutterLocalNotificationsPlugin.show(
    summaryNotificationId,
    'I.A agent',
    'Your meeting summary has been finished.',
    platformChannelSpecifics,
  );
}

Future<void> showNotificationOfSummaryFailed() async {
  const DarwinNotificationDetails iosPlatformChannelSpecifics =
      DarwinNotificationDetails();
  NotificationDetails platformChannelSpecifics = NotificationDetails(
    android: taskChannel,
    iOS: iosPlatformChannelSpecifics,
  );

  await flutterLocalNotificationsPlugin.show(
    summaryNotificationId,
    'I.A agent',
    "There's an error during generating your meeting summary.",
    platformChannelSpecifics,
  );
}
