import 'dart:async';

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
                Text('Friends', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Friendship requires confirmation from both devices.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: AppSpacing.sm),
                TabBar(
                  tabs: [
                    Tab(text: 'Friends (${friends.length})'),
                    Tab(text: 'Requests (${requests.length})'),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Expanded(
                  child: TabBarView(
                    children: [
                      friends.isEmpty
                          ? const Center(
                              child: Text(
                                'No friends yet.\nOpen a device menu and send a friend request.',
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
                                    'MAC ${friend.macAddress}',
                                  if (friend.operatingSystem != null &&
                                      friend.operatingSystem!.isNotEmpty)
                                    'OS ${friend.operatingSystem}',
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
                                      tooltip: 'Remove from friends',
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
                          ? const Center(
                              child: Text('No pending friend requests.'),
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
                                      '${request.senderIp} • MAC ${request.senderMacAddress}\n'
                                      'Received ${_formatTime(request.createdAt)}',
                                    ),
                                    isThreeLine: true,
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          tooltip: 'Decline',
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
                                          tooltip: 'Accept',
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
