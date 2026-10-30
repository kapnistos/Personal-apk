import 'package:flutter/material.dart';

import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../claude/claude_page.dart';
import '../shopping/shopping_page.dart';
import 'ai_chat_page.dart';
import 'ai_service.dart';

export 'ai_service.dart' show aiModels, AiModel;

const aiColor = Color(0xFF4D6BFE);

/// The AI tab: chat, the Hub agent, the model to use and how to pay for it.
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
                    const AppGlyph(icon: Icons.auto_awesome_rounded, color: aiColor, size: 44),
                    const SizedBox(height: 16),
                    Text('Your own assistant, inside Hub', style: text.headlineSmall),
                    const SizedBox(height: 6),
                    Text(
                      'Chat with the model you pick, or let the Hub agent add expenses, notes, tasks, events '
                      'and shopping for you.',
                      style: TextStyle(color: p.muted, height: 1.4),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: aiColor,
                            foregroundColor: Colors.white,
                            shape: const StadiumBorder(),
                          ),
                          onPressed: () => open(const AiChatPage()),
                          icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                          label: const Text('Chat'),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                          onPressed: () => open(const AiChatPage(agent: true)),
                          icon: const Icon(Icons.support_agent_rounded, size: 18),
                          label: const Text('Hub agent'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const ContentWidth(child: ModelPicker()),
          const SizedBox(height: 12),
          ContentWidth(
            child: Section(
              title: 'Works today',
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.support_agent_rounded),
                    title: const Text('Hub agent'),
                    subtitle: const Text('Say "12 euro lunch" or "note: call the landlord". You confirm each change'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => open(const AiChatPage(agent: true)),
                  ),
                  ListTile(
                    leading: const Icon(Icons.shopping_basket_outlined),
                    title: const Text('Shopping price check'),
                    subtitle: const Text('Your list sorted by the cheapest shop'),
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
          const SizedBox(height: 12),
          const ContentWidth(
            child: Section(
              title: 'Coming soon',
              trailing: Padding(padding: EdgeInsets.only(right: 10), child: SoonBadge()),
              child: Column(
                children: [
                  _Soon(
                    Icons.smart_toy_outlined,
                    'Add your own agents',
                    'Connect personal agents, such as Instinct, and let them act on your Hub',
                  ),
                  _Soon(Icons.insights_rounded, 'Money coach', 'Explains where your money went and where to save'),
                  _Soon(Icons.wb_twilight_rounded, 'Morning briefing', 'Your day, bills and weather in two lines'),
                  SizedBox(height: 6),
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

/// Pick the model Hub uses and how to pay: your subscription through the Claude app, or your own API key.
class ModelPicker extends StatelessWidget {
  const ModelPicker({super.key});

  static const settingKey = AiSettings.model;
  static const billingKey = AiSettings.billing;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final settings = context.settings;
    final ai = AiSetup(settings);
    final chosen = ai.model;
    final billing = ai.useApi ? 'api' : 'plan';
    AiProvider? lastProvider;
    Widget label(String t, {double top = 12}) => Padding(
      padding: EdgeInsets.fromLTRB(16, top, 16, 6),
      child: Text(
        t,
        style: TextStyle(color: p.muted, fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
    return Section(
      title: 'Model',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          label('How to pay', top: 4),
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
              billing == 'plan'
                  ? 'Uses your Claude plan through the Claude app. One tap opens Claude with the question; '
                        'copy the answer, come back, and Hub offers to use it. No cost per question.'
                  : 'Hub calls the model straight from this device on your own key. You pay the provider per use; '
                        'Haiku, GPT mini and DeepSeek cost the least.',
              style: TextStyle(color: p.muted, height: 1.4),
            ),
          ),
          if (billing == 'api') ApiKeyBox(key: ValueKey(chosen.provider), model: chosen),
          RadioGroup<String>(
            groupValue: chosen.id,
            onChanged: (v) {
              if (v != null) settings.setRaw(settingKey, v);
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final m in aiModels) ...[
                  if (m.provider != lastProvider) label((lastProvider = m.provider).label),
                  RadioListTile<String>(value: m.id, title: Text(m.name), subtitle: Text(m.bestFor)),
                ],
              ],
            ),
          ),
          if (billing == 'plan')
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: Text(
                'With your subscription, questions go to the Claude app. The other models need an API key.',
                style: TextStyle(color: p.muted, fontSize: 13, height: 1.4),
              ),
            )
          else
            const SizedBox(height: 12),
        ],
      ),
    );
  }
}

/// The key for the chosen model's provider, kept only in the device keystore.
class ApiKeyBox extends StatefulWidget {
  const ApiKeyBox({super.key, required this.model});
  final AiModel model;

  @override
  State<ApiKeyBox> createState() => _ApiKeyBoxState();
}

class _ApiKeyBoxState extends State<ApiKeyBox> {
  final _key = TextEditingController();
  final _modelId = TextEditingController();
  final _url = TextEditingController();
  bool _hidden = true;
  bool _testing = false;
  String? _status;
  bool _ok = false;

  AiProvider get _provider => widget.model.provider;

  /// Read without listening, so it is safe in initState.
  AppSettings get _settings => context.getInheritedWidgetOfExactType<Hub>()!.settings;

  @override
  void initState() {
    super.initState();
    final settings = _settings;
    final ai = AiSetup(settings);
    _modelId.text = settings.raw(AiSettings.modelIdKey(widget.model.id)) ?? '';
    _url.text = settings.raw(AiSettings.llamaUrl) ?? '';
    ai.keyFor(_provider).then((k) {
      if (mounted && _key.text.isEmpty) setState(() => _key.text = k);
    });
  }

  @override
  void didUpdateWidget(ApiKeyBox old) {
    super.didUpdateWidget(old);
    if (old.model.id != widget.model.id) {
      _modelId.text = _settings.raw(AiSettings.modelIdKey(widget.model.id)) ?? '';
    }
  }

  @override
  void dispose() {
    _key.dispose();
    _modelId.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ai = AiSetup(_settings);
    await ai.saveKey(_provider, _key.text);
    if (mounted) {
      setState(() {
        _ok = true;
        _status = _key.text.trim().isEmpty ? 'Key removed' : 'Key saved on this device';
      });
    }
  }

  Future<void> _test() async {
    setState(() {
      _testing = true;
      _status = null;
    });
    final ai = AiSetup(_settings);
    try {
      final r = await ai.testKey(_provider, _key.text);
      await ai.saveKey(_provider, _key.text);
      _ok = true;
      _status = 'Key works and is saved. That test used ${r.inputTokens + r.outputTokens} tokens.';
    } on AiException catch (e) {
      _ok = false;
      _status = e.message;
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final settings = context.settings;
    final llama = _provider == AiProvider.llama;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _key,
            obscureText: _hidden,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.key_rounded),
              labelText: llama ? 'API key (not needed for Ollama)' : '${_provider.label} API key',
              helperText: 'Kept only in this device\'s secure storage. Never in backups or sync.',
              helperMaxLines: 2,
              helperStyle: TextStyle(color: p.muted),
              suffixIcon: IconButton(
                tooltip: _hidden ? 'Show key' : 'Hide key',
                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
                onPressed: _save,
                child: const Text('Save'),
              ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                onPressed: _testing ? null : _test,
                icon: _testing
                    ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.bolt_rounded, size: 18),
                label: const Text('Test key'),
              ),
            ],
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(_status!, style: TextStyle(color: _ok ? p.positive : p.danger, height: 1.4)),
            ),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Advanced'),
              childrenPadding: const EdgeInsets.only(bottom: 8),
              children: [
                TextField(
                  controller: _modelId,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Model id for ${widget.model.name}',
                    hintText: widget.model.defaultModelId,
                    helperText: 'Leave empty for ${widget.model.defaultModelId}',
                    helperStyle: TextStyle(color: p.muted),
                  ),
                  onChanged: (v) => settings.setRaw(AiSettings.modelIdKey(widget.model.id), v.trim(), quiet: true),
                ),
                if (llama) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _url,
                    autocorrect: false,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      labelText: 'Server address',
                      hintText: AiSettings.defaultLlamaUrl,
                      helperText: 'Groq, OpenRouter, or Ollama on your laptop: http://<laptop>:11434/v1',
                      helperMaxLines: 2,
                      helperStyle: TextStyle(color: p.muted),
                    ),
                    onChanged: (v) => settings.setRaw(AiSettings.llamaUrl, v.trim(), quiet: true),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
