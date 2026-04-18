import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';

import '../application/discovery_controller.dart';

enum _DiscoveryAddShareAction { folder, files }

Future<bool> showDiscoveryAddShareSheet({
  required BuildContext context,
  required DiscoveryController controller,
}) async {
  final action = await showModalBottomSheet<_DiscoveryAddShareAction>(
    context: context,
    builder: (context) {
      return SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.create_new_folder_outlined),
              title: Text('discovery.share_sheet.add_shared_folder'.tr()),
              subtitle: Text(
                'discovery.share_sheet.add_shared_folder_description'.tr(),
              ),
              onTap: () {
                Navigator.of(context).pop(_DiscoveryAddShareAction.folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: Text('discovery.share_sheet.add_shared_files'.tr()),
              subtitle: Text(
                'discovery.share_sheet.add_shared_files_description'.tr(),
              ),
              onTap: () {
                Navigator.of(context).pop(_DiscoveryAddShareAction.files);
              },
            ),
          ],
        ),
      );
    },
  );

  if (action == null) {
    return false;
  }

  switch (action) {
    case _DiscoveryAddShareAction.folder:
      await controller.addSharedFolder();
    case _DiscoveryAddShareAction.files:
      await controller.addSharedFiles();
  }
  return true;
}
