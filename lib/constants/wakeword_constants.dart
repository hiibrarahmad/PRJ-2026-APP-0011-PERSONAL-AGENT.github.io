class wakeword_constants {
  static const List<String> wakeWordStartDialog = [
    'buddie',
    'buddy',
    'hi buddy',
    'hi buddie',
    'hello buddy',
    'hello buddie',
    'hello agent',
    'hi agent',
    'personal agent',
    'i a personal agent',
    'ia personal agent',
  ];

  static const List<String> wakeWordEndDialog = ['just listen', 'just a listen'];

  static const List<String> voiceVerificationPhrases = [
    'Hey, let\'s hear your voice! Say: \n"Agent, what\'s on my schedule today?"',
    'Great! Next, could you say: \n"Agent, what were the action items from the meeting?"',
    'Almost there! Finally, please say: \n"Agent, any updates from my last chat with friends?"',
    'Well done! You\'re all set up. \nJust say \n"Hi Agent, let\'s get started"',
  ];

  static const List<String> welcomePhrases = [
    'Agent, what\'s on my schedule today?',
    'Agent, what were the action items from the meeting?',
    'Agent, any updates from my last chat with friends?',
    'Hi Agent, let\'s get started',
  ];
}
