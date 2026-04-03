import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';

class DiscoveryWideLayoutSurface extends StatelessWidget {
  const DiscoveryWideLayoutSurface({
    required this.title,
    required this.mainContent,
    required this.sidePanel,
    required this.actionBar,
    required this.isLeftHanded,
    super.key,
  });

  static const Key headerKey = Key('discovery-wide-layout-header');
  static const Key mainPaneKey = Key('discovery-wide-layout-main-pane');
  static const Key sidePanelKey = Key('discovery-wide-layout-side-panel');
  static const Key actionBarKey = Key('discovery-wide-layout-action-bar');

  final String title;
  final Widget mainContent;
  final Widget sidePanel;
  final Widget actionBar;
  final bool isLeftHanded;

  @override
  Widget build(BuildContext context) {
    final divider = const VerticalDivider(
      width: 1,
      thickness: 1,
      color: AppColors.mutedBorder,
    );
    final keyedSidePanel = KeyedSubtree(key: sidePanelKey, child: sidePanel);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isLeftHanded) ...[keyedSidePanel, divider],
        Expanded(
          key: mainPaneKey,
          child: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: SafeArea(
              bottom: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md,
                      AppSpacing.sm,
                      AppSpacing.md,
                      AppSpacing.sm,
                    ),
                    child: Text(
                      title,
                      key: headerKey,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  Expanded(child: mainContent),
                  const Divider(
                    height: 1,
                    thickness: 1,
                    color: AppColors.mutedBorder,
                  ),
                  KeyedSubtree(key: actionBarKey, child: actionBar),
                ],
              ),
            ),
          ),
        ),
        if (!isLeftHanded) ...[divider, keyedSidePanel],
      ],
    );
  }
}
