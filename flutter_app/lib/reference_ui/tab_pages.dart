// Adapted from FlClash lib/pages/home.dart at the revision in UPSTREAM.md.
// GPL-3.0; see assets/flclash-LICENSE.txt.
import 'package:flutter/material.dart';

class FlClashTabPages extends StatefulWidget {
  const FlClashTabPages({
    super.key,
    required this.index,
    required this.children,
  });
  final int index;
  final List<Widget> children;
  @override
  State<FlClashTabPages> createState() => _FlClashTabPagesState();
}

class _FlClashTabPagesState extends State<FlClashTabPages> {
  late final PageController controller = PageController(
    initialPage: widget.index,
  );
  List<int>? order;
  int slide = 0;

  @override
  void didUpdateWidget(covariant FlClashTabPages oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) toPage(widget.index);
  }

  Future<void> toPage(int index) async {
    if (!controller.hasClients) return;
    final generation = ++slide;
    final position = controller.page?.round() ?? index;
    final current = order?[position] ?? position;
    if (order != null) {
      setState(() => order = null);
      controller.jumpToPage(current);
    }
    if (MediaQuery.disableAnimationsOf(context)) {
      controller.jumpToPage(index);
      return;
    }
    // The upstream TabBarView-style permutation skips intermediate pages.
    if ((index - current).abs() > 1) {
      final adjacent = index > current ? index - 1 : index + 1;
      setState(() {
        order = List.generate(widget.children.length, (item) => item)
          ..[adjacent] = current
          ..[current] = adjacent;
      });
      controller.jumpToPage(adjacent);
    }
    await controller.animateToPage(
      index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
    );
    if (mounted && slide == generation && order != null) {
      setState(() => order = null);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PageView.builder(
    controller: controller,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: widget.children.length,
    findChildIndexCallback: (key) =>
        key is ValueKey<int> ? order?.indexOf(key.value) ?? key.value : null,
    itemBuilder: (_, position) {
      final index = order?[position] ?? position;
      return _KeptTab(
        key: ValueKey(index),
        child: AnimatedBuilder(
          animation: controller,
          builder: (_, child) {
            final page =
                controller.hasClients &&
                    controller.position.hasContentDimensions
                ? controller.page ?? position.toDouble()
                : position.toDouble();
            final delta = (position - page).clamp(-1.0, 1.0);
            return FractionalTranslation(
              translation: Offset(-delta, 0),
              child: Opacity(opacity: 1 - delta.abs(), child: child),
            );
          },
          child: TickerMode(
            enabled: index == widget.index,
            child: widget.children[index],
          ),
        ),
      );
    },
  );
}

class _KeptTab extends StatefulWidget {
  const _KeptTab({super.key, required this.child});
  final Widget child;
  @override
  State<_KeptTab> createState() => _KeptTabState();
}

class _KeptTabState extends State<_KeptTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
