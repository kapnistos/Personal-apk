import 'package:flutter/material.dart';

import '../../core/edition.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../claude/claude_page.dart';
import '../shopping/shopping_page.dart';

const aiColor = Color(0xFF4D6BFE);

/// The AI tab: what works today, and what is on its way (DeepSeek, your own keys, personal agents).
class AiPage extends StatelessWidget {
  const AiPage({super.key});

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final text = Theme.of(context).textTheme;
    void open(Widget page) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
    return Scaffold(
      appBar: AppBar(title: const Text('AI')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          ContentWidth(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        AppGlyph(icon: Icons.auto_awesome_rounded, color: aiColor, size: 44),
                        Spacer(),
                        SoonBadge(),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text('Your own assistant, inside Hub', style: text.headlineSmall),
                    const SizedBox(height: 6),
                    Text(
                      personalEdition
                          ? 'Built in and working on your own notes, tasks, calendar and money, '
                                'on your Claude subscription only.'
                          : 'Built in and working on your own notes, tasks, calendar and money. '
                                'DeepSeek first, or any AI you have a key for.',
                      style: TextStyle(color: p.muted, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const ContentWidth(child: ModelPicker()),
          const SizedBox(height: 12),
          const ContentWidth(
            child: Section(
              title: 'Personal agents',
              trailing: Padding(padding: EdgeInsets.only(right: 10), child: SoonBadge()),
              child: Column(
                children: [
                  _Soon(
                    Icons.support_agent_rounded,
                    'Hub agent',
                    'Say "12 euro lunch" or "note: call the landlord" and it adds the expense, note or task for you, '
                        'using the model you chose',
                  ),
                  _Soon(
                    Icons.smart_toy_outlined,
                    'Add your own agents',
                    'Connect personal agents, such as Instinct, and let them act on your Hub',
                  ),
                  _Soon(
                    Icons.shopping_basket_outlined,
                    'Price check',
                    'Finds the cheapest shop for every item on your list',
                  ),
                  _Soon(Icons.insights_rounded, 'Money coach', 'Explains where your money went and where to save'),
                  _Soon(Icons.wb_twilight_rounded, 'Morning briefing', 'Your day, bills and weather in two lines'),
                  SizedBox(height: 6),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ContentWidth(
            child: Section(
              title: 'Works today',
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.shopping_basket_outlined),
                    title: const Text('Shopping price check'),
                    subtitle: const Text('Your list sorted by the cheapest shop, checked by Claude on your plan'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => open(const ShoppingPage()),
                  ),
                  ListTile(
                    leading: const Icon(Icons.auto_awesome_outlined),
                    title: const Text('Claude'),
                    subtitle: const Text('Plan your day or ask anything in the Claude app'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => open(const ClaudePage()),
                  ),
                  const SizedBox(height: 6),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class SoonBadge extends StatelessWidget {
  const SoonBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(color: aiColor.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(20)),
    child: const Text(
      'Coming soon',
      style: TextStyle(color: aiColor, fontWeight: FontWeight.w700, fontSize: 12.5),
    ),
  );
}

class _Soon extends StatelessWidget {
  const _Soon(this.icon, this.title, this.subtitle);
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) => ListTile(leading: Icon(icon), title: Text(title), subtitle: Text(subtitle));
}

/// One model on offer, with what it is best at.
class AiModel {
  const AiModel(this.id, this.provider, this.name, this.bestFor);
  final String id;
  final String provider;
  final String name;
  final String bestFor;
}

const aiModels = [
  AiModel(
    'anthropic.haiku',
    'Anthropic',
    'Claude Haiku',
    'Everyday tasks: fast and cheap. Recommended for the Hub agent.',
  ),
  AiModel('anthropic.sonnet', 'Anthropic', 'Claude Sonnet', 'Writing, planning and longer questions.'),
  AiModel('anthropic.opus', 'Anthropic', 'Claude Opus', 'The hardest problems; slower and costs more.'),
  AiModel('openai.mini', 'OpenAI', 'GPT mini', 'Quick answers at a low price.'),
  AiModel('openai.gpt', 'OpenAI', 'GPT', 'A strong all-rounder.'),
  AiModel('deepseek.chat', 'DeepSeek', 'DeepSeek Chat', 'Very low cost, good for price checks and search.'),
  AiModel(
    'deepseek.reasoner',
    'DeepSeek',
    'DeepSeek Reasoner',
    'Works through problems step by step, such as budgets.',
  ),
  AiModel('meta.llama', 'Meta', 'Llama', 'Open model; can run on your own laptop server, so nothing leaves home.'),
];

/// Pick the model Hub will use. The choice is kept; keys and calls arrive with the AI update.
class ModelPicker extends StatelessWidget {
  const ModelPicker({super.key});

  static const settingKey = 'ai.model';

  /// 'plan' uses a subscription you already pay for; 'api' pays per use on your own key.
  static const billingKey = 'ai.billing';

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final settings = context.settings;
    final chosen = settings.raw(settingKey) ?? 'anthropic.haiku';
    // The owner's build only ever uses the subscription; no API keys.
    final billing = personalEdition ? 'plan' : settings.raw(billingKey) ?? 'plan';
    String? lastProvider;
    return Section(
      title: 'Model',
      trailing: const Padding(padding: EdgeInsets.only(right: 10), child: SoonBadge()),
      child: RadioGroup<String>(
        groupValue: chosen,
        onChanged: (v) {
          if (v != null) settings.setRaw(settingKey, v);
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final m in aiModels.where((m) => !personalEdition || m.provider == 'Anthropic')) ...[
              if (m.provider != lastProvider) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
                  child: Text(
                    lastProvider = m.provider,
                    style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
              RadioListTile<String>(value: m.id, title: Text(m.name), subtitle: Text(m.bestFor)),
            ],
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Text(
                'How to pay',
                style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            if (!personalEdition)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'plan', label: Text('My subscription')),
                    ButtonSegment(value: 'api', label: Text('API key')),
                  ],
                  selected: {billing},
                  onSelectionChanged: (v) => settings.setRaw(billingKey, v.first),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(
                personalEdition
                    ? 'Uses only your own subscription, through the Claude app on this phone. Hub has no API key '
                          'and never pays per use: every question comes out of your plan.'
                    : billing == 'plan'
                    ? 'Uses the plan you already pay for, such as Claude Pro or ChatGPT Plus, through its own app. '
                          'No extra cost per question. Works today for Claude.'
                    : 'Pay per use with your own key. Costs depend on the model; Haiku, GPT mini and DeepSeek '
                          'cost the least.',
                style: TextStyle(color: p.muted, height: 1.4),
              ),
            ),
            if (billing == 'api')
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: TextField(
                  enabled: false,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.key_rounded),
                    hintText: 'Your API key (coming soon)',
                    helperText: 'Calls go straight from this device to the provider, on your own key.',
                    helperMaxLines: 2,
                    helperStyle: TextStyle(color: p.muted),
                  ),
                ),
              )
            else
              const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
