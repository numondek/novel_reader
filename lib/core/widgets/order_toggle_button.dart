import 'package:flutter/material.dart';

/// Switches a list between ascending and descending order.
///
/// The icon shows the direction currently displayed; the tooltip
/// names the order a tap switches to.
class OrderToggleButton extends StatelessWidget {
  const OrderToggleButton({
    super.key,
    required this.descending,
    required this.onToggle,
  });

  /// Whether the list is currently shown newest/last-first.
  final bool descending;

  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: descending ? 'Sort ascending' : 'Sort descending',
      icon: Icon(descending ? Icons.arrow_downward : Icons.arrow_upward),
      onPressed: onToggle,
    );
  }
}
