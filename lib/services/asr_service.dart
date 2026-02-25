///
///

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:app/config/default_config.dart';
import 'package:app/constants/prompt_constants.dart';
import 'package:app/constants/wakeword_constants.dart';
import 'package:app/models/chat_mode.dart';
import 'package:app/models/asr_mode.dart';

import 'package:app/services/cloud_asr.dart';
import 'package:app/utils/text_process_utils.dart';
import 'package:app/utils/sp_util.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:opus_dart/opus_dart.dart';
import 'package:opus_flutter/opus_flutter.dart' as opus_flutter;
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:linalg/linalg.dart';
import 'package:uuid/uuid.dart';
import '../constants/record_constants.dart';
import '../constants/system_constants.dart';
import '../models/record_entity.dart';
import '../services/objectbox_service.dart';
import '../services/unified_chat_manager.dart';
import '../services/llm_factory.dart';
import '../services/base_llm.dart';
import '../utils/asr_utils.dart';
import '../utils/audio_process_util.dart';
import 'asr_service_isolate.dart';
import '../utils/wav/audio_save_util.dart';

import 'ble_service.dart';

const int nDct = 257;
const int nPca = 47;
const int nPcaPackageByte = 244;
const int nOpusPackageByte = 84;
final Float32List silence = Float32List((16000 * 5).toInt());

@pragma('vm:entry-point')
void startRecordService() {
  FlutterForegroundTask.setTaskHandler(RecordServiceHandler());
}

class RecordServiceHandler extends TaskHandler {
  AudioRecorder _record = AudioRecorder();

  sherpa_onnx.VoiceActivityDetector? _vad;
  late KeywordSpotter _keywordSpotter;
  late OnlineStream _keywordSpotterStream;

  StreamSubscription<RecordState>? _recordSub;

  final ObjectBoxService _objectBoxService = ObjectBoxService();

  bool _inDialogMode = false;
  bool _isMeeting = false;

  /// Get current chat mode
  ChatMode get _currentChatMode {
    if (_isMeeting) {
      return ChatMode.meetingMode;
    } else if (_inDialogMode) {
      return ChatMode.dialogMode;
    } else {
      return ChatMode.defaultMode;
    }
  }

  /// Get current ASR mode
  AsrMode get _currentAsrMode {
    // Use the ASR mode corresponding to current chat mode
    return _getUserConfiguredAsrMode() ?? _currentChatMode.defaultAsrMode;
  }

  /// Get user configured ASR mode from SharedPreferences
  AsrMode? _getUserConfiguredAsrMode() {
    // This method should be async, but we need sync access for the getter
    // We'll use a cached value that gets updated when settings change
    return _cachedUserAsrMode ?? _currentChatMode.defaultAsrMode;
  }

  /// Cached user ASR mode to avoid async calls in getter
  AsrMode? _cachedUserAsrMode;

  /// Load user configured ASR mode from SharedPreferences
  Future<void> _loadUserAsrModeConfig() async {
    try {
      final chatMode = _currentChatMode;
      final instance = await SharedPreferences.getInstance();
      await instance.reload();
      final asrModeKey = await SPUtil.getString('asr_mode_${chatMode.name}');

      if (chatMode != _currentChatMode) {
        dev.log(
          'Chat mode changed while loading configuration; reloading settings',
        );
        return _loadUserAsrModeConfig();
      }

      _cachedUserAsrMode = AsrModeUtils.fromStorageKey(asrModeKey);
      dev.log(
        'Loaded user ASR mode: ${_cachedUserAsrMode?.name ?? "default"}, chat mode: ${chatMode.name}',
      );
    } catch (e) {
      dev.log('Failed to load user ASR mode: $e');
      _cachedUserAsrMode = null;
    }
  }

  /// Whether to use cloud services (determined by current ASR mode)
  bool get _isUsingCloudServices {
    return _currentAsrMode.isCloudBased && _cloudAsr.isAvailable;
  }

  /// Whether to use streaming ASR (determined by current ASR mode)
  bool get _shouldUseStreamingAsr {
    return _currentAsrMode.isStreaming && _cloudAsr.canUseStream;
  }

  bool _isInitialized = false;
  RecordState _recordState = RecordState.stop;
  int _lastDataReceivedTimestamp = 0;
  int _boneDataReceivedTimestamp = 0;
  bool _isBoneConductionActive = true;
  bool _onRecording = false;
  bool _budUser = true;
  int? _startMeetingTime;
  bool _kwsBuddie = false;
  bool _kwsJustListen = false;

  late FlutterTts _flutterTts;
  final CloudAsr _cloudAsr = CloudAsr();

  final UnifiedChatManager _unifiedChatManager = UnifiedChatManager();

  int currentStep = 0;
  String currentSpeaker = '';

  List<double> samplesFloat32Buffer = [];

  StreamSubscription<Uint8List>? _bleDataSubscription;
  Timer? _bleTimer;

  Stream<Uint8List>? _recordStream;

  Matrix iDctWeightMatrix = Matrix.fill(nDct, nDct, 0.0);
  Matrix iPcaWeightMatrix = Matrix.fill(nPca, nDct, 0.0);

  List<double> combinedAudio = [];

  List<int> combinedOpusAudio = [];

  final StreamController<Uint8List> _bleAudioStreamController =
      StreamController<Uint8List>();
  StreamSubscription<Uint8List>? _bleAudioStreamSubscription;

  bool _onMicrophone = false;
  var operationId;

  final AsrServiceIsolate _asrServiceIsolate = AsrServiceIsolate();

  late SimpleOpusDecoder opusDecoder;

