import 'dart:convert';
import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notification_access_service.dart';

class PersonalAssistantService {
  static const _locationTrackKey = 'ia_location_track_v1';
  static const _reminderTrackKey = 'ia_reminder_track_v1';
  static const _alarmTrackKey = 'ia_alarm_track_v1';
  static const _safeAlarmWindowDays = 7;

  final DeviceCalendarPlugin _calendarPlugin = DeviceCalendarPlugin();
  final NotificationAccessService _notificationAccessService =
      NotificationAccessService();

  Future<String?> tryHandleCommand(String input) async {
    final normalized = input.trim().toLowerCase();
    if (normalized.isEmpty) return null;

    if (_isDailyBriefCommand(normalized)) {
      return _buildTodayBriefing();
    }
    if (_isCalendarReadCommand(normalized)) {
      return _buildCalendarAgenda();
    }
    if (_isReminderCommand(normalized)) {
      return _createReminder(input);
    }
    if (_isAlarmCommand(normalized)) {
      return _createAlarm(input);
    }
    if (_isNotificationAccessCommand(normalized)) {
      return _openNotificationAccessSettings();
    }
    if (_isPermissionStatusCommand(normalized)) {
      return _buildPermissionStatusReport();
    }
    if (_isNotificationSummaryCommand(normalized)) {
      return _buildNotificationSummary();
    }
    return null;
  }

  bool _isDailyBriefCommand(String text) {
    return _containsAny(text, [
      'what happened today',
      'what happen today',
      'today summary',
      'daily summary',
      'daily brief',
      'what did i do today',
      'brief me on today',
    ]);
  }

  bool _isCalendarReadCommand(String text) {
    if (!text.contains('calendar') && !text.contains('agenda')) return false;
    return _containsAny(text, ['today', 'schedule', 'events', 'read']);
  }

  bool _isReminderCommand(String text) {
    return _containsAny(text, [
      'set reminder',
      'set a reminder',
      'remind me',
      'create reminder',
    ]);
  }

  bool _isAlarmCommand(String text) {
    return _containsAny(text, [
      'set alarm',
      'set an alarm',
      'alarm for',
      'wake me',
    ]);
  }

  bool _isNotificationAccessCommand(String text) {
    return _containsAny(text, [
      'enable notification access',
      'notification access settings',
      'open notification access',
    ]);
  }

  bool _isNotificationSummaryCommand(String text) {
    return _containsAny(text, [
      'notifications today',
      'notification summary',
      'read notifications',
      'what notifications',
    ]);
  }

  bool _isPermissionStatusCommand(String text) {
    return _containsAny(text, [
      'permission status',
      'check permissions',
      'diagnose access',
      'why no access',
      'unable to access',
      'can you access',
    ]);
  }

  bool _containsAny(String text, List<String> patterns) {
    for (final pattern in patterns) {
      if (text.contains(pattern)) return true;
    }
    return false;
  }

  Future<String> _buildTodayBriefing() async {
    await _captureLocationSnapshot();
    final todayEvents = await _getEventsForDay(DateTime.now());
    final reminderEntries = await _getTodayEntries(_reminderTrackKey);
    final alarmEntries = await _getTodayEntries(_alarmTrackKey);
    final notificationSummary = await _buildNotificationSummary(compact: true);
    final locationSummary = await _buildLocationSummary();

    final buffer = StringBuffer();
    buffer.writeln('Here is your daily briefing:');
    buffer.writeln('');

    if (todayEvents.isEmpty) {
      buffer.writeln('- Calendar: no events found for today.');
    } else {
      buffer.writeln('- Calendar: ${todayEvents.length} event(s) today.');
      for (final event in todayEvents.take(5)) {
        final title = (event.title ?? 'Untitled').trim();
        final start = event.start?.toLocal();
        if (start != null) {
          buffer.writeln('  - ${_formatDateTime(start)}: $title');
        } else {
          buffer.writeln('  - $title');
        }
      }
    }

    if (reminderEntries.isEmpty) {
      buffer.writeln('- Reminders: no tracked reminders for today.');
    } else {
      buffer.writeln('- Reminders: ${reminderEntries.length} tracked today.');
    }

    if (alarmEntries.isEmpty) {
      buffer.writeln('- Alarms: no tracked alarms for today.');
    } else {
      buffer.writeln('- Alarms: ${alarmEntries.length} tracked today.');
    }

    buffer.writeln('- $locationSummary');
    buffer.writeln('- $notificationSummary');
    buffer.writeln(
      '- Steps: not available yet. Current build estimates movement via GPS snapshots only.',
    );
    return buffer.toString().trim();
  }

