import 'package:uuid/uuid.dart';

class welcome_constants {
  static List<Map<String, dynamic>> welcomeSentences = [
    {
      'id': const Uuid().v4(),
      'text': "Hello, I am I.A PERSONAL AGENT.",
      'isUser': 'assistant',
    },
    {
      'id': const Uuid().v4(),
      'text':
          "Tap the Bluetooth icon at the top-right to pair your earbuds. The app needs two steps: pair in your phone Bluetooth settings first, then connect inside the app.",
      'isUser': 'assistant',
    },
    {
      'id': const Uuid().v4(),
      'text':
          "Say 'Hello Agent' to have a conversation with me. Say 'Just Listen' if you want me to be quiet but transcribe your comments and conversations to refer to later.",
      'isUser': 'assistant',
    },
    {
      'id': const Uuid().v4(),
      'text':
          "During online meetings, I.A PERSONAL AGENT will automatically transcribe everything for you. You can click the 'Help me Agent' button for assistance during the meetings!",
      'isUser': 'assistant',
    },
    {
      'id': const Uuid().v4(),
      'text':
          "Tap the 'journal' icon to the lower-right to review on-line meeting summaries and transcripts. Summaries appear there a minute after the meetings end.",
      'isUser': 'assistant',
    },
    {
      'id': const Uuid().v4(),
      'text':
          "More help can be found in 'Settings' in the top-right corner of the App --> 'Help document'.",
      'isUser': 'assistant',
    },
  ];
}
