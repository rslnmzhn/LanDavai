import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';

class DiscoveryDesktopLayoutSurface extends StatelessWidget {
  const DiscoveryDesktopLayoutSurface({
    required this.title,
    required this.isLeftHanded,
    required this.content,
    required this.sidePanel,
    required this.actionBar,
    super.key,
  });

  static const double sidePanelWidth = 296;

  final String title;
  final bool isLeftHanded;
  final Widget content;
  final Widget sidePanel;
  final Widget actionBar;

  @override
  Widget build(BuildContext context) {
    final sidePanelSurface = SizedBox(
      key: const Key('discovery-desktop-side-panel'),
      width: sidePanelWidth,
      child: ColoredBox(color: AppColors.surface, child: sidePanel),
    );
    final mainPane = ColoredBox(
      key: const Key('discovery-desktop-content-pane'),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.sm,
              AppSpacing.md,
              AppSpacing.xxs,
            ),
            child: Text(title, style: Theme.of(context).textTheme.titleLarge),
          ),
          Expanded(child: content),
          const Divider(
            height: 1,
            thickness: 1,
            color: AppColors.mutedBorder,
          ),
          KeyedSubtree(
            key: const Key('discovery-desktop-action-bar'),
            child: actionBar,
          ),
        ],
      ),
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: isLeftHanded
          ? <Widget>[
              sidePanelSurface,
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: AppColors.mutedBorder,
              ),
              Expanded(child: mainPane),
            ]
          : <Widget>[
              Expanded(child: mainPane),
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: AppColors.mutedBorder,
              ),
              sidePanelSurface,
            ],
    );
  }
}
