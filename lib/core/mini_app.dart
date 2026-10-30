import 'package:flutter/material.dart';

/// A mini-app is one tile on the home screen and the page it opens.
///
/// To add a new mini-app, create a folder under lib/apps, describe it with a
/// [MiniApp], and add it to the list in lib/apps/registry.dart.
class MiniApp {
  const MiniApp({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.builder,
    this.available = true,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final WidgetBuilder builder;

  /// False shows the tile as "coming soon" and does not open it.
  final bool available;

  void open(BuildContext context) {
    if (!available) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$title is coming in a later phase.')));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: builder));
  }
}