  int? _ffStartTime;
  int? _feStartTime;

  String? _currentAsrMessageId;
  StreamSubscription? _currentChatSubscription;
  bool _isProcessingChat = false;
  static final RegExp _cjkCharacters = RegExp(r'[\u4E00-\u9FFF]');
  bool _isTtsSpeaking = false;

  bool _shouldSaveAudioForQwenOmni() {
    try {
      final currentLLMType = LLMFactory.instance.currentType;
      if (currentLLMType != LLMType.qwenOmni) {
        return false;
      }

      if (!_inDialogMode) {
        return false;
      }

      return true;
    } catch (e) {
      dev.log('Failed to evaluate audio-save condition: $e');
      return false;
    }
  }

  Uint8List _convertFloat32ToUint8List(Float32List samples) {
    final bytes = ByteData(samples.length * 2);

    for (int i = 0; i < samples.length; i++) {
      int intSample = (samples[i] * 32767).round().clamp(-32768, 32767);
      bytes.setInt16(i * 2, intSample, Endian.little);
    }

    return bytes.buffer.asUint8List();
  }

  String _sanitizeAsrText(String raw) {
    if (raw.isEmpty) return '';

    var text = raw
        .replaceFirst('Buddy', 'Buddie')
        .replaceFirst('buddy', 'buddie')
        .replaceFirst('body', 'buddie');

    // Remove CJK characters to keep speech processing in English only.
    text = text.replaceAll(_cjkCharacters, ' ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
  }

  String _prepareTextForSpeech(String input) {
    var text = input;
    text = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' code block omitted. ');
    text = text.replaceAll(RegExp(r'https?://\S+'), '');
    text = text.replaceAll(RegExp(r'[_*#`]+'), ' ');
    text = text.replaceAll('\n', '. ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
  }

  Map<String, String>? _pickBestEnglishVoice(dynamic voicesRaw) {
    if (voicesRaw is! List) return null;

    final candidates = <Map<String, String>>[];
    for (final raw in voicesRaw) {
      if (raw is! Map) continue;
      final name = (raw['name'] ?? '').toString();
      final locale = (raw['locale'] ?? '').toString();
      if (name.isEmpty || locale.isEmpty) continue;
      if (!locale.toLowerCase().startsWith('en')) continue;
      candidates.add({'name': name, 'locale': locale});
    }

    if (candidates.isEmpty) return null;

    int score(Map<String, String> voice) {
      final name = (voice['name'] ?? '').toLowerCase();
      final locale = (voice['locale'] ?? '').toLowerCase();
      var s = 0;
      if (locale.startsWith('en-us')) s += 5;
      if (name.contains('neural') ||
          name.contains('wavenet') ||
          name.contains('natural') ||
          name.contains('studio') ||
          name.contains('enhanced') ||
          name.contains('premium')) {
        s += 6;
      }
      if (name.contains('compact') || name.contains('local')) s -= 2;
      return s;
    }

    candidates.sort((a, b) => score(b).compareTo(score(a)));
    return candidates.first;
  }

  bool _shouldInterruptTts(String asrText, bool isFinish) {
    if (!_isTtsSpeaking) return false;
    if (!isFinish) return false;
    if (asrText.length < 2) return false;
    return true;
  }

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    await DefaultConfig.initialize();

    await ObjectBoxService.initialize();

    await _unifiedChatManager.init(
      systemPrompt: '$systemPromptOfChat\n\n${systemPromptOfScenario['voice']}',
    );

    iDctWeightMatrix = await loadRealMatrixFromJson(
      'assets/idct_weight.json',
      nDct,
      nDct,
    );
    iPcaWeightMatrix = await loadRealMatrixFromJson(
      'assets/ipca_weight.json',
      nPca,
      nDct,
    );

    initOpus(await opus_flutter.load());
    opusDecoder = SimpleOpusDecoder(sampleRate: 16000, channels: 1);

    await _loadUserAsrModeConfig();

    _initTts();
    _initBle();

    await _cloudAsr.init();
    _cloudAsr.onASRResult = onASRResult;
    await _startRecord();
    // await _cloudTts.init();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  void onReceiveData(Object data) async {
    if (data is Map) {
      // Handle ASR configuration reload command (when settings change)
      if (data['action'] == 'reloadAsrConfig') {
        await _loadUserAsrModeConfig();
        return;
      }

      // Handle LLM configuration reload command (when settings change)
      if (data['action'] == 'reloadLLMConfig') {
        try {
          dev.log('Background service: received LLM config reload request');

          await LLMFactory.instance.reloadLLMConfig();

          await _unifiedChatManager.reinitializeLLM();

          final currentLLMType = LLMFactory.instance.currentType;
          final availableTypes = await LLMFactory.getAvailableLLMTypes();
          final supportsAudioInput = LLMFactory.instance.supportsAudioInput;

          dev.log(
            'Background service: LLM config reload complete, current type: ${currentLLMType?.name}',
          );

          FlutterForegroundTask.sendDataToMain({
            'llmConfigReloaded': true,
            'currentLLMType': currentLLMType?.name,
            'availableLLMTypes': availableTypes.map((t) => t.name).toList(),
            'supportsAudioInput': supportsAudioInput,
          });
        } catch (e) {
          dev.log('Background service: LLM config reload failed: $e');
          FlutterForegroundTask.sendDataToMain({
            'llmConfigReloaded': false,
            'error': e.toString(),
          });
        }
        return;
      }

      // Handle direct LLM type switch command
      if (data['action'] == 'switchLLMType') {
        final llmTypeName = data['llmType'] as String?;
        if (llmTypeName != null) {
          try {
            dev.log(
              'Background service: received LLM type switch request: $llmTypeName',
            );

            LLMType? targetType;
            switch (llmTypeName) {
              case 'customLLM':
                targetType = LLMType.customLLM;
                break;
              case 'qwenOmni':
                targetType = LLMType.qwenOmni;
                break;
            }

            if (targetType != null) {
              await LLMFactory.instance.switchToLLMType(targetType);

              await _unifiedChatManager.reinitializeLLM();

              dev.log(
                'Background service: LLM type switch complete: ${targetType.name}',
              );

              FlutterForegroundTask.sendDataToMain({
                'llmSwitchResult': 'success',
                'currentLLMType': targetType.name,
                'supportsAudioInput': LLMFactory.instance.supportsAudioInput,
              });
            } else {
              throw Exception('Invalid LLM type: $llmTypeName');
            }
          } catch (e) {
            dev.log('Background service: LLM type switch failed: $e');
            FlutterForegroundTask.sendDataToMain({
              'llmSwitchResult': 'failed',
              'error': e.toString(),
            });
          }
        }
        return;
      }
    }

    if (data == Constants.actionStopRecord || data == 'stopRecord') {
      await _stopAndTerminateService();
      return;
    } else if (data == 'startRecording') {
      _onRecording = true;
    } else if (data == 'stopRecording') {
      _onRecording = false;
    } else if (data == 'device') {
      var remoteId = await FlutterForegroundTask.getData(key: 'deviceRemoteId');
      if (remoteId != null) {
        await BleService().getAndConnect(remoteId);
        BleService().listenToConnectionState();
      }
    } else if (data == 'forget') {
      BleService().forgetDevice();
    } else if (data == Constants.actionStartMicrophone) {
      _isMeeting = false;
      FlutterForegroundTask.sendDataToMain({
        'isMeeting': false,
        'connectionState': false,
      });
      // await _startMicrophone();
      // _budUser = false;
      _inDialogMode = false;
      await _loadUserAsrModeConfig();
      // IsolateTts.interrupt();
      _flutterTts.stop();
    } else if (data == Constants.actionStopMicrophone) {
      await _stopMicrophone();
      _budUser = true;
      final isConnected =
          BleService().connectionState == BluetoothConnectionState.connected;
      FlutterForegroundTask.sendDataToMain({'connectionState': isConnected});
    } else if (data == "InitTTS") {
      try {
        // IsolateTts.init();
      } catch (e, stack) {
        dev.log("TTS has Init $e");
      }
    } else if (data == 'resetCloudAsr') {
      // Reset cloud ASR service, usually called after successful payment to get latest quota
      try {
        dev.log('Resetting cloud ASR service...');
        _cloudAsr.dispose();
        await _cloudAsr.init();
        _cloudAsr.onASRResult = onASRResult;
        dev.log('Cloud ASR service reset completed');
        FlutterForegroundTask.sendDataToMain({'asrResetResult': 'success'});
      } catch (e) {
        dev.log('Cloud ASR service reset failed: $e');
        FlutterForegroundTask.sendDataToMain({
          'asrResetResult': 'failed',
          'error': e.toString(),
        });
      }
    } else if (data == 'reinitializeLLM') {
      try {
        dev.log('Reinitializing LLM...');
        await _unifiedChatManager.reinitializeLLM();
        dev.log('LLM reinitialized');
        FlutterForegroundTask.sendDataToMain({'llmReinitResult': 'success'});
      } catch (e) {
        dev.log('LLM reinitialization failed: $e');
        FlutterForegroundTask.sendDataToMain({
          'llmReinitResult': 'failed',
          'error': e.toString(),
        });
      }
    }
    FlutterForegroundTask.sendDataToMain(Constants.actionDone);
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    await _stopRecord();

    _bleDataSubscription?.cancel();
    _bleAudioStreamSubscription?.cancel();
    _bleTimer?.cancel();
    _cloudAsr.dispose();
    BleService().dispose();
  }