  Future<String> _buildCalendarAgenda() async {
    final diagnostics = await _getCalendarDiagnostics();
    if (!diagnostics.permissionGranted) {
      return 'Calendar access is not granted yet. Run "permission status", then grant Calendar permission in app settings.';
    }
    if (diagnostics.calendarCount == 0) {
      return 'Calendar permission is granted, but no calendar account is available on this phone. Add a Google/Outlook account to Calendar first.';
    }

    final events = await _getEventsForDay(DateTime.now());
    if (events.isEmpty) {
      return 'I could not find calendar events for today.';
    }

    final lines = <String>['Today\'s calendar agenda:'];
    for (final event in events.take(12)) {
      final title = (event.title ?? 'Untitled').trim();
      final start = event.start?.toLocal();
      if (start != null) {
        lines.add('- ${_formatDateTime(start)}: $title');
      } else {
        lines.add('- $title');
      }
    }
    return lines.join('\n');
  }

  Future<String> _buildNotificationSummary({bool compact = false}) async {
    final enabled = await _notificationAccessService
        .isNotificationAccessEnabled();
    if (!enabled) {
      if (compact) {
        return 'Notifications: access is off. Say "enable notification access" to grant it.';
      }
      return 'Notification access is not enabled yet. Say "enable notification access" and grant the permission in Android settings.';
    }

    final notifications = await _notificationAccessService
        .getCapturedNotifications(limit: 250);
    final dayStart = DateTime.now();
    final start = DateTime(dayStart.year, dayStart.month, dayStart.day);
    final today = notifications
        .where((n) => n.postedAt.isAfter(start))
        .toList();

    if (today.isEmpty) {
      return compact
          ? 'Notifications: no captured notifications yet today.'
          : 'No captured notifications yet for today.';
    }

    final byApp = <String, int>{};
    for (final item in today) {
      byApp.update(item.packageName, (value) => value + 1, ifAbsent: () => 1);
    }
    final topApps = byApp.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (compact) {
      final top = topApps
          .take(3)
          .map((e) => '${e.key} (${e.value})')
          .join(', ');
      return 'Notifications: ${today.length} captured today. Top apps: $top.';
    }

    final lines = <String>[
      'Captured notifications today: ${today.length}',
      'Top apps:',
    ];
    for (final entry in topApps.take(5)) {
      lines.add('- ${entry.key}: ${entry.value}');
    }
    return lines.join('\n');
  }

  Future<String> _openNotificationAccessSettings() async {
    final opened = await _notificationAccessService
        .openNotificationAccessSettings();
    if (opened) {
      return 'Opened notification access settings. Enable I.A agent so I can include notifications in your daily briefing.';
    }
    return 'Could not open notification access settings automatically. Please open Android Settings > Notification Access and enable I.A agent.';
  }

  Future<String> _buildPermissionStatusReport() async {
    final calendarPluginStatus = await _calendarPlugin.hasPermissions();
    final calendarFull = await Permission.calendarFullAccess.status;
    final calendarWriteOnly = await Permission.calendarWriteOnly.status;
    final calendarLegacy = await Permission.calendar.status;
    final notificationRuntime = await Permission.notification.status;
    final locationStatus = await Permission.locationWhenInUse.status;
    final notificationAccessEnabled = await _notificationAccessService
        .isNotificationAccessEnabled();

    return [
      'Permission diagnostics:',
      '- Calendar plugin: ${calendarPluginStatus.data == true ? "granted" : "not granted"}',
      '- Calendar full access: $calendarFull',
      '- Calendar write-only: $calendarWriteOnly',
      '- Calendar legacy: $calendarLegacy',
      '- Android notification runtime: $notificationRuntime',
      '- Notification listener access: ${notificationAccessEnabled ? "enabled" : "disabled"}',
      '- Location while-in-use: $locationStatus',
      '',
      'If listener access still shows disabled after enabling it, toggle it OFF then ON once in Android Settings > Notification Access.',
    ].join('\n');
  }

