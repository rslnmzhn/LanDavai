import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../application/discovery_controller.dart';
import '../application/discovery_read_model.dart';

class DiscoveryFriendsSheet extends StatelessWidget {
  const DiscoveryFriendsSheet({
    required this.controller,
    required this.readModel,
    super.key,
  });

  final DiscoveryController controller;
  final DiscoveryReadModel readModel;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[controller, readModel]),
      builder: (context, _) {
        final friends = readModel.friendDevices;
        final requests = controller.incomingFriendRequests;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'discovery.friends_sheet.title'.tr(),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'discovery.friends_sheet.description'.tr(),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                TabBar(
                  tabs: [
                    Tab(
                      text: 'discovery.friends_sheet.tab_friends'.tr(
                        namedArgs: <String, String>{
                          'count': '${friends.length}',
                        },
                      ),
                    ),
                    Tab(
                      text: 'discovery.friends_sheet.tab_requests'.tr(
                        namedArgs: <String, String>{
                          'count': '${requests.length}',
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: TabBarView(
                    children: [
                      friends.isEmpty
                          ? Center(
                              child: Text(
                                'discovery.friends_sheet.empty_friends'.tr(),
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.separated(
                              itemCount: friends.length,
                              separatorBuilder: (_, index) =>
                                  const SizedBox(height: AppSpacing.xs),
                              itemBuilder: (_, index) {
                                final friend = friends[index];
                                final subtitleParts = <String>[
                                  friend.ip,
                                  if (friend.macAddress != null)
                                    'discovery.device.mac_value'.tr(
                                      namedArgs: <String, String>{
                                        'value': friend.macAddress!,
                                      },
                                    ),
                                  if (friend.operatingSystem != null &&
                                      friend.operatingSystem!.isNotEmpty)
                                    'discovery.device.os_value'.tr(
                                      namedArgs: <String, String>{
                                        'value': friend.operatingSystem!,
                                      },
                                    ),
                                ];
                                return Card(
                                  child: ListTile(
                                    leading: const Icon(
                                      Icons.star,
                                      color: AppColors.warning,
                                    ),
                                    title: Text(friend.displayName),
                                    subtitle: Text(subtitleParts.join(' • ')),
                                    trailing: IconButton(
                                      tooltip: 'common.remove_from_friends'
                                          .tr(),
                                      onPressed:
                                          controller.isFriendMutationInProgress
                                          ? null
                                          : () {
                                              unawaited(
                                                controller
                                                    .removeDeviceFromFriends(
                                                      friend,
                                                    ),
                                              );
                                            },
                                      icon: const Icon(
                                        Icons.person_remove_alt_1_rounded,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                      requests.isEmpty
                          ? Center(
                              child: Text(
                                'discovery.friends_sheet.empty_requests'.tr(),
                              ),
                            )
                          : ListView.separated(
                              itemCount: requests.length,
                              separatorBuilder: (_, index) =>
                                  const SizedBox(height: AppSpacing.xs),
                              itemBuilder: (_, index) {
                                final request = requests[index];
                                return Card(
                                  child: ListTile(
                                    leading: const Icon(
                                      Icons.person_add_alt_1_rounded,
                                    ),
                                    title: Text(request.senderName),
                                    subtitle: Text(
                                      '${request.senderIp} • '
                                      '${'discovery.device.mac_value'.tr(namedArgs: <String, String>{'value': request.senderMacAddress})}\n'
                                      '${'discovery.friends_sheet.received_at'.tr(namedArgs: <String, String>{'value': _formatTime(request.createdAt)})}',
                                    ),
                                    isThreeLine: true,
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'common.decline'.tr(),
                                          onPressed:
                                              controller
                                                  .isFriendMutationInProgress
                                              ? null
                                              : () {
                                                  unawaited(
                                                    controller
                                                        .respondToFriendRequest(
                                                          requestId:
                                                              request.requestId,
                                                          accept: false,
                                                        ),
                                                  );
                                                },
                                          icon: const Icon(Icons.close_rounded),
                                        ),
                                        IconButton(
                                          tooltip: 'common.accept'.tr(),
                                          onPressed:
                                              controller
                                                  .isFriendMutationInProgress
                                              ? null
                                              : () {
                                                  unawaited(
                                                    controller
                                                        .respondToFriendRequest(
                                                          requestId:
                                                              request.requestId,
                                                          accept: true,
                                                        ),
                                                  );
                                                },
                                          icon: const Icon(
                                            Icons.check_rounded,
                                            color: AppColors.success,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime time) {
    final date =
        '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')}';
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$date $hh:$mm';
  }
}
