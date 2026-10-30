import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import 'ai_service.dart';
import 'ai_usage.dart';
import 'ai_usage_sheet.dart';
import 'ai_widgets.dart';
import 'chat_memory.dart';
import 'claude_plan_box.dart';

/// Opens AI settings: how answers come, the key, the model.
Future<void> showAiSettings(BuildContext context) {
  final settings = context.settings;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // Never the whole screen, so a tap above it closes it.
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
    builder: (_) => AiSettingsSheet(settings: settings),
  );
}

class AiSettingsSheet extends StatelessWidget {
  const AiSettingsSheet({super.key, required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final ai = AiSetup(settings);
        final billing = ai.billing;
        Future<void> setBilling(String v) => settings.setRaw(AiSettings.billing, v);
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            child: ContentWidth(
              maxWidth: 560,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('AI settings', style: Theme.of(context).textTheme.titleLarge),
                  const AiLabel('How it answers', top: 16),
                  AiCheckRow(
                    title: 'Claude Code (my plan)',
                    subtitle: 'Answers in Hub on your Claude plan. No cost per question.',
                    selected: billing == AiSettings.claudeCode,
                    onTap: () => setBilling(AiSettings.claudeCode),
                  ),
                  AiCheckRow(
                    title: 'Claude app (my plan)',
                    subtitle: 'Opens Claude with your question. Copy the answer and come back.',
                    selected: billing == 'plan',
                    onTap: () => setBilling('plan'),
                  ),
                  AiCheckRow(
                    title: 'API key',
                    subtitle: 'Paste a key from OpenRouter, Anthropic, OpenAI, DeepSeek or Groq. You pay per use.',
                    selected: billing == 'api',
                    onTap: () => setBilling('api'),
                  ),
                  if (billing == AiSettings.claudeCode) ...[
                    const AiLabel('Model'),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: PillToggle<String>(
                        options: const [('haiku', 'Haiku'), ('sonnet', 'Sonnet'), ('opus', 'Opus')],
                        value: ai.planAlias,
                        onChanged: (v) => settings.setRaw(AiSettings.claudeCodeModel, v),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const ClaudePlanBox(),
                  ],
                  if (billing == 'api') ...[
                    const AiLabel('Your key'),
                    ApiKeyBox(settings: settings),
                    const AiLabel('Model'),
                    if (ai.model.provider == AiProvider.openrouter)
                      _OpenRouterModelRow(ai: ai)
                    else
                      for (final m in aiModels.where((m) => m.provider == ai.model.provider))
                        AiCheckRow(
                          title: m.name,
                          subtitle: m.bestFor,
                          selected: ai.model.id == m.id,
                          onTap: () => settings.setRaw(AiSettings.model, m.id),
                        ),
                  ],
                  const AiLabel('Chat'),
                  AiCheckRow(
                    title: 'Let Chat see my Hub',
                    subtitle:
                        'Chat can look at your calendar, wallet, tasks and notes when a question needs them. '
                        'The Hub agent always can.',
                    selected: ChatMemory(settings).shareContext,
                    onTap: () => ChatMemory(settings).setShareContext(!ChatMemory(settings).shareContext),
                  ),
                  const AiLabel('Usage'),
                  _UsageRow(settings: settings),
                  const SizedBox(height: 20),
                  Text(
                    'Coming soon: your own agents, such as Instinct, working on your Hub.',
                    style: TextStyle(color: p.muted, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Today's and this month's tokens and cost in one line; tap for the full usage sheet.
class _UsageRow extends StatelessWidget {
  const _UsageRow({required this.settings});
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final usage = AiUsage(settings);
    final now = DateTime.now();
    String line(UsageTotal t) => '${formatTokens(t.tokens)} tokens${t.priced ? ' · ${formatUsd(t.cost)}' : ''}';
    final today = usage.total(from: DateTime(now.year, now.month, now.day));
    final month = usage.total(from: DateTime(now.year, now.month));
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showAiUsage(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Today ${line(today)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('This month ${line(month)}', style: TextStyle(color: p.muted, fontSize: 13.5, height: 1.35)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: p.muted),
            ],
          ),
        ),
      ),
    );
  }
}

/// One paste field for any key. Hub works out whose key it is, checks it and saves it in the
/// device keystore, never the settings table, so it stays out of backups and sync.
class ApiKeyBox extends StatefulWidget {
  const ApiKeyBox({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<ApiKeyBox> createState() => _ApiKeyBoxState();
}

class _ApiKeyBoxState extends State<ApiKeyBox> {
  final _key = TextEditingController();
  final _url = TextEditingController();
  bool _busy = false;
  bool _ok = false;
  String? _status;

  AiSetup get _ai => AiSetup(widget.settings);
  AiProvider get _provider => _ai.model.provider;

  @override
  void initState() {
    super.initState();
    _url.text = widget.settings.raw(AiSettings.llamaUrl) ?? '';
    _loadKey();
  }

  Future<void> _loadKey() async {
    final k = await _ai.keyFor(_provider);
    if (!mounted) return;
    setState(() {
      _key.text = k;
      _ok = k.isNotEmpty;
      _status = k.isEmpty ? null : 'Key saved for ${_provider.label}';
    });
  }

  @override
  void dispose() {
    _key.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (text.isEmpty) {
      setState(() {
        _ok = false;
        _status = 'The clipboard is empty. Copy your key first.';
      });
      return;
    }
    _key.text = text;
    await _connect();
  }

  Future<void> _connect({AiProvider? as}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Checking…';
      _ok = true;
    });
    final ai = _ai;
    try {
      final p = await ai.connect(_key.text, as: as);
      _ok = true;
      _status = 'Connected to ${p.label}';
      if (p == AiProvider.openrouter) await _pickStarterModel(ai);
    } on AiException catch (e) {
      _ok = false;
      _status = e.message;
    } finally {
      ai.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  /// With a fresh OpenRouter key, start on a cheap good model rather than Auto.
  Future<void> _pickStarterModel(AiSetup ai) async {
    if ((widget.settings.raw(AiSettings.openrouterModel) ?? '').isNotEmpty) return;
    try {
      final first = OpenRouterModel.suggested(await ai.openRouterModels()).firstOrNull;
      if (first != null) await widget.settings.setRaw(AiSettings.openrouterModel, first.id);
    } on AiException {
      // Auto still works; the list can be fetched later.
    }
  }

  /// Picking a company by hand: checks the pasted key as theirs, or shows their saved key.
  Future<void> _choose(AiProvider p) async {
    if (p == _provider && _key.text.trim().isEmpty) return;
    final saved = await _ai.keyFor(p);
    final typed = _key.text.trim();
    if (typed.isNotEmpty && typed != saved) {
      await _connect(as: p);
      return;
    }
    await widget.settings.setRaw(AiSettings.model, aiModels.firstWhere((m) => m.provider == p).id);
    await _loadKey();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final provider = _provider;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('ai-key-field'),
                controller: _key,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: InputDecoration(
                  hintText: provider.keyOptional ? 'Paste your API key (Ollama needs none)' : 'Paste your API key',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(22),
                    borderSide: BorderSide(color: p.accent, width: 1.5),
                  ),
                ),
                onSubmitted: (_) => _connect(),
              ),
            ),
            const SizedBox(width: 8),
            AiPill(label: 'Paste', filled: true, busy: _busy, onTap: _paste),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final x in const [
              AiProvider.openrouter,
              AiProvider.anthropic,
              AiProvider.openai,
              AiProvider.deepseek,
              AiProvider.llama,
            ])
              _ProviderPill(label: x.label, selected: x == provider, onTap: () => _choose(x)),
          ],
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              _status!,
              style: TextStyle(color: _busy ? p.muted : (_ok ? p.positive : p.danger), height: 1.4),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            'Kept only in this device\'s secure storage. Never in backups or sync.',
            style: TextStyle(color: p.muted, fontSize: 12.5),
          ),
        ),
        if (provider == AiProvider.llama) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            autocorrect: false,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'Server address',
              hintText: AiSettings.defaultLlamaUrl,
              helperText: 'Groq, or Ollama on your laptop: http://<laptop>:11434/v1',
            ),
            onChanged: (v) => widget.settings.setRaw(AiSettings.llamaUrl, v.trim(), quiet: true),
          ),
        ],
      ],
    );
  }
}