  @override
  void onNotificationButtonPressed(String id) async {
    if (id == Constants.actionStopRecord ||
        id == 'stopRecord' ||
        id == 'stop') {
      await _stopAndTerminateService();
    }
  }

  Future<void> _stopAndTerminateService() async {
    try {
      await _stopRecord();
    } catch (e) {
      dev.log('Stop record failed: $e');
    }

    if (await FlutterForegroundTask.isRunningService) {
      try {
        await FlutterForegroundTask.stopService();
      } catch (e) {
        dev.log('Stop foreground service failed: $e');
      }
    }
  }

  void _initBle() async {
    await BleService().init();
    _bleDataSubscription?.cancel();
    _bleDataSubscription = BleService().dataStream.listen((value) {
      final currentTime = DateTime.now().millisecondsSinceEpoch;

      if (value.length == nPcaPackageByte) {
        if (value[0] == 0xff || value[0] == 0xfe) {
          _processMeetingStatus(value[0] == 0xfe, currentTime);
          _decodeAndProcessPcaPackage(value);
        } else if (value[0] == 0x00 || value[0] == 0x01) {
          _processBoneConduction(value[0] == 0x01, currentTime);
        }
      } else if (value.length == nOpusPackageByte) {
        _processBoneConduction(value[80] == 0x01, currentTime);
        _processMeetingStatus(value[81] == 0xfe, currentTime);
        _decodeAndProcessOpusPackage(value);
      } else {
        if (kDebugMode) {
          dev.log("Unexpected BLE data length: ${value.length}");
        }
      }
    });

    _bleAudioStreamSubscription?.cancel();
    _bleAudioStreamSubscription = _bleAudioStreamController.stream.listen((
      bleAudioClip,
    ) {
      dev.log('Process start!!');
      _processAudioData(bleAudioClip);
    });
  }