  Future<String> _createReminder(String rawInput) async {
    final parsed = _parseScheduleIntent(rawInput, fallbackTitle: 'Reminder');
    if (parsed == null) {
      return 'I could not parse the reminder time. Example: "set reminder tomorrow 8:30 am project call".';
    }

    final permissionResult = await _ensureCalendarPermission();
    if (!permissionResult) {
      final report = await _buildPermissionStatusReport();
      return 'Calendar permission is required. Please grant calendar access in app settings and try again.\n\n$report';
    }

    final calendar = await _pickWritableCalendar();
    if (calendar == null || calendar.id == null) {
      final opened = await _openCalendarInsertScreen(parsed);
      if (opened) {
        return 'No writable calendar provider was available directly, so I opened the Calendar create-event screen. Save the reminder there.';
      }
      return 'No writable calendar was found on this device. Add a calendar account (Google/Outlook) and retry.\n\nTip: open Calendar app once and create a test event manually.';
    }

    final reminderMinutes = _buildReminderMinutes(parsed.when);
    final start = TZDateTime.from(parsed.when, local);
    final end = start.add(const Duration(minutes: 30));
    final event = Event(
      calendar.id,
      title: parsed.title,
      description: 'Created by I.A agent',
      start: start,
      end: end,
      reminders: reminderMinutes.map((m) => Reminder(minutes: m)).toList(),
    );

    final result = await _calendarPlugin.createOrUpdateEvent(event);
    if (result == null || !result.isSuccess) {
      final opened = await _openCalendarInsertScreen(parsed);
      if (opened) {
        return 'Direct calendar write failed, so I opened the Calendar create-event screen. Save the reminder there.';
      }
      return 'I could not create that reminder in your calendar. Try adding a default writable calendar account.';
    }

    await _appendTrackedEntry(_reminderTrackKey, {
      'title': parsed.title,
      'timestamp': parsed.when.millisecondsSinceEpoch,
      'eventId': result.data,
      'safeZone': parsed.safeZoneApplied,
    });

    final safeZoneNote = parsed.safeZoneApplied
        ? ' Safe-zone reminder logic was applied for this far date.'
        : '';
    return 'Reminder set for ${_formatDateTime(parsed.when)}: ${parsed.title}.$safeZoneNote';
  }

