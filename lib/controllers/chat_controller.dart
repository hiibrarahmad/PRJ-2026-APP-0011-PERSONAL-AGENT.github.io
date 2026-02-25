/// Chat state controller for text/audio messages and streaming assistant replies.

import 'dart:async';
import 'dart:developer' as dev;
import 'dart:io';

import 'package:app/constants/prompt_constants.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_sound/public/flutter_sound_player.dart' as player;
import 'package:flutter_sound_platform_interface/flutter_sound_platform_interface.dart'
    as code;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:uuid/uuid.dart';

import '../models/record_entity.dart';
import '../models/chat_mode.dart';
import '../services/unified_chat_manager.dart';
import '../services/base_llm.dart';
import '../services/objectbox_service.dart';

class ChatController extends ChangeNotifier {
  late final UnifiedChatManager unifiedChatManager;
  late final UnifiedChatManager unifiedChatHelp;
  final String helpMessage =
      'Based on historical information, I think the following may help you:\n\n';
  final ObjectBoxService _objectBoxService = ObjectBoxService();
  final List<Map<String, dynamic>> historyMessages = [];
  final List<Map<String, dynamic>> newMessages = [];
  final TextEditingController textController = TextEditingController();
  final Function onNewMessage;
  final ScrollController scrollController = ScrollController();
  Map<String, String?> userToResponseMap = {};

  final ValueNotifier<Set<String>> unReadMessageId = ValueNotifier({});

  static const int _pageSize = 25;
  bool isLoading = false;
  bool hasMoreMessages = true;
  bool bleConnection = false;

  Map<String, String> asrStreamingMessages = {}; // messageId -> current text
  Map<String, int> asrMessageIndices =
      {}; // messageId -> message index in newMessages

  static final Set<ChatController> _instances = <ChatController>{};

  final player.FlutterSoundPlayer _audioPlayer = player.FlutterSoundPlayer();
  final FlutterTts _uiTts = FlutterTts();
  bool _uiTtsReady = false;

  ChatController({required this.onNewMessage}) {
    _instances.add(this);
    _initialize();
  }

  @override
  void dispose() {
    _instances.remove(this);
    super.dispose();
    textController.dispose();
    scrollController.dispose();
    asrStreamingMessages.clear();
    asrMessageIndices.clear();
    _audioPlayer.closePlayer();
    _uiTts.stop();
    FlutterForegroundTask.removeTaskDataCallback(_onReceiveTaskData);
  }

  static Future<void> reinitializeAllLLM() async {
    for (final controller in _instances) {
      await controller.reinitializeLLM();
    }
  }

  /// Determine current chat mode based on data
  ChatMode _getChatMode(Map<String, dynamic> data) {
    final inDialogMode = data['inDialogMode'] as bool?;
    final isMeeting = data['isMeeting'] as bool?;

    ChatMode mode;
    if (isMeeting == true) {
      mode = ChatMode.meetingMode;
    } else if (inDialogMode == true) {
      mode = ChatMode.dialogMode;
    } else {
      mode = ChatMode.defaultMode;
    }

    return mode;
  }

  /// Unified handling of regular messages (non-ASR stream messages)
  void _handleRegularMessage(
    String text,
    String? speaker,
    bool isEndpoint,
    ChatMode chatMode,
    bool hasAsrMessageId,
  ) {
    if (!isEndpoint || !chatMode.shouldInsertMessage(hasAsrMessageId)) {
      return;
    }
    isSpeakValueNotifier.value = false;

    final messageData = {
      'id': const Uuid().v4(),
      'text': text,
      'isUser': speaker ?? 'unknown',
    };

    insertNewMessage(messageData);

    // In dialog mode, need to set AI response mapping
    if (chatMode == ChatMode.dialogMode && speaker == 'user') {
      userToResponseMap[messageData['id'] as String] = null;
    }
  }