  void _processBoneConduction(bool status, int currentTime) {
    if (status) {
      if (!_isBoneConductionActive) {
        _isBoneConductionActive = true;
      }
      _boneDataReceivedTimestamp = currentTime;
    } else {
      if (_isBoneConductionActive &&
          currentTime - _boneDataReceivedTimestamp > 2000) {
        _isBoneConductionActive = false;
      }
    }
  }

  void _processMeetingStatus(bool status, int currentTime) async {
    if (!_isMeeting) {
      if (status) {
        _feStartTime ??= currentTime;
        if (currentTime - _feStartTime! > 10000) {
          _isMeeting = true;
          _startMeetingTime = currentTime;
          _inDialogMode = false;
          _feStartTime = null;
          await _loadUserAsrModeConfig();
          FlutterForegroundTask.sendDataToMain({'isMeeting': true});
          // IsolateTts.interrupt();
          _flutterTts.stop();
          FlutterForegroundTask.sendDataToMain({
            'text': SystemConstants.meetingStart,
            'isEndpoint': true,
            'inDialogMode': _inDialogMode,
            'isMeeting': _isMeeting,
            'speaker': 'assistant',
          });
          _objectBoxService.insertMeetingRecord(
            RecordEntity(
              role: 'assistant',
              content: SystemConstants.meetingStart,
            ),
          );
        }
      } else {
        _feStartTime = null;
      }
    } else {
      if (!status) {
        _ffStartTime ??= currentTime;
        if (currentTime - _ffStartTime! > 10000) {
          _isMeeting = false;
          _ffStartTime = null;
          await _loadUserAsrModeConfig();
          FlutterForegroundTask.sendDataToMain({'isMeeting': false});
          FlutterForegroundTask.sendDataToMain({
            'text': SystemConstants.meetingEnd,
            'isEndpoint': true,
            'inDialogMode': _inDialogMode,
            'isMeeting': _isMeeting,
            'speaker': 'assistant',
          });
          _objectBoxService.insertMeetingRecord(
            RecordEntity(
              role: 'assistant',
              content: SystemConstants.meetingEnd,
            ),
          );
        }
      } else {
        _ffStartTime = null;
      }
    }
  }

  void _decodeAndProcessPcaPackage(Uint8List value) async {
    for (var i = 0; i < 3; i++) {
      var audioSlice = AudioProcessingUtil.processSinglePackage(
        value.sublist(1 + i * 80, 1 + (i + 1) * 80),
        iPcaWeightMatrix,
        iDctWeightMatrix,
      );
      combinedAudio.addAll(audioSlice);
      if (combinedAudio.length == 512) {
        Uint8List data = Uint8List(512 * 2);
        for (var j = 0; j < 512; j++) {
          data[j * 2] = (combinedAudio[j] * 32767).toInt();
          data[j * 2 + 1] = (combinedAudio[j] * 32767).toInt() >> 8;
        }
        _bleAudioStreamController.add(data);
        combinedAudio.clear();
      }
    }
  }

  void _decodeAndProcessOpusPackage(Uint8List value) async {
    Uint8List micPart = value.sublist(0, 40);
    Uint8List spkPart = value.sublist(40, 80);
    bool micPartNoneZero =
        micPart.reduce((value, element) => value + element.abs()) > 0;
    bool spkPartNoneZero =
        spkPart.reduce((value, element) => value + element.abs()) > 0;
    if (!micPartNoneZero && !spkPartNoneZero) {
      return;
    }
    Int16List micClip = micPartNoneZero
        ? opusDecoder.decode(input: micPart)
        : Int16List(0);
    Int16List spkClip = spkPartNoneZero
        ? opusDecoder.decode(input: spkPart)
        : Int16List(0);
    for (var i = 0; i < max(micClip.length, spkClip.length); i++) {
      combinedOpusAudio.add(
        (i < micClip.length ? micClip[i] : 0) +
            (i < spkClip.length ? spkClip[i] : 0),
      );
    }
    if (combinedOpusAudio.length > 1000) {
      Uint8List pcmData = Uint8List(combinedOpusAudio.length * 2);
      for (var i = 0; i < combinedOpusAudio.length; i++) {
        pcmData[i * 2] = combinedOpusAudio[i];
        pcmData[i * 2 + 1] = combinedOpusAudio[i] >> 8;
      }
      _bleAudioStreamController.add(pcmData);
      combinedOpusAudio = [];
    }
  }

