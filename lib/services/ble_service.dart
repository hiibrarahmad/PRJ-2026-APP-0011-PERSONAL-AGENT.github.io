/// BLE device lifecycle and data channel service.
/// - Restores previously paired device when available.
/// - Reports connection state to foreground task UI.
/// - Uses Buddie BLE data channel when present, falls back to microphone.

import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:typed_data';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../constants/record_constants.dart';

class BleService {
  static final BleService _instance = BleService._internal();
  factory BleService() => _instance;
  BleService._internal();

  BluetoothConnectionState _connectionState =
      BluetoothConnectionState.disconnected;
  BluetoothDevice? _device;
  StreamSubscription<BluetoothConnectionState>? _connectionStateSubscription;
  String? deviceName;
  bool _hasBuddieDataChannel = false;

  final StreamController<Uint8List> _dataController =
      StreamController<Uint8List>();
  Stream<Uint8List> get dataStream => _dataController.stream;
  StreamSubscription<List<int>>? _dataSubscription;

  String? get deviceRemoteId => _device?.remoteId.toString();
  BluetoothConnectionState get connectionState => _connectionState;

  Stream<BluetoothConnectionState> get connectionStateStream =>
      _device?.connectionState ?? Stream<BluetoothConnectionState>.empty();

  Timer? _debounceTimer;

  String _resolveDeviceName() {
    final platformName = _device?.platformName ?? '';
    if (platformName.isNotEmpty) return platformName;
    final advName = _device?.advName ?? '';
    if (advName.isNotEmpty) return advName;
    return _device?.remoteId.toString() ?? 'Unknown device';
  }

  Future<void> _configureConnectionLink() async {
    if (_device == null) return;
    if (Platform.isAndroid) {
      try {
        // Best-effort tuning for Android BLE link quality.
        await _device!.requestMtu(247);
        await _device!.requestConnectionPriority(
          connectionPriorityRequest: ConnectionPriority.high,
        );
        await _device!.setPreferredPhy(
          txPhy: Phy.le2m.mask,
          rxPhy: Phy.le2m.mask,
          option: PhyCoding.noPreferred,
        );
      } catch (e) {
        dev.log('BLE link tuning skipped: $e');
      }
    } else {
      _device!.mtu.listen((int mtu) {
        debugPrint("BLE MTU: $mtu");
      });
    }
  }

  Future<bool> _tryEnableBuddieDataChannel() async {
    if (_device == null) return false;
    try {
      // Keep the original Buddie-specific BLE data channel as preferred.
      final services = await _device!.discoverServices();
      final service = services.firstWhereOrNull(
        (item) => item.uuid.toString() == "ae00",
      );
      if (service == null) {
        return false;
      }

      final chr = service.characteristics.firstWhereOrNull(
        (item) => item.uuid.toString() == "ae04",
      );
      if (chr == null) {
        return false;
      }

      await chr.setNotifyValue(true);
      _dataSubscription?.cancel();
      _dataSubscription = chr.onValueReceived.listen((value) {
        _dataController.add(Uint8List.fromList(value));
      });
      return true;
    } catch (e) {
      dev.log('Buddie data channel unavailable: $e');
      return false;
    }
  }

  Future<void> init() async {
    var remoteId = await FlutterForegroundTask.getData(key: 'deviceRemoteId');
    if (remoteId != null) {
      try {
        _device = BluetoothDevice.fromId(remoteId);
        await FlutterBluePlus.adapterState
            .where((val) => val == BluetoothAdapterState.on)
            .first;
        await _device!.connect(autoConnect: true, mtu: null);
        listenToConnectionState();
      } catch (e) {
        dev.log('BLE init reconnect failed: $e');
      }
    }
    if (Platform.isAndroid) {
      await FlutterBluePlus.getPhySupport();
    }
  }

  Future<void> getAndConnect(dynamic remoteId) async {
    await FlutterBluePlus.adapterState
        .where((val) => val == BluetoothAdapterState.on)
        .first;

    if (remoteId != null) {
      _device = BluetoothDevice.fromId(remoteId);

      final state = await _device!.connectionState.first;
      if (state != BluetoothConnectionState.connected) {
        await _device?.connect(autoConnect: true, mtu: null);
      }
    }
  }

  void listenToConnectionState() {
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = _device?.connectionState.listen((
      state,
    ) async {
      _connectionState = state;

      _debounceTimer?.cancel();
      _debounceTimer = Timer(Duration(milliseconds: 500), () async {
        if (state == BluetoothConnectionState.connected) {
          await Future.delayed(Duration(milliseconds: 3000));
          await _configureConnectionLink();
          _hasBuddieDataChannel = await _tryEnableBuddieDataChannel();
          deviceName = _resolveDeviceName();

          if (_hasBuddieDataChannel) {
            // Preserve original behavior when Buddie BLE audio channel exists.
            FlutterForegroundTask.sendDataToTask(
              Constants.actionStopMicrophone,
            );
          } else {
            // Generic earbuds stay connected, but keep phone microphone path.
            FlutterForegroundTask.sendDataToTask(
              Constants.actionStartMicrophone,
            );
          }

          FlutterForegroundTask.sendDataToMain({
            'connectionState': true,
            'deviceName': deviceName,
            'deviceId': _device?.remoteId.toString(),
            'bleDataChannelReady': _hasBuddieDataChannel,
          });
        } else if (state == BluetoothConnectionState.disconnected) {
          _hasBuddieDataChannel = false;
          _dataSubscription?.cancel();
          _dataSubscription = null;
          deviceName = _resolveDeviceName();
          FlutterForegroundTask.sendDataToTask(Constants.actionStartMicrophone);
          FlutterForegroundTask.sendDataToMain({
            'connectionState': false,
            'deviceName': deviceName,
            'deviceId': _device?.remoteId.toString(),
            'bleDataChannelReady': false,
          });
          dev.log(
            "${_device?.disconnectReason?.code} ${_device?.disconnectReason?.description}",
          );
        }
      });
    });
  }

  void forgetDevice() {
    _device?.disconnect();
    _dataSubscription?.cancel();
    _dataSubscription = null;
    _hasBuddieDataChannel = false;
    deviceName = null;
    _connectionState = BluetoothConnectionState.disconnected;
    FlutterForegroundTask.removeData(key: 'deviceRemoteId');
    FlutterForegroundTask.removeData(key: 'deviceName');
    FlutterForegroundTask.sendDataToMain({
      'action': 'deviceReset',
      'connectionState': false,
      'deviceName': null,
      'deviceId': null,
      'bleDataChannelReady': false,
    });
  }

  void dispose() {
    _connectionStateSubscription?.cancel();
    _dataSubscription?.cancel();
    _debounceTimer?.cancel();
    _dataController.close();
  }
}