class _ProviderPill extends StatelessWidget {
  const _ProviderPill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    return Semantics(
      button: true,
      selected: selected,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Pressable(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: ShapeDecoration(color: selected ? p.ink : p.raised, shape: const StadiumBorder()),
            child: Text(
              label,
              style: TextStyle(color: selected ? p.background : p.ink, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}

/// The chosen OpenRouter model; tapping opens the searchable list.
class _OpenRouterModelRow extends StatelessWidget {
  const _OpenRouterModelRow({required this.ai});
  final AiSetup ai;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final id = ai.openRouterModel;
    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          builder: (_) => OpenRouterModelSheet(settings: ai.settings),
        ),
        child: Pressable(
          scale: 0.98,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
            decoration: BoxDecoration(color: p.raised, borderRadius: BorderRadius.circular(18)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ai.modelName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      Text(
                        id == AiSettings.defaultOpenRouterModel ? 'OpenRouter picks a model for each question' : id,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: p.muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Change',
                  style: TextStyle(color: p.muted, fontWeight: FontWeight.w600),
                ),
                Icon(Icons.chevron_right_rounded, color: p.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Every model OpenRouter offers today, searchable, with a few suggestions on top.
class OpenRouterModelSheet extends StatefulWidget {
  const OpenRouterModelSheet({super.key, required this.settings});
  final AppSettings settings;

  @override
  State<OpenRouterModelSheet> createState() => _OpenRouterModelSheetState();
}

class _OpenRouterModelSheetState extends State<OpenRouterModelSheet> {
  final _search = TextEditingController();
  List<OpenRouterModel>? _models;
  String? _error;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() => _error = null);
    final ai = AiSetup(widget.settings);
    try {
      final list = await ai.openRouterModels(refresh: refresh);
      if (mounted) setState(() => _models = list);
    } on AiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      ai.close();
    }
  }

  Future<void> _pick(String id) async {
    await widget.settings.setRaw(AiSettings.openrouterModel, id);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final chosen = AiSetup(widget.settings).openRouterModel;
    final all = _models ?? const <OpenRouterModel>[];
    final q = _query.trim().toLowerCase();
    final matches = q.isEmpty
        ? all
        : all.where((m) => m.name.toLowerCase().contains(q) || m.id.toLowerCase().contains(q)).toList();
    final suggested = q.isEmpty ? OpenRouterModel.suggested(all) : const <OpenRouterModel>[];
    final rows = <Widget>[
      if (q.isEmpty) ...[
        AiCheckRow(
          title: 'Auto',
          subtitle: 'OpenRouter picks a model for each question',
          selected: chosen == AiSettings.defaultOpenRouterModel,
          onTap: () => _pick(AiSettings.defaultOpenRouterModel),
        ),
        if (suggested.isNotEmpty) const AiLabel('Suggested', top: 8),
        for (final m in suggested) _row(m, chosen),
        const AiLabel('All models', top: 12),
      ],
      for (final m in matches) _row(m, chosen),
      if (_models != null && matches.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Text('No model matches "$_query"', style: TextStyle(color: p.muted)),
        ),
    ];
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Pick a model', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _search,
                    autocorrect: false,
                    decoration: InputDecoration(
                      hintText: 'Search, e.g. claude, gpt, llama',
                      prefixIcon: Icon(Icons.search_rounded, color: p.muted),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: BorderSide.none),
                    ),
                    onChanged: (v) => setState(() => _query = v),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _models == null
                  ? Center(
                      child: _error == null
                          ? Text('Loading models…', style: TextStyle(color: p.muted))
                          : Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    _error!,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: p.danger, height: 1.4),
                                  ),
                                  const SizedBox(height: 12),
                                  AiPill(label: 'Try again', onTap: () => _load(refresh: true)),
                                ],
                              ),
                            ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                      itemCount: rows.length,
                      itemBuilder: (_, i) => rows[i],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(OpenRouterModel m, String chosen) =>
      AiCheckRow(title: m.name, subtitle: m.details, selected: m.id == chosen, onTap: () => _pick(m.id));
}