  Future<void> _initTts() async {
    _flutterTts = FlutterTts();
    _flutterTts.setStartHandler(() {
      _isTtsSpeaking = true;
    });
    _flutterTts.setCompletionHandler(() {
      _isTtsSpeaking = false;
    });
    _flutterTts.setCancelHandler(() {
      _isTtsSpeaking = false;
    });
    _flutterTts.setErrorHandler((_) {
      _isTtsSpeaking = false;
    });

    await _flutterTts.awaitSpeakCompletion(true);

    if (Platform.isAndroid) {
      try {
        final engines = await _flutterTts.getEngines;
        final preferred = engines
            .map((e) => e.toString())
            .firstWhere(
              (e) => e.toLowerCase().contains('google'),
              orElse: () => '',
            );
        if (preferred.isNotEmpty) {
          await _flutterTts.setEngine(preferred);
        }
      } catch (e) {
        dev.log('TTS engine select failed: $e');
      }
    }

    try {
      final langs = await _flutterTts.getLanguages;
      String? selectedLanguage;
      for (final item in langs) {
        final lang = item.toString();
        final normalized = lang.toLowerCase();
        if (normalized == 'en-us' || normalized.startsWith('en-us-')) {
          selectedLanguage = lang;
          break;
        }
        if (selectedLanguage == null && normalized.startsWith('en')) {
          selectedLanguage = lang;
        }
      }
      await _flutterTts.setLanguage(selectedLanguage ?? 'en-US');
    } catch (e) {
      dev.log('TTS language select failed: $e');
      await _flutterTts.setLanguage('en-US');
    }

    try {
      final voices = await _flutterTts.getVoices;
      final bestVoice = _pickBestEnglishVoice(voices);
      if (bestVoice != null) {
        await _flutterTts.setVoice(bestVoice);
      }
    } catch (e) {
      dev.log('TTS voice select failed: $e');
    }

    await _flutterTts.setSpeechRate(0.53);
    await _flutterTts.setPitch(1.03);
    await _flutterTts.setVolume(1.0);
    if (Platform.isAndroid) {
      await _flutterTts.setQueueMode(1);
    }
  }

  Future<void> _initAsr() async {
    if (!_isInitialized) {
      sherpa_onnx.initBindings();

      _vad = await initVad();
      _keywordSpotter = await initKeywordSpotter();
      _keywordSpotterStream = _keywordSpotter.createStream();

      await _asrServiceIsolate.init();

      _recordSub = _record.onStateChanged().listen((recordState) {
        _recordState = recordState;
      });

      _isInitialized = true;
    }
  }

  Future<void> _startRecord() async {
    await _initAsr();

    if (BleService().connectionState == BluetoothConnectionState.disconnected) {
      _startMicrophone();
    }

    FlutterForegroundTask.sendDataToMain({
      'connectionState':
          BleService().connectionState == BluetoothConnectionState.connected,
    });

    FlutterForegroundTask.saveData(key: 'isRecording', value: true);
    // create stop action button
    FlutterForegroundTask.updateService(
      notificationText: 'Recording...',
      notificationButtons: [
        const NotificationButton(id: Constants.actionStopRecord, text: 'Stop'),
      ],
    );
  }

