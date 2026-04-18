import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:landa/features/settings/domain/app_settings.dart';
import 'package:landa/features/settings/presentation/app_settings_tab_sections.dart';

void main() {
  test(
    'network tab keeps configured discovery target callbacks wired',
    () async {
      final controller = TextEditingController();
      final targets = <String>['100.64.0.2'];
      final removed = <String>[];
      var addCalls = 0;

      final widget = AppSettingsNetworkTab(
        settings: AppSettings.defaults,
        configuredDiscoveryTargets: targets,
        configuredTargetController: controller,
        onAddConfiguredTarget: () async {
          addCalls += 1;
          targets.add(controller.text.trim());
        },
        onRemoveConfiguredTarget: (value) async {
          removed.add(value);
          targets.remove(value);
        },
        onBackgroundIntervalChanged: (_) {},
        onDownloadAttemptNotificationsChanged: (_) {},
      );

      controller.text = '100.64.0.8';
      await widget.onAddConfiguredTarget();
      expect(addCalls, 1);
      expect(targets, contains('100.64.0.8'));

      await widget.onRemoveConfiguredTarget('100.64.0.2');
      expect(removed, <String>['100.64.0.2']);
      expect(targets, isNot(contains('100.64.0.2')));
    },
  );
}
