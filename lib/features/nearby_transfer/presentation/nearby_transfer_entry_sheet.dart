import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_radius.dart';
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
    isDismissible: true,
    enableDrag: true,
    isScrollControlled: true,
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
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (context) {
        return NearbyTransferFlowPage(
          store: sessionStore,
          initialStage: selectedStage,
        );
      },
    ),
  );
}

class NearbyTransferFlowPage extends StatelessWidget {
  const NearbyTransferFlowPage({
    required this.store,
    required this.initialStage,
    super.key,
  });

  final NearbyTransferSessionStore store;
  final NearbyTransferEntryStage initialStage;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('nearby-transfer-fullscreen-page'),
      body: NearbyTransferEntrySheet(
        store: store,
        initialStage: initialStage,
        showMenuStage: false,
      ),
    );
  }
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

  String? _resolveRoleBadge() {
    return switch (_stage) {
      NearbyTransferEntryStage.send => 'nearby_transfer.title_send'.tr(),
      NearbyTransferEntryStage.receive => 'nearby_transfer.title_receive'.tr(),
      NearbyTransferEntryStage.menu => null,
    };
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
                    AppSpacing.sm,
                    AppSpacing.sm,
                    AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      if (widget.showMenuStage &&
                          _stage != NearbyTransferEntryStage.menu)
                        IconButton(
                          tooltip: 'nearby_transfer.back'.tr(),
                          onPressed: _handleBackToMenuRequested,
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'nearby_transfer.title'.tr(),
                              style: Theme.of(context).textTheme.titleLarge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (_resolveRoleBadge() != null)
                              Text(
                                _resolveRoleBadge()!,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: AppColors.textSecondary),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
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
                const Divider(height: 1, color: AppColors.mutedBorder),
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
        return SingleChildScrollView(
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

  Future<void> _handleBackToMenuRequested() async {
    if (_store.hasActiveConnection) {
      final confirmed = await _confirmDisconnectDialog();
      if (!confirmed) {
        return;
      }
    }
    await _store.resetForEntrySelection();
    if (!mounted) {
      return;
    }
    setState(() {
      _stage = NearbyTransferEntryStage.menu;
    });
  }

  Future<void> _handleCloseRequested() async {
    if (!_store.hasActiveConnection) {
      await _store.resetForEntrySelection();
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      return;
    }
    await _handleDisconnectRequested(popAfterDisconnect: true);
  }

  Future<bool> _confirmDisconnectDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text('nearby_transfer.disconnect_title'.tr()),
          content: Text('nearby_transfer.disconnect_message'.tr()),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('nearby_transfer.disconnect_confirm'.tr()),
            ),
          ],
        );
      },
    );
    return confirmed == true;
  }

  Future<void> _handleDisconnectRequested({
    bool popAfterDisconnect = false,
  }) async {
    final confirmed = await _confirmDisconnectDialog();
    if (!confirmed) {
      return;
    }
    await _store.disconnect();
    if (!mounted) {
      return;
    }
    if (popAfterDisconnect) {
      await _store.resetForEntrySelection();
      if (!mounted) {
        return;
      }
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
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: DecoratedBox(
          key: const Key('nearby-transfer-launcher-sheet'),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.lg),
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
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'nearby_transfer.close'.tr(),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                'nearby_transfer.subtitle_entry'.tr(),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
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
      ),
    );
  }
}