  Future<void> _startMicrophone() async {
    if (_onMicrophone) return;
    _onMicrophone = true;
    if (_recordStream != null) return;
    const config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
    );
    _record = AudioRecorder();
    _recordStream = await _record.startStream(config);
    _recordStream?.listen((data) {
      _processAudioData(data);
    });
  }

  void onASRResult(String data, bool isFinish) {
    final text = _sanitizeAsrText(data);
    if (text.isEmpty) {
      return;
    }

    if (_shouldInterruptTts(text, isFinish)) {
      _currentChatSubscription?.cancel();
      _currentChatSubscription = null;
      _isProcessingChat = false;
      _flutterTts.stop();
    }

    if (isFinish) {
      final operationId = Uuid().v1();
      _processFinalAsrResult(text, operationId);
    } else {
      _processIntermediateAsrResult(text);
    }
  }

  void _processIntermediateAsrResult(String text) {
    if (text.isEmpty) return;

    if (_currentAsrMessageId == null) {
      _currentAsrMessageId = Uuid().v4();
    }

    FlutterForegroundTask.sendDataToMain({
      'asrMessageId': _currentAsrMessageId,
      'asrText': text,
      'asrIsStreaming': true,
      'asrIsEndpoint': false,
      'inDialogMode': _inDialogMode,
      'isMeeting': _isMeeting,
      'speaker': 'user',
      'isVadDetected': true,
    });
  }

  void _processFinalAsrResult(String text, String? operationId) {
    if (text.isEmpty) return;

    text = text.trim();
    text = TextProcessUtils.removeBracketsContent(text);
    text = TextProcessUtils.clearIfRepeatedMoreThanFiveTimes(text);
    text = text.trim();

    if (text.isEmpty) {
      return;
    }

    if (_currentAsrMessageId != null) {
      FlutterForegroundTask.sendDataToMain({
        'asrMessageId': _currentAsrMessageId,
        'asrText': text,
        'asrIsStreaming': false,
        'asrIsEndpoint': true,
        'inDialogMode': _inDialogMode,
        'isMeeting': _isMeeting,
        'speaker': 'user',
        'isVadDetected': false,
      });

      _currentAsrMessageId = null;
    }

    _handlePostAsrProcessing(text, operationId);
  }

  void _handlePostAsrProcessing(String text, String? operationId) {
    if (!_inDialogMode &&
        (wakeword_constants.wakeWordStartDialog.any(
              (keyword) => text.toLowerCase().contains(keyword),
            ) ||
            _kwsBuddie)) {
      _kwsBuddie = false;
      _kwsJustListen = false;
      if (!_isMeeting && _budUser) {
        _inDialogMode = true;
        AudioPlayer().play(AssetSource('audios/interruption.wav'));
      } else {
        if (_isMeeting) {
          FlutterForegroundTask.sendDataToMain({
            'text': SystemConstants.callBuddieInMeeting,
            'isEndpoint': true,
            'inDialogMode': _inDialogMode,
            'isMeeting': _isMeeting,
            'speaker': 'assistant',
          });
          _objectBoxService.insertDialogueRecord(
            RecordEntity(
              role: 'assistant',
              content: SystemConstants.callBuddieInMeeting,
            ),
          );
        } else if (!_budUser) {
          FlutterForegroundTask.sendDataToMain({
            'text': SystemConstants.callBuddieNoBud,
            'isEndpoint': true,
            'inDialogMode': _inDialogMode,
            'isMeeting': _isMeeting,
            'speaker': 'assistant',
          });
          _objectBoxService.insertDialogueRecord(
            RecordEntity(
              role: 'assistant',
              content: SystemConstants.callBuddieNoBud,
            ),
          );
        }
      }
    }

    if (_isMeeting) {
      _objectBoxService.insertMeetingRecord(
        RecordEntity(role: 'user', content: text),
      );
      _unifiedChatManager.addChatSession('user', text);
    } else {
      if (_inDialogMode) {
        _objectBoxService.insertDialogueRecord(
          RecordEntity(role: 'user', content: text),
        );
        _unifiedChatManager.addChatSession('user', text);
        if (wakeword_constants.wakeWordEndDialog.any(
              (keyword) => text.toLowerCase().contains(keyword),
            ) ||
            _kwsJustListen) {
          _inDialogMode = false;
          _kwsJustListen = false;
          _kwsBuddie = false;
          _vad!.clear();
          _flutterTts.stop();
          AudioPlayer().play(AssetSource('audios/beep.wav'));
        }
      } else {
        _objectBoxService.insertDefaultRecord(
          RecordEntity(role: 'user', content: text),
        );
        _unifiedChatManager.addChatSession('user', text);
      }
    }

    if (_inDialogMode) {
      _startChatStreamingRequest(text, null);
    }
  }

  void _processAudioData(
    data, {
    String category = RecordEntity.categoryDefault,
    String? operationId,
  }) async {
    if (_vad == null || !_asrServiceIsolate.isInitialized) {
      return;
    }

    FileService.highSaveWav(
      startMeetingTime: _startMeetingTime,
      onRecording: _isMeeting,
      data: data,
      numChannels: 1,
      sampleRate: 16000,
    );

    if (!_onRecording) return;

    if (_shouldUseStreamingAsr) {
      _cloudAsr.pushStreamData(data);
      return;
    }

    final samplesFloat32 = convertBytesToFloat32(Uint8List.fromList(data));
    _vad!.acceptWaveform(samplesFloat32);
    _keywordSpotterStream.acceptWaveform(
      samples: samplesFloat32,
      sampleRate: 16000,
    );
    while (_keywordSpotter.isReady(_keywordSpotterStream)) {
      _keywordSpotter.decode(_keywordSpotterStream);
      final text = _keywordSpotter.getResult(_keywordSpotterStream).keyword;
      if (text.isNotEmpty) {
        if (wakeword_constants.wakeWordStartDialog.any(
          (keyword) => text.toLowerCase().contains(keyword),
        )) {
          _kwsBuddie = true;
        } else if (wakeword_constants.wakeWordEndDialog.any(
          (keyword) => text.toLowerCase().contains(keyword),
        )) {
          _kwsJustListen = true;
        } else {}
      }
    }

    if (_vad!.isDetected()) {
      FlutterForegroundTask.sendDataToMain({'isVadDetected': true});
    } else {
      FlutterForegroundTask.sendDataToMain({'isVadDetected': false});
    }

    var text = '';
    while (!_vad!.isEmpty()) {
      final samples = _vad!.front().samples;
      if (samples.length < _vad!.config.sileroVad.windowSize) {
        break;
      }
      _vad!.pop();

      FlutterForegroundTask.sendDataToMain({'action': 'stopAudio'});

      Float32List paddedSamples = await _addSilencePadding(samples);
      var segment = '';

      if (_isUsingCloudServices) {
        dev.log('Using cloud ASR: ${_currentAsrMode.name}');
        segment = await _cloudAsr.recognize(paddedSamples);
      } else {
        dev.log('Using local ASR: ${_currentAsrMode.name}');

        segment = await _asrServiceIsolate.sendData(paddedSamples);
      }
      segment = segment
          .replaceFirst('Buddy', 'Buddie')
          .replaceFirst('buddy', 'buddie');

      text += segment;

      _processIntermediateResult(segment);

      if (text.isNotEmpty) {
        _processFinalResult(
          text,
          'user',
          category: category,
          operationId: operationId,
          lastAsrAudioData: _shouldSaveAudioForQwenOmni()
              ? paddedSamples
              : null,
        );
      }
    }
  }

  void _processIntermediateResult(String text) {
    if (text.isEmpty) return;

    if (_currentAsrMessageId == null) {
      _currentAsrMessageId = Uuid().v4();
    }

    FlutterForegroundTask.sendDataToMain({
      'asrMessageId': _currentAsrMessageId,
      'asrText': text,
      'asrIsStreaming': true,
      'asrIsEndpoint': false,
      'inDialogMode': _inDialogMode,
      'isMeeting': _isMeeting,
      'speaker': 'user',
      'isVadDetected': true,
    });
  }

  void _processFinalResult(
    String text,
    String speaker, {
    String category = RecordEntity.categoryDefault,
    String? operationId,
    bool isS2s = false,
    Float32List? lastAsrAudioData,
  }) {
    if (text.isEmpty) return;

    text = text.trim();
    text = TextProcessUtils.removeBracketsContent(text);
    text = TextProcessUtils.clearIfRepeatedMoreThanFiveTimes(text);
    text = text.trim();

    if (text.isEmpty) {
      return;
    }

    if (_currentAsrMessageId != null && speaker == 'user') {
      FlutterForegroundTask.sendDataToMain({
        'asrMessageId': _currentAsrMessageId,
        'asrText': text,
        'asrIsStreaming': false,
        'asrIsEndpoint': true,
        'inDialogMode': _inDialogMode,
        'isMeeting': _isMeeting,
        'speaker': speaker,
      });

      _currentAsrMessageId = null;
    } else {
      FlutterForegroundTask.sendDataToMain({
        'text': text,
        'isEndpoint': true,
        'inDialogMode': _inDialogMode,
        'isMeeting': _isMeeting,
        'speaker': speaker,
      });
    }

    if (!_inDialogMode &&
        speaker == 'user' &&
        (wakeword_constants.wakeWordStartDialog.any(
              (keyword) => text.toLowerCase().contains(keyword),
            ) ||
            _kwsBuddie)) {
      _kwsBuddie = false;
      _kwsJustListen = false;
      if (!_isMeeting && _budUser) {
        _inDialogMode = true;
        _loadUserAsrModeConfig();
        AudioPlayer().play(AssetSource('audios/interruption.wav'));
      } else {
        if (_isMeeting) {
          FlutterForegroundTask.sendDataToMain({
            'text': SystemConstants.callBuddieInMeeting,
            'isEndpoint': true,
            'inDialogMode': _inDialogMode,
            'isMeeting': _isMeeting,
            'speaker': 'assistant',
          });
          _objectBoxService.insertDialogueRecord(
            RecordEntity(
              role: 'assistant',
              content: SystemConstants.callBuddieInMeeting,
            ),
          );
        } else if (!_budUser) {
          FlutterForegroundTask.sendDataToMain({
            'text': SystemConstants.callBuddieNoBud,
            'isEndpoint': true,
            'inDialogMode': _inDialogMode,
            'isMeeting': _isMeeting,
            'speaker': 'assistant',
          });
          _objectBoxService.insertDialogueRecord(
            RecordEntity(
              role: 'assistant',
              content: SystemConstants.callBuddieNoBud,
            ),
          );
        }
      }
    }

    if (_isMeeting) {
      _objectBoxService.insertMeetingRecord(
        RecordEntity(role: 'user', content: text),
      );
      _unifiedChatManager.addChatSession('user', text);
    } else {
      if (speaker != 'user') {
        _objectBoxService.insertDefaultRecord(
          RecordEntity(role: isS2s ? 'assistant' : 'others', content: text),
        );
        _unifiedChatManager.addChatSession(
          isS2s ? 'assistant' : 'others',
          text,
        );
      } else {
        if (_inDialogMode) {
          _objectBoxService.insertDialogueRecord(
            RecordEntity(role: 'user', content: text),
          );
          _unifiedChatManager.addChatSession('user', text);
          if (wakeword_constants.wakeWordEndDialog.any(
                (keyword) => text.toLowerCase().contains(keyword),
              ) ||
              _kwsJustListen) {
            _inDialogMode = false;
            _kwsJustListen = false;
            _kwsBuddie = false;
            _loadUserAsrModeConfig();
            _vad!.clear();
            _flutterTts.stop();
            AudioPlayer().play(AssetSource('audios/beep.wav'));
          } else {
            _startChatStreamingRequest(text, lastAsrAudioData);
          }
        } else {
          _objectBoxService.insertDefaultRecord(
            RecordEntity(role: 'user', content: text),
          );
          _unifiedChatManager.addChatSession('user', text);
        }
      }
    }
  }

  // Start one streaming request at a time and speak the final assistant answer.
  void _startChatStreamingRequest(String text, Float32List? lastAsrAudioData) {
    if (_isProcessingChat) {
      return;
    }

    _currentChatSubscription?.cancel();
    _currentChatSubscription = null;
    _isProcessingChat = true;
    final assistantBuffer = StringBuffer();
    var finalized = false;

    try {
      final isQwenOmni =
          _unifiedChatManager.getCurrentLLMType() == LLMType.qwenOmni;

      final stream = isQwenOmni
          ? _unifiedChatManager.createStreamingRequestWithAudio(
              audioData: lastAsrAudioData != null
                  ? _convertFloat32ToUint8List(lastAsrAudioData)
                  : null,
              userMessage: text,
            )
          : _unifiedChatManager.createStreamingRequest(text: text);

      _currentChatSubscription = stream.listen(
        (response) async {
          final parsed = _parseChatStreamResponse(response);
          if (parsed == null) return;

          if (parsed.deltaText.isNotEmpty) {
            assistantBuffer.write(parsed.deltaText);
          }

          FlutterForegroundTask.sendDataToMain({
            'currentText': text,
            'isFinished': parsed.isFinished,
            'content': parsed.deltaText.isNotEmpty
                ? parsed.deltaText
                : parsed.content,
          });

          if (!parsed.isFinished || finalized) {
            return;
          }

          finalized = true;
          final finalContent = parsed.content.isNotEmpty
              ? parsed.content
              : assistantBuffer.toString();
          await _finalizeAssistantReply(finalContent);
          _isProcessingChat = false;
        },
        onError: (error) {
          dev.log('Chat streaming error: $error');
          _isProcessingChat = false;
        },
        onDone: () {
          if (!finalized) {
            finalized = true;
            final fallbackContent = assistantBuffer.toString();
            if (fallbackContent.trim().isNotEmpty) {
              _finalizeAssistantReply(fallbackContent);
            }
          }
          _isProcessingChat = false;
        },
      );
    } catch (e) {
      dev.log('Failed to start chat streaming: $e');
      _isProcessingChat = false;
    }
  }

  ({String deltaText, String content, bool isFinished})?
  _parseChatStreamResponse(String response) {
    try {
      final res = jsonDecode(response) as Map<String, dynamic>;
      final deltaText = (res['delta'] ?? '').toString();
      final content = (res['content'] ?? deltaText).toString();
      final isFinished = _isFinishedFlag(res['isFinished']);
      return (deltaText: deltaText, content: content, isFinished: isFinished);
    } catch (e) {
      dev.log('Chat stream parse error: $e');
      return null;
    }
  }

  bool _isFinishedFlag(dynamic rawValue) {
    if (rawValue is bool) return rawValue;
    if (rawValue is num) return rawValue != 0;
    final normalized = rawValue?.toString().toLowerCase().trim();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
  }

  Future<void> _finalizeAssistantReply(String content) async {
    final finalContent = content.trim();
    if (finalContent.isEmpty) {
      return;
    }

    _objectBoxService.insertDialogueRecord(
      RecordEntity(role: 'assistant', content: finalContent),
    );
    _unifiedChatManager.addChatSession('assistant', finalContent);
    await _speakAssistantReply(finalContent);
  }

  Future<void> _speakAssistantReply(String content) async {
    if (_isMeeting) {
      return;
    }

    final text = _prepareTextForSpeech(content);
    if (text.isEmpty) {
      return;
    }

    try {
      await _flutterTts.stop();
      await _flutterTts.speak(text);
    } catch (e) {
      dev.log('TTS playback error: $e');
    }
  }

  Future<void> _stopRecord() async {
    if (_recordStream != null) {
      await _record.stop();
      await _record.dispose();
      _recordStream = null;
    }

    _recordSub?.cancel();
    _currentChatSubscription?.cancel();
    _vad?.free();
    _asrServiceIsolate.stopRecord();
    _cloudAsr.stopStream();

    _isProcessingChat = false;
    _currentAsrMessageId = null;

    _isInitialized = false;

    FlutterForegroundTask.saveData(key: 'isRecording', value: false);
    FlutterForegroundTask.updateService(
      notificationText: 'Tap to return to the app',
    );
  }

  Future<void> _stopMicrophone() async {
    if (!_onMicrophone) return;
    if (_recordStream != null) {
      await _record.stop();
      await _record.dispose();
      _recordStream = null;
      _onMicrophone = false;
    }
  }

  Future<sherpa_onnx.VoiceActivityDetector> initVad() async =>
      sherpa_onnx.VoiceActivityDetector(
        config: sherpa_onnx.VadModelConfig(
          sileroVad: sherpa_onnx.SileroVadModelConfig(
            model: await copyAssetFile('assets/silero_vad.onnx'),
            minSilenceDuration: 0.5,
            minSpeechDuration: 0.25,
            windowSize: 512,
            maxSpeechDuration: 5.0,
          ),
          numThreads: 1,
          debug: true,
        ),
        bufferSizeInSeconds: 12.0,
      );

  Future<KeywordSpotter> initKeywordSpotter() async {
    const kwsDir =
        'assets/sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01';
    const encoder = 'encoder-epoch-12-avg-2-chunk-16-left-64.onnx';
    const decoder = 'decoder-epoch-12-avg-2-chunk-16-left-64.onnx';
    const joiner = 'joiner-epoch-12-avg-2-chunk-16-left-64.onnx';
    KeywordSpotter kws = KeywordSpotter(
      KeywordSpotterConfig(
        model: OnlineModelConfig(
          transducer: OnlineTransducerModelConfig(
            encoder: await copyAssetFile('$kwsDir/$encoder'),
            decoder: await copyAssetFile('$kwsDir/$decoder'),
            joiner: await copyAssetFile('$kwsDir/$joiner'),
          ),
          tokens: await copyAssetFile('$kwsDir/tokens_kws.txt'),
        ),
        keywordsFile: await copyAssetFile('$kwsDir/keywords.txt'),
      ),
    );
    return kws;
  }

  Future<List<List<double>>> loadMatrixFromJson(
    String assetPath,
    int rows,
    int cols,
  ) async {
    String jsonString = await rootBundle.loadString(assetPath);
    List<dynamic> jsonData = jsonDecode(jsonString);
    // Check if jsonData is empty
    if (jsonData.isEmpty) {
      return [];
    }
    // Check if the length of jsonData matches the expected size
    if (jsonData.length != rows * cols) {
      dev.log(
        'Warning: jsonData length (${jsonData.length}) does not match expected size ($rows * $cols).',
      );
      return [];
    }
    List<List<double>> matrix = List.generate(rows, (i) {
      return List.generate(cols, (j) {
        return jsonData[i * cols + j].toDouble();
      });
    });
    return matrix;
  }

  Future<Matrix> loadRealMatrixFromJson(
    String assetPath,
    int rows,
    int cols,
  ) async {
    String jsonString = await rootBundle.loadString(assetPath);
    List<dynamic> jsonData = jsonDecode(jsonString);
    dev.log('Loaded JSON data type: ${jsonData.runtimeType}');
    dev.log('Number of elements in jsonData: ${jsonData.length}');

    Matrix matrix = Matrix.fill(rows, cols, 0.0);
    if (jsonData.isEmpty) {
      // Check if jsonData is empty
      dev.log('jsonData is empty!');
    } else if (jsonData.length != rows * cols) {
      // Check if the length of jsonData matches the expected size
      dev.log(
        'Warning: jsonData length (${jsonData.length}) does not match expected size ($rows * $cols).',
      );
    } else {
      for (int i = 0; i < rows; i++) {
        for (int j = 0; j < cols; j++) {
          matrix[i][j] = jsonData[i * cols + j].toDouble();
        }
      }
    }

    return matrix;
  }

  Future<Float32List> _addSilencePadding(Float32List samples) async {
    int totalLength = silence.length * 2 + samples.length;

    Float32List paddedSamples = Float32List(totalLength);

    paddedSamples.setAll(silence.length, samples);

    return paddedSamples;
  }
}
