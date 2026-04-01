import 'package:flutter/material.dart';

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
              title: const Text('Add shared folder'),
              subtitle: const Text('Create lightweight cache index for folder'),
              onTap: () {
                Navigator.of(context).pop(_DiscoveryAddShareAction.folder);
              },
            ),
            ListTile(
              leading: const Icon(Icons.note_add_outlined),
              title: const Text('Add shared files'),
              subtitle: const Text('Create lightweight cache index for files'),
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