  Future<void> _initialize() async {
    unifiedChatManager = UnifiedChatManager();
    unifiedChatHelp = UnifiedChatManager();
    await unifiedChatManager.init(
      systemPrompt: '$systemPromptOfChat\n\n${systemPromptOfScenario['text']}',
    );
    await unifiedChatHelp.init(systemPrompt: systemPromptOfHelp);

    await loadMoreMessages(reset: true);
    if (Platform.isAndroid) {
      await _audioPlayer.openPlayer(isBGService: true);
    } else {
      await _audioPlayer.openPlayer();
    }
    await _initUiTts();
    FlutterForegroundTask.addTaskDataCallback(_onReceiveTaskData);
  }

  Future<void> _initUiTts() async {
    if (_uiTtsReady) return;
    try {
      await _uiTts.awaitSpeakCompletion(false);
      if (Platform.isAndroid) {
        try {
          final engines = await _uiTts.getEngines;
          final preferred = engines
              .map((e) => e.toString())
              .firstWhere(
                (e) => e.toLowerCase().contains('google'),
                orElse: () => '',
              );
          if (preferred.isNotEmpty) {
            await _uiTts.setEngine(preferred);
          }
        } catch (e) {
          dev.log('UI TTS engine select failed: $e');
        }

        await _uiTts.setQueueMode(1);
      }

      final langs = await _uiTts.getLanguages;
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
      if (selectedLanguage != null) {
        await _uiTts.setLanguage(selectedLanguage);
      }

      final voices = await _uiTts.getVoices;
      final bestVoice = _pickBestEnglishVoice(voices);
      if (bestVoice != null) {
        await _uiTts.setVoice(bestVoice);
      }

      // Slightly faster and brighter for a more conversational tone.
      await _uiTts.setSpeechRate(0.53);
      await _uiTts.setPitch(1.03);
      await _uiTts.setVolume(1.0);
      _uiTtsReady = true;
    } catch (e) {
      dev.log('UI TTS init failed: $e');
    }
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

  String _prepareTextForSpeech(String input) {
    var text = input;
    text = text.replaceAll(RegExp(r'```[\s\S]*?```'), ' code block omitted. ');
    text = text.replaceAll(RegExp(r'https?://\S+'), '');
    text = text.replaceAll(RegExp(r'[_*#`]+'), ' ');
    text = text.replaceAll('\n', '. ');
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text;
  }

  Future<void> _speakAssistantText(String text) async {
    final speakText = _prepareTextForSpeech(text);
    if (speakText.isEmpty) return;
    if (!_uiTtsReady) {
      await _initUiTts();
    }
    try {
      await _uiTts.stop();
      await _uiTts.speak(speakText);
    } catch (e) {
      dev.log('UI TTS speak failed: $e');
    }
  }

  Future<void> reinitializeLLM() async {
    await unifiedChatManager.reinitializeLLM();
    await unifiedChatHelp.reinitializeLLM();
  }

  Future<void> loadMoreMessages({bool reset = false}) async {
    if (isLoading) return;

    isLoading = true;

    if (reset) {
      historyMessages.clear();
      newMessages.clear();
      hasMoreMessages = true;
      // Clean up ASR stream state
      _cleanupAsrStreams();
      unifiedChatManager.updateChatHistory();
      unifiedChatHelp.updateChatHistory();
    }

    List<RecordEntity>? records = _objectBoxService.getChatRecords(
      offset: historyMessages.length + newMessages.length,
      limit: _pageSize,
    );

    if (records != null && records.isNotEmpty) {
      List<Map<String, dynamic>> loadMessages = records.map((record) {
        return {
          'id': Uuid().v4(),
          'text': record.content,
          'isUser': record.role,
        };
      }).toList();
      if (newMessages.isEmpty) {
        newMessages.insertAll(0, loadMessages.toList());
        tryNotifyListeners();
        firstScrollToBottom();
      } else {
        historyMessages.insertAll(0, loadMessages.reversed.toList());
      }
      tryNotifyListeners();
    } else {
      hasMoreMessages = false;
    }

    isLoading = false;
  }

  ValueNotifier<bool> isSpeakValueNotifier = ValueNotifier(false);

  void _onReceiveTaskData(Object data) {
    if (data == 'refresh') {
      loadMoreMessages(reset: true);
      return;
    }

    if (data is Map<String, dynamic>) {
      if (data['action'] == 'playAudio') {
        _playAudio(data['data']);
        return;
      }

      if (data['action'] == 'stopAudio') {
        _stopAudio();
        return;
      }

      // Handle ASR stream data (typewriter effect)
      final asrMessageId = data['asrMessageId'] as String?;
      final asrText = data['asrText'] as String?;
      final asrIsStreaming = data['asrIsStreaming'] as bool?;
      final asrIsEndpoint = data['asrIsEndpoint'] as bool?;

      if (asrMessageId != null && asrText != null) {
        _handleAsrStreamData(
          asrMessageId,
          asrText,
          asrIsStreaming ?? false,
          asrIsEndpoint ?? false,
          data,
        );
        return;
      }

      // Handle other types of data
      final text = data['text'] as String?;
      final currentText = data['currentText'] as String?;
      final speaker = data['speaker'] as String?;
      final isEndpoint = data['isEndpoint'] as bool?;
      final isFinished = data['isFinished'] as bool?;
      final delta = data['content'] as String?;
      final isSpeaking = data['isVadDetected'] as bool?;

      if (isSpeaking != null && isSpeaking) {
        isSpeakValueNotifier.value = true;
        if (!bleConnection) {
          FlutterForegroundTask.sendDataToTask("InitTTS");
          bleConnection = true;
        }
      } else if (isSpeaking != null && !isSpeaking) {
        isSpeakValueNotifier.value = false;
        if (!bleConnection) {
          FlutterForegroundTask.sendDataToTask("InitTTS");
          bleConnection = true;
        }
      }
      final chatMode = _getChatMode(data);
      // Unified handling of regular messages (non-ASR and non-chat assistant streams)
      if (isEndpoint != null && text != null) {
        final hasAsrMessageId = data['asrMessageId'] != null;

        _handleRegularMessage(
          text,
          speaker,
          isEndpoint,
          chatMode,
          hasAsrMessageId,
        );
      }

      if (isFinished != null && delta != null) {
        int userIndex = newMessages.indexWhere(
          (msg) => msg['text'] == currentText && msg['isUser'] == 'user',
        );

        if (userIndex != -1) {
          String? responseId = userToResponseMap[newMessages[userIndex]['id']];
          bool isInBottom = checkInBottom();

          if (responseId == null) {
            responseId = const Uuid().v4();
            userToResponseMap[newMessages[userIndex]['id']] = responseId;
            newMessages.insert(0, {
              'id': responseId,
              'text': '',
              'isUser': 'assistant',
            });
          }

          int botIndex = newMessages.indexWhere(
            (msg) => msg['id'] == responseId,
          );
          if (botIndex != -1) {
            newMessages[botIndex]['text'] += delta;
            tryNotifyListeners();

            if (isInBottom) {
              firstScrollToBottom();
            }
            if (isFinished) {
              newMessages[botIndex]['text'] = newMessages[botIndex]['text']
                  .trim();
              userToResponseMap.remove(newMessages[userIndex]['id']);
            }
          }
        }
      }
    }
  }

  void _handleAsrStreamData(
    String asrMessageId,
    String asrText,
    bool isStreaming,
    bool isEndpoint,
    Map<String, dynamic> data,
  ) {
    final speaker = data['speaker'] as String?;

    bool isInBottom = checkInBottom();

    if (isStreaming && !isEndpoint) {
      if (!asrMessageIndices.containsKey(asrMessageId)) {
        final messageData = {
          'id': asrMessageId,
          'text': asrText,
          'isUser': speaker,
          'isAsrStreaming': true,
        };

        newMessages.insert(0, messageData);
        asrMessageIndices[asrMessageId] = 0;
        asrStreamingMessages[asrMessageId] = asrText;

        if (!isInBottom) {
          unReadMessageId.value.add(asrMessageId);
          unReadMessageId.notifyListeners();
        }

        tryNotifyListeners();
        if (isInBottom) {
          firstScrollToBottom();
        }
      } else {
        final messageIndex = asrMessageIndices[asrMessageId]!;
        if (messageIndex < newMessages.length &&
            newMessages[messageIndex]['id'] == asrMessageId) {
          newMessages[messageIndex]['text'] = asrText;
          asrStreamingMessages[asrMessageId] = asrText;

          tryNotifyListeners();
          if (isInBottom) {
            firstScrollToBottom();
          }
        }
      }
    } else if (isEndpoint) {
      if (asrMessageIndices.containsKey(asrMessageId)) {
        final messageIndex = asrMessageIndices[asrMessageId]!;
        if (messageIndex < newMessages.length &&
            newMessages[messageIndex]['id'] == asrMessageId) {
          newMessages[messageIndex]['text'] = asrText;
          newMessages[messageIndex]['isAsrStreaming'] = false;

          asrStreamingMessages.remove(asrMessageId);
          asrMessageIndices.remove(asrMessageId);

          tryNotifyListeners();
          if (isInBottom) {
            firstScrollToBottom();
          }
        }
      } else {
        insertNewMessage({
          'id': asrMessageId,
          'text': asrText,
          'isUser': speaker,
        });
      }
    }
  }

  void _cleanupAsrStreams() {
    asrStreamingMessages.clear();
    asrMessageIndices.clear();
  }

  tryNotifyListeners() {
    onNewMessage();
    if (hasListeners) {
      notifyListeners();
    }
  }

  Future<void> sendMessage({String? initialText}) async {
    String text = initialText ?? textController.text;

    if (text.isNotEmpty) {
      textController.clear();

      insertNewMessage({
        'id': const Uuid().v4(),
        'text': text,
        'isUser': 'user',
      });
      _objectBoxService.insertDialogueRecord(
        RecordEntity(role: 'user', content: text),
      );
      firstScrollToBottom();

      unifiedChatManager.addChatSession('user', text);
      await _getBotResponse(text);
    }
  }

  Future<void> askHelp() async {
    String text = "Please help me";

    unifiedChatHelp.updateChatHistory();

    if (text.isNotEmpty) {
      textController.clear();

      insertNewMessage({
        'id': const Uuid().v4(),
        'text': 'Help me Agent',
        'isUser': 'user',
      });
      _objectBoxService.insertDialogueRecord(
        RecordEntity(role: 'user', content: 'Help me Agent'),
      );
      firstScrollToBottom();

      unifiedChatManager.addChatSession('user', 'Help me Agent');
      await _getBotResponse(text, isHelp: true);
    }
  }

  Future<void> _getBotResponse(String userInput, {bool isHelp = false}) async {
    try {
      tryNotifyListeners();

      String? responseId;
      final chatResponse = isHelp ? unifiedChatHelp : unifiedChatManager;
      final response = await chatResponse.createRequest(text: userInput);
      bool isInBottom = checkInBottom();

      if (responseId == null) {
        responseId = const Uuid().v4();
        if (isHelp) {
          newMessages.insert(0, {
            'id': responseId,
            'text': helpMessage,
            'isUser': 'assistant',
          });
        } else {
          newMessages.insert(0, {
            'id': responseId,
            'text': '',
            'isUser': 'assistant',
          });
        }
      }

      updateMessageText(responseId, response, isFinal: true, isHelp: isHelp);

      if (isInBottom) {
        firstScrollToBottom();
      }
      if (responseId != null) {
        final finalText =
            newMessages.firstWhere((msg) => msg['id'] == responseId)['text']
                as String;
        final cleanText = isHelp
            ? finalText.replaceFirst(helpMessage, '')
            : finalText;

        _objectBoxService.insertDialogueRecord(
          RecordEntity(role: 'assistant', content: cleanText),
        );
        chatResponse.addChatSession('assistant', cleanText);
        await _speakAssistantText(cleanText);
      }
    } catch (e) {
      String errorInfo = e.toString();

      newMessages.insert(0, {
        'id': Uuid().v4(),
        'text': 'Error: $errorInfo',
        'isUser': 'assistant',
      });

      tryNotifyListeners();
    }
  }

  void updateMessageText(
    String messageId,
    String text, {
    bool isFinal = false,
    bool isHelp = false,
  }) {
    int index = newMessages.indexWhere((msg) => msg['id'] == messageId);
    if (index != -1) {
      if (!isFinal) {
        newMessages[index]['text'] += text;
      } else {
        newMessages[index]['text'] = isHelp ? helpMessage + text : text;
      }
      tryNotifyListeners();
    }
  }

  void insertNewMessage(Map<String, dynamic> data) {
    bool isInBottom = checkInBottom();
    if (!isInBottom) {
      unReadMessageId.value.add(data['id']);
    }
    newMessages.insert(0, data);
    tryNotifyListeners();
    if (isInBottom) {
      firstScrollToBottom();
    }
  }

  void copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied to clipboard!'),
        duration: Duration(milliseconds: 500),
      ),
    );
  }

  bool isInAnimation = false;

  bool checkInBottom() {
    if (!scrollController.hasClients) return true;
    double maxScroll = scrollController.position.maxScrollExtent;
    double currentScroll = scrollController.offset;
    return currentScroll >= maxScroll - 20;
  }

  firstScrollToBottom({bool isAnimated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!scrollController.hasClients) return;
      if (isInAnimation) return;
      isInAnimation = true;
      double maxScroll = scrollController.position.maxScrollExtent;
      double currentScroll = scrollController.offset;
      while (currentScroll < maxScroll) {
        if (isAnimated) {
          // Perform the animated scroll only on the first call
          await scrollController.animateTo(
            maxScroll,
            duration: const Duration(milliseconds: 100),
            curve: Curves.linear,
          );
          await Future.delayed(const Duration(milliseconds: 10));
        } else {
          // Perform an immediate jump to the bottom on subsequent recursive calls
          scrollController.jumpTo(maxScroll);
        }
        maxScroll = scrollController.position.maxScrollExtent;
        currentScroll = scrollController.offset;
      }
      isInAnimation = false;
    });
  }

  /// Get current LLM type
  LLMType? getCurrentLLMType() {
    return unifiedChatManager.getCurrentLLMType();
  }

  /// Check if audio input is supported
  bool get supportsAudioInput => unifiedChatManager.supportsAudioInput;

  /// Get list of available LLM types
  Future<List<LLMType>> getAvailableLLMTypes() {
    return unifiedChatManager.getAvailableLLMTypes();
  }

  /// Switch to specified LLM type
  Future<void> switchToLLM(LLMType type) async {
    await unifiedChatManager.switchToLLM(type);
    await unifiedChatHelp.switchToLLM(type);
    notifyListeners();
  }

  /// Play audio data
  Future<void> _playAudio(Uint8List audioData) async {
    try {
      await _audioPlayer.stopPlayer();

      await _audioPlayer.startPlayer(
        codec: code.Codec.pcm16,
        fromDataBuffer: audioData,
        sampleRate: 24000,
        numChannels: 1,
      );
    } catch (e) {
      try {
        await _audioPlayer.stopPlayer();
        await _audioPlayer.startPlayer(
          codec: code.Codec.pcm16WAV,
          fromDataBuffer: audioData,
        );
      } catch (e2) {
        try {
          await _audioPlayer.stopPlayer();
          await _audioPlayer.startPlayer(
            codec: code.Codec.aacMP4,
            fromDataBuffer: audioData,
          );
        } catch (e3) {
          try {
            await _audioPlayer.stopPlayer();
            await _audioPlayer.startPlayer(fromDataBuffer: audioData);
          } catch (e4) {
            dev.log('QwenOmni audio playback failed: $e');
            throw Exception('Failed to play audio');
          }
        }
      }
    }
  }

  /// Stop audio playback
  Future<void> _stopAudio() async {
    await _audioPlayer.stopPlayer();
  }
}
