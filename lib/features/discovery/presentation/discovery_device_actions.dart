import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../application/discovery_controller.dart';
import '../domain/discovered_device.dart';

enum _DiscoveryDeviceAction { rename, friend }

Future<void> showDiscoveryDeviceActionsMenu({
  required BuildContext context,
  required DiscoveryController controller,
  required DiscoveredDevice device,
  Offset? globalPosition,
}) async {
  final isFriend = device.isTrusted;
  final hasPendingRequest = controller.hasPendingFriendRequestForDevice(device);
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  final position = globalPosition == null || overlay == null
      ? null
      : RelativeRect.fromRect(
          Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
          Offset.zero & overlay.size,
        );

  final action = await showMenu<_DiscoveryDeviceAction>(
    context: context,
    position: position ?? const RelativeRect.fromLTRB(24, 180, 24, 0),
    items: [
      PopupMenuItem<_DiscoveryDeviceAction>(
        value: _DiscoveryDeviceAction.rename,
        child: ListTile(
          leading: Icon(Icons.edit_outlined),
          title: Text('discovery.device.rename'.tr()),
          contentPadding: EdgeInsets.zero,
        ),
      ),
      PopupMenuItem<_DiscoveryDeviceAction>(
        value: isFriend || hasPendingRequest
            ? null
            : _DiscoveryDeviceAction.friend,
        enabled: !isFriend && !hasPendingRequest,
        child: ListTile(
          leading: Icon(
            isFriend
                ? Icons.check_circle_outline
                : hasPendingRequest
                ? Icons.schedule_rounded
                : Icons.person_add_alt_1_rounded,
          ),
          title: Text(
            isFriend
                ? 'discovery.device.already_friends'.tr()
                : hasPendingRequest
                ? 'discovery.device.friend_request_pending'.tr()
                : 'discovery.device.add_to_friends'.tr(),
          ),
          contentPadding: EdgeInsets.zero,
        ),
      ),
    ],
  );

  if (action == null || !context.mounted) {
    return;
  }

  switch (action) {
    case _DiscoveryDeviceAction.rename:
      await _showDiscoveryRenameDialog(
        context: context,
        controller: controller,
        device: device,
      );
    case _DiscoveryDeviceAction.friend:
      await controller.sendFriendRequest(device);
  }
}

Future<void> _showDiscoveryRenameDialog({
  required BuildContext context,
  required DiscoveryController controller,
  required DiscoveredDevice device,
}) async {
  final initialValue = device.aliasName ?? device.deviceName ?? '';
  final textController = TextEditingController(text: initialValue);
  try {
    final newAlias = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('discovery.device.rename'.tr()),
          content: TextField(
            controller: textController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'discovery.device.rename_custom_name'.tr(),
              helperText: 'discovery.device.rename_helper'.tr(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('common.cancel'.tr()),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(''),
              child: Text('common.reset'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(textController.text),
              child: Text('common.save'.tr()),
            ),
          ],
        );
      },
    );
    if (newAlias == null) {
      return;
    }

    await controller.renameDeviceAlias(device: device, alias: newAlias);
    if (!context.mounted || controller.errorMessage == null) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(controller.errorMessage!)));
  } finally {
    textController.dispose();
  }
}
