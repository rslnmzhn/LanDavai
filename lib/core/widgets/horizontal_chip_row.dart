import 'package:flutter/material.dart';

class HorizontalChipRow extends StatelessWidget {
  const HorizontalChipRow({
    required this.children,
    this.scrollKey,
    this.spacing = 8,
    super.key,
  });

  final List<Widget> children;
  final Key? scrollKey;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          key: scrollKey,
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: _buildSpacedChildren(),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildSpacedChildren() {
    final spaced = <Widget>[];
    for (var index = 0; index < children.length; index += 1) {
      if (index > 0) {
        spaced.add(SizedBox(width: spacing));
      }
      spaced.add(children[index]);
    }
    return spaced;
  }
}
