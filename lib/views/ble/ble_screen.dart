import 'dart:async';
import 'dart:io';

import 'package:app/views/ui/toast_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../generated/l10n.dart';
import 'device_card.dart';
import 'not_paired_notice.dart';
import 'scanning_card.dart';

class BLEScreen extends StatefulWidget {
  final bool paired;
  final String? remoteId;
  final String? deviceName;

  const BLEScreen({
    super.key,
    required this.paired,
    this.remoteId,
    this.deviceName,
  });

  @override
  _BLEScreenState createState() => _BLEScreenState();
}

class _BLEScreenState extends State<BLEScreen> {
  List<BluetoothDevice> pairedDevices = [];
  List<BluetoothDevice> systemConnectedDevices = [];
  List<ScanResult> _devices = [];
  bool _isScanning = false;
  late bool _paired;
  String _statusMessage = '';
  StreamSubscription<ScanResult>? _subscription;
  ScanResult? _selectedDevice;
  String? _remoteId;
  String? _deviceName;

  @override
  void initState() {
    super.initState();
    _paired = widget.paired;
    _remoteId = widget.remoteId;
    _deviceName = widget.deviceName;
    if (!_paired) {
      _isScanning = false;
    } else {
      _bootstrapDevices();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _bootstrapDevices() async {
    await getPairedDevices();
    await _loadSystemConnectedDevices();
    if (mounted && _remoteId == null) {
      startScanning();
    }
  }

  Future<void> _loadSystemConnectedDevices() async {
    try {
      var connected = FlutterBluePlus.connectedDevices;
      if (connected.isEmpty) {
        connected = await FlutterBluePlus.systemDevices([Guid("1800")]);
      }

      if (!mounted) return;
      setState(() {
        systemConnectedDevices = connected;
      });
    } catch (_) {
      // Ignore unsupported queries and continue with scan flow.
    }
  }

  Future<void> getPairedDevices() async {
    if (Platform.isIOS) {
      // List<Guid> withServices = [
      //   // Guid("00001108-0000-1000-8000-00805f9b34fb"), // UUID
      // ];
      // pairedDevices = await FlutterBluePlus.systemDevices(withServices);
      // pairedDevices = await FlutterBluePlus.systemDevices([]);
      // if (pairedDevices.isEmpty) {
      //   pairedDevices = await FlutterBluePlus.bondedDevices;
      // }
    } else if (Platform.isAndroid) {
      pairedDevices = await FlutterBluePlus.bondedDevices;
    }
  }

  bool _isSameDeviceByIdOrName(BluetoothDevice paired, ScanResult scanned) {
    final pairedId = paired.remoteId.str.toLowerCase();
    final scannedId = scanned.device.remoteId.str.toLowerCase();
    if (pairedId == scannedId) {
      return true;
    }

    final pairedName = paired.platformName.trim().toLowerCase();
    final scannedName = getDeviceName(scanned).trim().toLowerCase();
    return pairedName.isNotEmpty &&
        scannedName.isNotEmpty &&
        pairedName == scannedName;
  }

  bool _isBondedScanResult(ScanResult result) {
    // Relaxed matching: allow any bonded earbud/device instead of only "Buddie*".
    if (pairedDevices.isEmpty) {
      // iOS may not always expose bonded list in the same way.
      return Platform.isIOS;
    }

    return pairedDevices.any(
      (device) => _isSameDeviceByIdOrName(device, result),
    );
  }

  void _upsertScannedDevice(ScanResult result) {
    final idx = _devices.indexWhere(
      (item) => item.device.remoteId.str == result.device.remoteId.str,
    );
    if (idx >= 0) {
      _devices[idx] = result;
      return;
    }
    _devices.add(result);
  }

  void startScanning() async {
    setState(() {
      _isScanning = true;
      _statusMessage = 'Scanning...';
      _devices.clear();
    });

    final stream = scanDevices();

    _subscription = stream.listen(
      (result) {
        setState(() {
          if (_isBondedScanResult(result)) {
            _upsertScannedDevice(result);
          }
          if (_devices.isNotEmpty) {
            _selectedDevice = _devices[0];
          }
        });
      },
      onDone: () {
        setState(() {
          _isScanning = false;
          _statusMessage = _devices.isEmpty
              ? 'No devices found'
              : 'Scan completed!';
        });
      },
      onError: (error) {
        setState(() {
          _isScanning = false;
          _statusMessage = 'Scan failed: $error';
        });
      },
    );

    Future.delayed(const Duration(seconds: 8), () async {
      if (!mounted || !_isScanning) return;
      await FlutterBluePlus.stopScan();
      await _subscription?.cancel();
      setState(() {
        _isScanning = false;
        _statusMessage = _devices.isEmpty
            ? 'No paired headset detected. Connect from phone Bluetooth settings and retry.'
            : 'Scan completed!';
      });
    });
  }

  Future<bool> startConnecting(ScanResult result) async {
    await FlutterBluePlus.stopScan();
    await _subscription?.cancel();

    final success = await connectToDevice(result);

    setState(() {
      _statusMessage = success
          ? 'Connected to ${result.advertisementData.advName}!'
          : 'Failed to connect to ${result.advertisementData.advName}';
      _isScanning = false;
    });

    return success;
  }

  Future<bool> startConnectingByRemoteId(
    String remoteId,
    String deviceName,
  ) async {
    await FlutterBluePlus.stopScan();
    await _subscription?.cancel();

    final success = await connectToRemoteId(remoteId, deviceName: deviceName);

    setState(() {
      _statusMessage = success
          ? 'Connected to $deviceName!'
          : 'Failed to connect to $deviceName';
      _isScanning = false;
    });

    return success;
  }

  Widget _buildPairedView() {
    if (_remoteId == null) {
      return Stack(
        children: [
          if (systemConnectedDevices.isNotEmpty)
            DeviceCard(
              deviceName: systemConnectedDevices.first.platformName.isNotEmpty
                  ? systemConnectedDevices.first.platformName
                  : systemConnectedDevices.first.remoteId.str,
              text: 'Use currently connected headset?',
              onConfirm: () async {
                final current = systemConnectedDevices.first;
                final fallbackName = current.platformName.isNotEmpty
                    ? current.platformName
                    : current.remoteId.str;
                final success = await startConnectingByRemoteId(
                  current.remoteId.str,
                  fallbackName,
                );
                Navigator.pop(context);
                if (success) {
                  context.showToast(S.of(context).pageBleToastConnectSuccess);
                } else {
                  context.showToast(S.of(context).pageBleToastConnectFailed);
                }
              },
              onCancel: () => Navigator.pop(context),
            ),
          if (_devices.isNotEmpty)
            DeviceCard(
              deviceName: getDeviceName(_devices[0]),
              text: S.of(context).pageBleIsYour,
              onConfirm: () async {
                final target = _selectedDevice ?? _devices[0];
                final success = await startConnecting(target);
                Navigator.pop(context);
                if (success) {
                  context.showToast(S.of(context).pageBleToastConnectSuccess);
                } else {
                  context.showToast(S.of(context).pageBleToastConnectFailed);
                }
              },
              onCancel: () => Navigator.pop(context),
            ),
          if (!_isScanning && _devices.isEmpty && pairedDevices.isNotEmpty)
            DeviceCard(
              deviceName: pairedDevices[0].platformName.isNotEmpty
                  ? pairedDevices[0].platformName
                  : pairedDevices[0].remoteId.str,
              text: S.of(context).pageBleIsYour,
              onConfirm: () async {
                final fallbackName = pairedDevices[0].platformName.isNotEmpty
                    ? pairedDevices[0].platformName
                    : pairedDevices[0].remoteId.str;
                final success = await startConnectingByRemoteId(
                  pairedDevices[0].remoteId.str,
                  fallbackName,
                );
                Navigator.pop(context);
                if (success) {
                  context.showToast(S.of(context).pageBleToastConnectSuccess);
                } else {
                  context.showToast(S.of(context).pageBleToastConnectFailed);
                }
              },
              onCancel: () => Navigator.pop(context),
            ),
          if (_isScanning && _devices.isEmpty) const ScanningCard(),
        ],
      );
    } else {
      return Stack(
        children: [
          DeviceCard(
            deviceName: _deviceName ?? S.of(context).pageBleUnknownDevice,
            text: S.of(context).pageBleSaved,
            onConfirm: () async {
              FlutterForegroundTask.sendDataToTask('forget');
              Navigator.pop(context);
              context.showToast(S.of(context).pageBleToastForgetSuccess);
            },
            onCancel: () => Navigator.pop(context),
            confirmText: 'Forget',
          ),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _paired ? _buildPairedView() : const NotPairedNotice(),
      ),
    );
  }
}

Stream<ScanResult> scanDevices({
  Duration timeout = const Duration(seconds: 10),
}) async* {
  await FlutterBluePlus.adapterState
      .where((val) => val == BluetoothAdapterState.on)
      .first;

  final Set<String> foundDeviceIds = {};

  final StreamController<ScanResult> controller =
      StreamController<ScanResult>();

  final subscription = FlutterBluePlus.scanResults.listen((results) {
    for (final result in results) {
      final deviceId = result.device.remoteId.toString();

      if (!foundDeviceIds.contains(deviceId)) {
        foundDeviceIds.add(deviceId);
        controller.add(result);
      }
    }
  });

  try {
    await FlutterBluePlus.startScan();
    yield* controller.stream;
  } finally {
    await FlutterBluePlus.stopScan();
    await subscription.cancel();
    await controller.close();
  }
}

Future<bool> connectToDevice(ScanResult selectedResult) async {
  return connectToRemoteId(
    selectedResult.device.remoteId.toString(),
    deviceName: getDeviceName(selectedResult),
  );
}

Future<bool> connectToRemoteId(String remoteId, {String? deviceName}) async {
  try {
    await FlutterBluePlus.adapterState
        .where((val) => val == BluetoothAdapterState.on)
        .first;

    await FlutterForegroundTask.saveData(
      key: 'deviceRemoteId',
      value: remoteId,
    );
    await FlutterForegroundTask.saveData(
      key: 'deviceName',
      value: deviceName ?? remoteId,
    );
    FlutterForegroundTask.sendDataToTask('device');
    return true;
  } catch (e) {
    return false;
  }
}

String getDeviceName(ScanResult result) {
  if (result.device.platformName.isNotEmpty) {
    return result.device.platformName;
  }
  if (result.advertisementData.advName.isNotEmpty) {
    return result.advertisementData.advName;
  }
  return "Unknown device";
}