  Future<String> _createAlarm(String rawInput) async {
    final parsed = _parseScheduleIntent(rawInput, fallbackTitle: 'Alarm');
    if (parsed == null) {
      return 'I could not parse the alarm time. Example: "set alarm at 7:00 am".';
    }

    final now = DateTime.now();
    final difference = parsed.when.difference(now);
    final farAway = difference.inDays > _safeAlarmWindowDays;

    if (farAway) {
      final safeDate = parsed.when.subtract(
        const Duration(days: _safeAlarmWindowDays),
      );
      await _appendTrackedEntry(_alarmTrackKey, {
        'title': parsed.title,
        'timestamp': parsed.when.millisecondsSinceEpoch,
        'safeZoneTimestamp': safeDate.millisecondsSinceEpoch,
        'safeZone': true,
      });

      final safeReminderInput =
          'set reminder ${_formatDateTimeForParser(safeDate)} prepare alarm for ${parsed.title}';
      await _createReminder(safeReminderInput);

      return 'This alarm is far away, so I placed a safe-zone reminder for ${_formatDateTime(safeDate)}. Final target is ${_formatDateTime(parsed.when)}.';
    }

    if (!Platform.isAndroid) {
      return 'Direct system alarm setup is currently supported on Android only.';
    }

    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.SET_ALARM',
        arguments: <String, dynamic>{
          'android.intent.extra.alarm.HOUR': parsed.when.hour,
          'android.intent.extra.alarm.MINUTES': parsed.when.minute,
          'android.intent.extra.alarm.MESSAGE': parsed.title,
          'android.intent.extra.alarm.SKIP_UI': false,
        },
      );
      final canResolve = await intent.canResolveActivity();
      if (canResolve != true) {
        return 'No alarm clock app handler was found on this device.';
      }
      await intent.launch();
    } catch (_) {
      return 'I could not open the Android alarm screen.';
    }

    await _appendTrackedEntry(_alarmTrackKey, {
      'title': parsed.title,
      'timestamp': parsed.when.millisecondsSinceEpoch,
      'safeZone': false,
    });

    return 'Alarm request prepared for ${_formatDateTime(parsed.when)} (${parsed.title}). Confirm it in the alarm app screen.';
  }

  Future<List<Event>> _getEventsForDay(DateTime day) async {
    final hasPermission = await _ensureCalendarPermission();
    if (!hasPermission) return const [];

    final calendarsResult = await _calendarPlugin.retrieveCalendars();
    if (!calendarsResult.isSuccess || calendarsResult.data == null) {
      return const [];
    }

    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final events = <Event>[];

    for (final calendar in calendarsResult.data!) {
      final calendarId = calendar.id;
      if (calendarId == null || calendarId.isEmpty) continue;

      final result = await _calendarPlugin.retrieveEvents(
        calendarId,
        RetrieveEventsParams(startDate: dayStart, endDate: dayEnd),
      );
      if (result.isSuccess && result.data != null) {
        events.addAll(result.data!);
      }
    }

    events.sort((a, b) {
      final aTs = a.start?.millisecondsSinceEpoch ?? 0;
      final bTs = b.start?.millisecondsSinceEpoch ?? 0;
      return aTs.compareTo(bTs);
    });
    return events;
  }

  Future<bool> _openCalendarInsertScreen(_ScheduleIntent parsed) async {
    if (!Platform.isAndroid) return false;
    try {
      final intent = AndroidIntent(
        action: 'android.intent.action.INSERT',
        data: 'content://com.android.calendar/events',
        arguments: <String, dynamic>{
          'title': parsed.title,
          'description': 'Created by I.A agent',
          'beginTime': parsed.when.millisecondsSinceEpoch,
          'endTime': parsed.when
              .add(const Duration(minutes: 30))
              .millisecondsSinceEpoch,
        },
      );
      final canResolve = await intent.canResolveActivity();
      if (canResolve != true) return false;
      await intent.launch();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ensureCalendarPermission() async {
    try {
      final hasPermissions = await _calendarPlugin.hasPermissions();
      if (hasPermissions.isSuccess && (hasPermissions.data ?? false)) {
        return true;
      }
      final request = await _calendarPlugin.requestPermissions();
      if (request.isSuccess && (request.data ?? false)) {
        return true;
      }
    } catch (_) {
      // Keep going with runtime fallbacks.
    }

    final statuses = await [
      Permission.calendarFullAccess,
      Permission.calendarWriteOnly,
      Permission.calendar,
    ].request();

    final runtimeGranted = statuses.values.any((status) => status.isGranted);
    if (!runtimeGranted) {
      return false;
    }

    try {
      final verify = await _calendarPlugin.hasPermissions();
      if (verify.isSuccess && (verify.data ?? false)) {
        return true;
      }
    } catch (_) {
      // Some ROMs can still fail this check even when runtime permission is granted.
    }

    return true;
  }

  Future<Calendar?> _pickWritableCalendar() async {
    final result = await _calendarPlugin.retrieveCalendars();
    if (!result.isSuccess || result.data == null || result.data!.isEmpty) {
      return null;
    }
    final writable = result.data!
        .where((calendar) => calendar.isReadOnly != true)
        .toList();
    if (writable.isEmpty) return result.data!.first;
    final defaultCalendar = writable.where((c) => c.isDefault == true).toList();
    return defaultCalendar.isNotEmpty ? defaultCalendar.first : writable.first;
  }

  Future<_CalendarDiagnostics> _getCalendarDiagnostics() async {
    final permissionGranted = await _ensureCalendarPermission();
    var count = 0;
    try {
      final result = await _calendarPlugin.retrieveCalendars();
      count = result.data?.length ?? 0;
    } catch (_) {
      count = 0;
    }
    return _CalendarDiagnostics(
      permissionGranted: permissionGranted,
      calendarCount: count,
    );
  }

  List<int> _buildReminderMinutes(DateTime target) {
    final diff = target.difference(DateTime.now());
    if (diff.inDays > 30) {
      return const [10080, 1440, 60];
    }
    if (diff.inDays > 7) {
      return const [1440, 60];
    }
    if (diff.inDays >= 1) {
      return const [180, 30];
    }
    return const [60, 10];
  }

  Future<void> _captureLocationSnapshot() async {
    if (await Permission.locationWhenInUse.request() !=
        PermissionStatus.granted) {
      return;
    }
    LocationPermission locationPermission = await Geolocator.checkPermission();
    if (locationPermission == LocationPermission.denied ||
        locationPermission == LocationPermission.deniedForever) {
      locationPermission = await Geolocator.requestPermission();
    }
    if (locationPermission == LocationPermission.denied ||
        locationPermission == LocationPermission.deniedForever) {
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      );
      await _appendTrackedEntry(_locationTrackKey, {
        'lat': position.latitude,
        'lng': position.longitude,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (_) {
      return;
    }
  }

  Future<String> _buildLocationSummary() async {
    final entries = await _getTodayEntries(_locationTrackKey);
    if (entries.isEmpty) {
      return 'Location: no GPS snapshots yet today.';
    }

    final latest = entries.last;
    final lat = (latest['lat'] as num?)?.toDouble();
    final lng = (latest['lng'] as num?)?.toDouble();
    final distanceKm = _estimateDistanceKm(entries);
    if (lat == null || lng == null) {
      return 'Location snapshots exist, but latest coordinates are unavailable.';
    }

    return 'Location: last known ${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}. Estimated movement today: ${distanceKm.toStringAsFixed(2)} km.';
  }

  double _estimateDistanceKm(List<Map<String, dynamic>> entries) {
    if (entries.length < 2) return 0.0;
    var totalMeters = 0.0;
    for (var i = 1; i < entries.length; i++) {
      final prev = entries[i - 1];
      final curr = entries[i];
      final prevLat = (prev['lat'] as num?)?.toDouble();
      final prevLng = (prev['lng'] as num?)?.toDouble();
      final currLat = (curr['lat'] as num?)?.toDouble();
      final currLng = (curr['lng'] as num?)?.toDouble();
      if (prevLat == null ||
          prevLng == null ||
          currLat == null ||
          currLng == null) {
        continue;
      }
      totalMeters += Geolocator.distanceBetween(
        prevLat,
        prevLng,
        currLat,
        currLng,
      );
    }
    return totalMeters / 1000.0;
  }

  Future<List<Map<String, dynamic>>> _getTodayEntries(String key) async {
    final entries = await _loadTrackedEntries(key);
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).millisecondsSinceEpoch;
    return entries.where((entry) {
      final ts = (entry['timestamp'] as num?)?.toInt() ?? 0;
      return ts >= start;
    }).toList()..sort((a, b) {
      final aTs = (a['timestamp'] as num?)?.toInt() ?? 0;
      final bTs = (b['timestamp'] as num?)?.toInt() ?? 0;
      return aTs.compareTo(bTs);
    });
  }

  Future<List<Map<String, dynamic>>> _loadTrackedEntries(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map(
            (item) =>
                item.map((mapKey, value) => MapEntry(mapKey.toString(), value)),
          )
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> _appendTrackedEntry(
    String key,
    Map<String, dynamic> entry,
  ) async {
    final existing = await _loadTrackedEntries(key);
    existing.add(entry);
    const maxItems = 500;
    if (existing.length > maxItems) {
      existing.removeRange(0, existing.length - maxItems);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(existing));
  }

  String _formatDateTime(DateTime time) {
    final mm = time.month.toString().padLeft(2, '0');
    final dd = time.day.toString().padLeft(2, '0');
    final hh = time.hour.toString().padLeft(2, '0');
    final min = time.minute.toString().padLeft(2, '0');
    return '$mm/$dd ${time.year} $hh:$min';
  }

  String _formatDateTimeForParser(DateTime time) {
    final mm = time.month.toString().padLeft(2, '0');
    final dd = time.day.toString().padLeft(2, '0');
    final hh = time.hour.toString().padLeft(2, '0');
    final min = time.minute.toString().padLeft(2, '0');
    return '${time.year}-$mm-$dd $hh:$min';
  }

  _ScheduleIntent? _parseScheduleIntent(
    String rawInput, {
    required String fallbackTitle,
  }) {
    final input = rawInput.trim();
    if (input.isEmpty) return null;
    final lower = input.toLowerCase();
    final now = DateTime.now();

    DateTime day = DateTime(now.year, now.month, now.day);
    var hasExplicitDay = false;
    var safeZoneApplied = false;

    if (lower.contains('tomorrow')) {
      day = day.add(const Duration(days: 1));
      hasExplicitDay = true;
    } else if (lower.contains('today')) {
      hasExplicitDay = true;
    } else {
      final isoDate = RegExp(
        r'\b(\d{4})-(\d{1,2})-(\d{1,2})\b',
      ).firstMatch(lower);
      if (isoDate != null) {
        final year = int.tryParse(isoDate.group(1) ?? '');
        final month = int.tryParse(isoDate.group(2) ?? '');
        final dayOfMonth = int.tryParse(isoDate.group(3) ?? '');
        if (year != null && month != null && dayOfMonth != null) {
          day = DateTime(year, month, dayOfMonth);
          hasExplicitDay = true;
        }
      }
    }

    if (!hasExplicitDay) {
      final weekdays = <String, int>{
        'monday': DateTime.monday,
        'tuesday': DateTime.tuesday,
        'wednesday': DateTime.wednesday,
        'thursday': DateTime.thursday,
        'friday': DateTime.friday,
        'saturday': DateTime.saturday,
        'sunday': DateTime.sunday,
      };
      for (final entry in weekdays.entries) {
        if (!lower.contains(entry.key)) continue;
        var diff = (entry.value - now.weekday) % 7;
        if (diff <= 0) diff += 7;
        day = day.add(Duration(days: diff));
        hasExplicitDay = true;
        break;
      }
    }

    var hour = 9;
    var minute = 0;
    var hasExplicitTime = false;

    final amPm = RegExp(
      r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b',
    ).firstMatch(lower);
    if (amPm != null) {
      var parsedHour = int.tryParse(amPm.group(1) ?? '0') ?? 0;
      final parsedMinute = int.tryParse(amPm.group(2) ?? '0') ?? 0;
      final suffix = amPm.group(3) ?? 'am';
      parsedHour = parsedHour.clamp(0, 12);
      if (suffix == 'pm' && parsedHour < 12) parsedHour += 12;
      if (suffix == 'am' && parsedHour == 12) parsedHour = 0;
      hour = parsedHour;
      minute = parsedMinute.clamp(0, 59);
      hasExplicitTime = true;
    } else {
      final hhmm = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b').firstMatch(lower);
      if (hhmm != null) {
        hour = int.tryParse(hhmm.group(1) ?? '9') ?? 9;
        minute = int.tryParse(hhmm.group(2) ?? '0') ?? 0;
        hasExplicitTime = true;
      }
    }

    if (!hasExplicitTime) {
      if (lower.contains('morning')) {
        hour = 9;
      } else if (lower.contains('afternoon')) {
        hour = 14;
      } else if (lower.contains('evening')) {
        hour = 19;
      } else if (lower.contains('night')) {
        hour = 21;
      }
    }

    var when = DateTime(day.year, day.month, day.day, hour, minute);
    if (!hasExplicitDay && when.isBefore(now)) {
      when = when.add(const Duration(days: 1));
    }
    if (when.difference(now).inDays > 30) {
      safeZoneApplied = true;
    }

    var title = input;
    final removePatterns = <RegExp>[
      RegExp(r'\bset( an?)? reminder\b', caseSensitive: false),
      RegExp(r'\bset( an?)? alarm\b', caseSensitive: false),
      RegExp(r'\bremind me\b', caseSensitive: false),
      RegExp(r'\balarm for\b', caseSensitive: false),
      RegExp(r'\bwake me\b', caseSensitive: false),
      RegExp(r'\btomorrow\b', caseSensitive: false),
      RegExp(r'\btoday\b', caseSensitive: false),
      RegExp(
        r'\b(monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b',
        caseSensitive: false,
      ),
      RegExp(r'\b\d{4}-\d{1,2}-\d{1,2}\b'),
      RegExp(r'\b\d{1,2}:\d{2}\b'),
      RegExp(r'\b\d{1,2}(:\d{2})?\s*(am|pm)\b', caseSensitive: false),
      RegExp(r'\b(morning|afternoon|evening|night)\b', caseSensitive: false),
      RegExp(r'\bat\b', caseSensitive: false),
      RegExp(r'\bon\b', caseSensitive: false),
      RegExp(r'\s+'),
    ];
    for (final pattern in removePatterns) {
      title = title.replaceAll(pattern, ' ');
    }
    title = title.trim();
    if (title.isEmpty) title = fallbackTitle;

    return _ScheduleIntent(
      title: title,
      when: when,
      safeZoneApplied: safeZoneApplied,
    );
  }
}

class _ScheduleIntent {
  final String title;
  final DateTime when;
  final bool safeZoneApplied;

  const _ScheduleIntent({
    required this.title,
    required this.when,
    required this.safeZoneApplied,
  });
}

class _CalendarDiagnostics {
  final bool permissionGranted;
  final int calendarCount;

  const _CalendarDiagnostics({
    required this.permissionGranted,
    required this.calendarCount,
  });
}
