import 'package:flutter/material.dart';

/// A horizontal scroll view with an **always-visible scrollbar**, for wide
/// content like a [DataTable]. The desktop table screens previously used a
/// bare horizontal `SingleChildScrollView`, so on a laptop the rightmost
/// columns (e.g. the Users "Actions" column) sat off-screen with no hint
/// that you could scroll to them. Pair it with an outer vertical
/// `SingleChildScrollView` when the table can be taller than its panel.
class ScrollableTable extends StatefulWidget {
  final Widget child;

  const ScrollableTable({super.key, required this.child});

  @override
  State<ScrollableTable> createState() => _ScrollableTableState();
}

class _ScrollableTableState extends State<ScrollableTable> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      controller: _controller,
      thumbVisibility: true,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 12),
        child: widget.child,
      ),
    );
  }
}
