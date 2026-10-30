import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/db/database.dart';
import '../../core/settings.dart';
import '../../core/theme.dart';
import '../../core/widgets.dart';
import '../claude/claude_bridge.dart';
import 'shopping_model.dart';

/// One list for everything, grouped by the shop where each item is cheapest.
class ShoppingPage extends StatefulWidget {
  const ShoppingPage({super.key});

  @override
  State<ShoppingPage> createState() => _ShoppingPageState();
}

class _ShoppingPageState extends State<ShoppingPage> {
  final _input = TextEditingController();
  final _focus = FocusNode();
  bool _byShop = true;

  @override
  void dispose() {
    _input.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final db = context.db;
    final settings = context.settings;
    final cheapest = cheapestMap(settings);
    final remembered = rememberedStores(settings);
    for (final (name, qty) in parseShoppingInput(_input.text)) {
      await db.addShoppingItem(
        name,
        quantity: qty,
        category: categorize(name),
        store: suggestStore(name, cheapest, remembered),
      );
    }
    _input.clear();
    _focus.requestFocus();
  }

  Future<void> _sortAll(List<ShoppingItem> items) async {
    final db = context.db;
    final cheapest = cheapestMap(context.settings);
    final remembered = rememberedStores(context.settings);
    for (final i in items.where((i) => !i.done)) {
      await db.updateShoppingItem(
        i.id,
        category: categorize(i.name),
        store: suggestStore(i.name, cheapest, remembered),
      );
    }
    setState(() => _byShop = true);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Sorted by the cheapest shop for each item')));
    }
  }

  Future<void> _askClaude(List<ShoppingItem> items) async {
    final open = items.where((i) => !i.done).map((i) => i.quantity.isEmpty ? i.name : '${i.name} (${i.quantity})');
    if (open.isEmpty) return;
    final city = context.settings.raw('shopping.city') ?? 'Eindhoven';
    await ClaudeBridge.ask(context, shoppingPrompt(open.toList(), city));
  }

  Future<void> _pasteAnswer(List<ShoppingItem> items) async {
    final db = context.db;
    final settings = context.settings;
    final messenger = ScaffoldMessenger.of(context);
    final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    if (!mounted) return;
    final c = TextEditingController(text: clip);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Claude's answer"),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: c,
            maxLines: 10,
            minLines: 5,
            decoration: const InputDecoration(hintText: 'Paste the reply here (pasta → Albert Heijn …)'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Apply')),
        ],
      ),
    );
    if (ok != true) return;
    final plan = parseStorePlan(c.text, items.map((i) => i.name));
    for (final i in items) {
      final store = plan[i.name.trim().toLowerCase()];
      if (store == null) continue;
      await db.updateShoppingItem(i.id, store: store);
      await rememberStore(settings, i.name, store);
    }
    setState(() => _byShop = true);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          plan.isEmpty ? 'Could not read any shops in that text' : 'Moved ${plan.length} items to their shops',
        ),
      ),
    );
  }

  Future<void> _edit(ShoppingItem item) async {
    final db = context.db;
    final settings = context.settings;
    final name = TextEditingController(text: item.name);
    final qty = TextEditingController(text: item.quantity);
    var store = item.store;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Item'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: qty,
                      decoration: const InputDecoration(labelText: 'How many'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const SectionLabel('Buy at'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in knownStores.keys)
                    ChoiceChip(
                      showCheckmark: false,
                      avatar: CircleAvatar(radius: 5, backgroundColor: storeColor(s)),
                      label: Text(s),
                      selected: store == s,
                      onSelected: (v) => setSheet(() => store = v ? s : ''),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Hub remembers this shop for "${item.name}" next time.',
                style: TextStyle(color: Palette.of(context).muted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(onPressed: () => Navigator.pop(context, 'delete'), child: const Text('Delete')),
                  const Spacer(),
                  FilledButton(onPressed: () => Navigator.pop(context, 'save'), child: const Text('Save')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (result == 'delete') {
      await db.deleteShoppingItem(item.id);
      if (mounted) showUndo(context, '${item.name} removed', () => db.restoreShoppingItem(item));
    }
    if (result == 'save' && name.text.trim().isNotEmpty) {
      await db.updateShoppingItem(
        item.id,
        name: name.text.trim(),
        quantity: qty.text.trim(),
        store: store,
        category: categorize(name.text),
      );
      if (store.isNotEmpty && store != item.store) await rememberStore(settings, name.text, store);
    }
  }

  @override
  Widget build(BuildContext context) {
    final db = context.db;
    final p = Palette.of(context);
    return StreamBuilder<List<ShoppingItem>>(
      stream: db.watchShopping(),
      builder: (context, snap) {
        final items = snap.data ?? const <ShoppingItem>[];
        final open = items.where((i) => !i.done).toList();
        final bought = items.where((i) => i.done).toList();
        final groups = <String, List<ShoppingItem>>{};
        for (final i in open) {
          final key = _byShop
              ? (i.store.isEmpty ? 'Anywhere' : i.store)
              : (i.category.isEmpty ? otherCategory : i.category);
          (groups[key] ??= []).add(i);
        }
        final keys = groups.keys.toList()
          ..sort((a, b) {
            if (a == 'Anywhere') return 1;
            if (b == 'Anywhere') return -1;
            return groups[b]!.length.compareTo(groups[a]!.length);
          });
        return Scaffold(
          appBar: AppBar(
            title: const Text('Shopping'),
            actions: [
              IconButton(
                tooltip: 'Which shop for what',
                icon: const Icon(Icons.tune_rounded),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ShopRulesPage())),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'sort') await _sortAll(items);
                  if (v == 'claude') await _askClaude(items);
                  if (v == 'paste') await _pasteAnswer(items);
                  if (v == 'clear') await db.clearBoughtShopping();
                  if (v == 'copy') {
                    final text = keys
                        .map(
                          (k) =>
                              '$k\n${groups[k]!.map((i) => '- ${i.name}${i.quantity.isEmpty ? '' : ' (${i.quantity})'}').join('\n')}',
                        )
                        .join('\n\n');
                    await Clipboard.setData(ClipboardData(text: text));
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'sort', child: Text('Sort by cheapest shop')),
                  PopupMenuItem(value: 'claude', child: Text('Ask Claude for the best prices')),
                  PopupMenuItem(value: 'paste', child: Text("Use Claude's answer")),
                  PopupMenuItem(value: 'copy', child: Text('Copy list')),
                  PopupMenuItem(value: 'clear', child: Text('Clear bought items')),
                ],
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            children: [
              ContentWidth(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            focusNode: _focus,
                            textCapitalization: TextCapitalization.sentences,
                            textInputAction: TextInputAction.done,
                            onSubmitted: (_) => _add(),
                            decoration: const InputDecoration(
                              hintText: 'pasta, deodorant, 2x toilet paper',
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                            ),
                          ),
                        ),
                        IconButton.filled(onPressed: _add, icon: const Icon(Icons.add_rounded)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ContentWidth(
                child: Row(
                  children: [
                    SegmentedButton<bool>(
                      showSelectedIcon: false,
                      style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
                      segments: const [
                        ButtonSegment(value: true, label: Text('By shop')),
                        ButtonSegment(value: false, label: Text('By aisle')),
                      ],
                      selected: {_byShop},
                      onSelectionChanged: (v) => setState(() => _byShop = v.first),
                    ),
                    const Spacer(),
                    if (open.isNotEmpty)
                      TextButton.icon(
                        onPressed: () => _askClaude(items),
                        icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                        label: const Text('Best prices'),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              if (items.isEmpty)
                const EmptyState(
                  icon: Icons.shopping_basket_outlined,
                  title: 'Nothing to buy',
                  message:
                      'Type everything in one go, separated by commas. Hub puts each item under the shop '
                      'where it is usually cheapest, and you can ask Claude to check.',
                ),
              for (final k in keys)
                ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Card(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Row(
                              children: [
                                if (_byShop)
                                  CircleAvatar(radius: 6, backgroundColor: storeColor(k))
                                else
                                  Icon(categoryIcon(k), size: 18, color: p.muted),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(k, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                ),
                                Text(
                                  '${groups[k]!.length}',
                                  style: TextStyle(color: p.muted, fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          for (final i in groups[k]!) _ItemTile(item: i, byShop: _byShop, onEdit: () => _edit(i)),
                          const SizedBox(height: 6),
                        ],
                      ),
                    ),
                  ),
                ),
              if (bought.isNotEmpty)
                ContentWidth(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Section(
                      title: 'In the basket · ${bought.length}',
                      trailing: TextButton(onPressed: db.clearBoughtShopping, child: const Text('Clear')),
                      child: Column(
                        children: [
                          for (final i in bought) _ItemTile(item: i, byShop: _byShop, onEdit: () => _edit(i)),
                          const SizedBox(height: 6),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ItemTile extends StatelessWidget {
  const _ItemTile({required this.item, required this.byShop, required this.onEdit});
  final ShoppingItem item;
  final bool byShop;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final db = context.db;
    return Dismissible(
      key: ValueKey('shop-${item.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: p.danger.withValues(alpha: 0.12),
        child: Icon(Icons.delete_outline_rounded, color: p.danger),
      ),
      onDismissed: (_) async {
        await db.deleteShoppingItem(item.id);
        if (context.mounted) showUndo(context, '${item.name} removed', () => db.restoreShoppingItem(item));
      },
      child: ListTile(
        dense: true,
        leading: Checkbox(
          shape: const CircleBorder(),
          value: item.done,
          onChanged: (v) => db.updateShoppingItem(item.id, done: v ?? false),
        ),
        title: Text(
          item.name,
          style: TextStyle(
            fontSize: 15.5,
            decoration: item.done ? TextDecoration.lineThrough : null,
            color: item.done ? p.muted : null,
          ),
        ),
        subtitle: Text(
          [
            if (item.quantity.isNotEmpty) item.quantity,
            if (byShop && item.category.isNotEmpty && item.category != otherCategory) item.category,
            if (!byShop && item.store.isNotEmpty) item.store,
          ].join(' · '),
          style: TextStyle(color: p.muted, fontSize: 13),
        ),
        trailing: IconButton(
          tooltip: 'Change',
          icon: Icon(Icons.storefront_outlined, color: p.muted, size: 20),
          onPressed: onEdit,
        ),
        onTap: () => db.updateShoppingItem(item.id, done: !item.done),
        onLongPress: onEdit,
      ),
    );
  }
}

/// Which shop is cheapest for each kind of item, and the city Claude should think about.
class ShopRulesPage extends StatefulWidget {
  const ShopRulesPage({super.key});

  @override
  State<ShopRulesPage> createState() => _ShopRulesPageState();
}

class _ShopRulesPageState extends State<ShopRulesPage> {
  late Map<String, String> _map = cheapestMap(context.settings);
  late final _city = TextEditingController(text: context.settings.raw('shopping.city') ?? 'Eindhoven');

  @override
  void dispose() {
    _city.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = Palette.of(context);
    final settings = context.settings;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cheapest shops'),
        actions: [
          TextButton(
            onPressed: () async {
              setState(() => _map = {...defaultCheapest});
              await saveCheapestMap(settings, _map);
            },
            child: const Text('Reset'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          ContentWidth(
            child: Text(
              'New items go to the shop set here for their kind, unless you moved that item before. '
              '"Best prices" asks Claude, using your Claude plan, to check against current offers.',
              style: TextStyle(color: p.muted),
            ),
          ),
          const SizedBox(height: 12),
          ContentWidth(
            child: Card(
              child: Column(
                children: [
                  for (final c in [...shopCategories.map((c) => c.name), otherCategory])
                    ListTile(
                      leading: Icon(categoryIcon(c)),
                      title: Text(c),
                      trailing: DropdownButton<String>(
                        value: knownStores.containsKey(_map[c]) ? _map[c] : null,
                        underline: const SizedBox.shrink(),
                        items: [for (final s in knownStores.keys) DropdownMenuItem(value: s, child: Text(s))],
                        onChanged: (v) async {
                          if (v == null) return;
                          setState(() => _map[c] = v);
                          await saveCheapestMap(settings, _map);
                        },
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ContentWidth(
            child: TextField(
              controller: _city,
              decoration: const InputDecoration(labelText: 'Your city, for Claude'),
              onChanged: (v) => settings.setRaw('shopping.city', v.trim()),
            ),
          ),
        ],
      ),
    );
  }
}
