import 'package:flutter/material.dart';

import 'ai_chat_page.dart';

export 'ai_service.dart' show aiModels, AiModel;
export 'ai_widgets.dart' show aiColor;

/// The AI tab is the chat itself: Chat or the Hub agent, the conversation and a composer.
/// Settings live behind the model chip in its header.
class AiPage extends StatelessWidget {
  const AiPage({super.key});

  @override
  Widget build(BuildContext context) => const AiChatPage(inTab: true);
}
