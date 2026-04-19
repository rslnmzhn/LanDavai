import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_spacing.dart';
import '../application/nearby_transfer_session_store.dart';
import 'nearby_transfer_receive_view.dart';
import 'nearby_transfer_send_view.dart';

enum NearbyTransferEntryStage { menu, send, receive }

Future<void> showNearbyTransferEntrySheet({
  required BuildContext context,
  required NearbyTransferSessionStore sessionStore,
}) async {
  final selectedStage = await showModalBottomSheet<NearbyTransferEntryStage>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    builder: (context) {
      return const _NearbyTransferModeChooserSheet();
    },
  );
  if (selectedStage == null) {
    return;
  }
  if (selectedStage == NearbyTransferEntryStage.send) {
    await sessionStore.prepareSendFlow();
  } else {
    await sessionStore.prepareReceiveFlow();
  }
  if (!context.mounted) {
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    builder: (context) {
      return FractionallySizedBox(
        heightFactor: 0.92,
        child: NearbyTransferEntrySheet(
          store: sessionStore,
          initialStage: selectedStage,
          showMenuStage: false,
        ),
      );
    },
  );
}

class NearbyTransferEntrySheet extends StatefulWidget {
  const NearbyTransferEntrySheet({
    required this.store,
    this.initialStage = NearbyTransferEntryStage.menu,
    this.showMenuStage = true,
    super.key,
  });

  final NearbyTransferSessionStore store;
  final NearbyTransferEntryStage initialStage;
  final bool showMenuStage;

  @override
  State<NearbyTransferEntrySheet> createState() =>
      _NearbyTransferEntrySheetState();
}

class _NearbyTransferEntrySheetState extends State<NearbyTransferEntrySheet> {
  late NearbyTransferEntryStage _stage;

  NearbyTransferSessionStore get _store => widget.store;

  @override
  void initState() {
    super.initState();
    _stage = widget.initialStage;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_store.hasActiveConnection,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        unawaited(_handleCloseRequested());
      },
      child: AnimatedBuilder(
        animation: _store,
        builder: (context, _) {
          return SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      if (widget.showMenuStage &&
                          _stage != NearbyTransferEntryStage.menu)
                        IconButton(
                          onPressed: () async {
                            await _store.resetForEntrySelection();
                            if (!mounted) {
                              return;
                            }
                            setState(() {
                              _stage = NearbyTransferEntryStage.menu;
                            });
                          },
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      Expanded(
                        child: Text(
                          'nearby_transfer.title'.tr(),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        tooltip: 'nearby_transfer.close'.tr(),
                        onPressed: _handleCloseRequested,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: _buildStage(context)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStage(BuildContext context) {
    switch (_stage) {
      case NearbyTransferEntryStage.menu:
        if (!widget.showMenuStage) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: () async {
                  await _store.prepareReceiveFlow();
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _stage = NearbyTransferEntryStage.receive;
                  });
                },
                icon: const Icon(Icons.download_rounded),
                label: Text('nearby_transfer.receive_files'.tr()),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: () async {
                  await _store.prepareSendFlow();
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _stage = NearbyTransferEntryStage.send;
                  });
                },
                icon: const Icon(Icons.upload_rounded),
                label: Text('nearby_transfer.send_files'.tr()),
              ),
            ],
          ),
        );
      case NearbyTransferEntryStage.send:
        return NearbyTransferSendView(
          store: _store,
          onDisconnectRequested: _handleDisconnectRequested,
        );
      case NearbyTransferEntryStage.receive:
        return NearbyTransferReceiveView(
          store: _store,
          onDisconnectRequested: _handleDisconnectRequested,
        );
    }
  }

  Future<void> _handleCloseRequested() async {
    if (!_store.hasActiveConnection) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      return;
    }
    await _handleDisconnectRequested(popAfterDisconnect: true);
  }

  Future<void> _handleDisconnectRequested({
    bool popAfterDisconnect = false,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('nearby_transfer.disconnect_title'.tr()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('nearby_transfer.disconnect_confirm'.tr()),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await _store.disconnect();
    if (!mounted) {
      return;
    }
    if (popAfterDisconnect) {
      Navigator.of(context, rootNavigator: true).pop();
      return;
    }
    setState(() {});
  }
}

class _NearbyTransferModeChooserSheet extends StatelessWidget {
  const _NearbyTransferModeChooserSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.md,
          AppSpacing.lg,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'nearby_transfer.title'.tr(),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'nearby_transfer.close'.tr(),
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(context).pop(NearbyTransferEntryStage.receive);
              },
              icon: const Icon(Icons.download_rounded),
              label: Text('nearby_transfer.receive_files'.tr()),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop(NearbyTransferEntryStage.send);
              },
              icon: const Icon(Icons.upload_rounded),
              label: Text('nearby_transfer.send_files'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
