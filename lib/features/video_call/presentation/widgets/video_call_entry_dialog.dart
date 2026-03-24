import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../../../core/services/supabase_client.dart';

class VideoCallJoinResult {
  const VideoCallJoinResult({
    required this.roomId,
    required this.audioDeviceId,
    required this.videoDeviceId,
  });

  final String roomId;
  final String? audioDeviceId;
  final String? videoDeviceId;
}

Future<VideoCallJoinResult?> showVideoCallEntryDialog({
  required BuildContext context,
  required String projectId,
  required String displayName,
}) async {
  // Context may become invalid while we await network/devices calls.
  if (!context.mounted) return null;

  final client = SupabaseClientService.instance.client;
  final currentUserId = SupabaseClientService.instance.currentUserId;
  if (currentUserId == null) return null;

  // Existing room (latest) for this project
  final roomQuery = await client
      .from('video_call_rooms')
      .select('id,created_at')
      .eq('project_id', projectId)
      .order('created_at', ascending: false)
      .limit(1)
      .maybeSingle();

  final roomId = roomQuery == null ? null : roomQuery['id'] as String?;

  final participants = roomId == null
      ? <Map<String, dynamic>>[]
      : (await client
              .from('video_call_participants')
              .select('user_id,display_name')
              .eq('room_id', roomId)
              .order('joined_at', ascending: true))
          .cast<Map<String, dynamic>>();

  final audioInputs = await Helper.enumerateDevices('audioinput');
  final cameras = await Helper.enumerateDevices('videoinput');

  final firstAudio = audioInputs.isNotEmpty ? audioInputs.first.deviceId : null;
  final firstCam = cameras.isNotEmpty ? cameras.first.deviceId : null;

  String? chosenAudio = firstAudio;
  String? chosenCam = firstCam;
  var permissionsGranted = false;

  // ignore: use_build_context_synchronously
  return showDialog<VideoCallJoinResult>(
    // ignore: use_build_context_synchronously
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final canJoinExisting = roomId != null && participants.isNotEmpty;
          final primaryActionLabel = canJoinExisting ? 'Подключиться' : 'Создать новый';

          return AlertDialog(
            title: const Text('Видеозвонок проекта'),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Участники:',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  participants.isEmpty
                      ? const Text('Пока никто не подключился.')
                      : Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: participants
                              .map((p) => Chip(
                                    label: Text(
                                      (p['display_name'] as String?) ?? 'User',
                                    ),
                                  ))
                              .toList(),
                        ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final stream = await Helper.openCamera({
                          'audio': true,
                          'video': true,
                        });
                        for (final t in stream.getTracks()) {
                          t.stop();
                        }
                        permissionsGranted = true;
                        setState(() {});
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Права на камеру и микрофон выданы')),
                        );
                      } catch (e) {
                        permissionsGranted = false;
                        setState(() {});
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Не удалось выдать права: $e')),
                        );
                      }
                    },
                    icon: Icon(
                      permissionsGranted ? Icons.verified_user : Icons.security_outlined,
                    ),
                    label: Text(
                      permissionsGranted ? 'Права выданы' : 'Выдать права',
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Динамики не требуют отдельного разрешения в браузере.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: chosenAudio,
                    decoration: const InputDecoration(
                      labelText: 'Микрофон',
                      border: OutlineInputBorder(),
                    ),
                    items: audioInputs.isEmpty
                        ? const []
                        : audioInputs
                            .map((d) => DropdownMenuItem<String>(
                                  value: d.deviceId,
                                  child: Text(d.label.isNotEmpty ? d.label : 'Микрофон'),
                                ))
                            .toList(),
                    onChanged: (v) => setState(() => chosenAudio = v),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    value: chosenCam,
                    decoration: const InputDecoration(
                      labelText: 'Веб-камера',
                      border: OutlineInputBorder(),
                    ),
                    items: cameras.isEmpty
                        ? const []
                        : cameras
                            .map((d) => DropdownMenuItem<String>(
                                  value: d.deviceId,
                                  child: Text(d.label.isNotEmpty ? d.label : 'Камера'),
                                ))
                            .toList(),
                    onChanged: (v) => setState(() => chosenCam = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, null),
                child: const Text('Отмена'),
              ),
              ElevatedButton(
                onPressed: () async {
                  try {
                    String actualRoomId = roomId ?? '';
                    if (!canJoinExisting) {
                      Map<String, dynamic> createdRoom;
                      try {
                        createdRoom = await client
                            .from('video_call_rooms')
                            .insert({
                              'project_id': projectId,
                              'created_by': currentUserId,
                            })
                            .select('id')
                            .single();
                      } catch (e) {
                        // Backward compatibility: old schema may still require board_id NOT NULL.
                        final message = e.toString().toLowerCase();
                        if (!message.contains('board_id') ||
                            (!message.contains('not-null') && !message.contains('violates'))) {
                          rethrow;
                        }

                        final board = await client
                            .from('boards')
                            .select('id')
                            .eq('project_id', projectId)
                            .order('created_at', ascending: true)
                            .limit(1)
                            .maybeSingle();
                        String? fallbackBoardId = board?['id']?.toString();
                        if (fallbackBoardId == null) {
                          final createdBoard = await client
                              .from('boards')
                              .insert({
                                'project_id': projectId,
                                'name': 'Общая коммуникация',
                                'created_by': currentUserId,
                              })
                              .select('id')
                              .single();
                          fallbackBoardId = createdBoard['id']?.toString();
                        }
                        if (fallbackBoardId == null) {
                          throw Exception('Не удалось создать служебную доску для звонка');
                        }

                        createdRoom = await client
                            .from('video_call_rooms')
                            .insert({
                              'project_id': projectId,
                              'board_id': fallbackBoardId,
                              'created_by': currentUserId,
                            })
                            .select('id')
                            .single();
                      }

                      actualRoomId = createdRoom['id'] as String;
                    } else {
                      actualRoomId = roomId;
                    }

                    final alreadyInRoom = participants.any(
                      (p) => (p['user_id'] as String?) == currentUserId,
                    );

                    if (!alreadyInRoom) {
                      await client.from('video_call_participants').insert({
                        'room_id': actualRoomId,
                        'user_id': currentUserId,
                        'display_name': displayName,
                      });
                    }

                    if (!context.mounted) return;
                    Navigator.pop(
                      context,
                      VideoCallJoinResult(
                        roomId: actualRoomId,
                        audioDeviceId: chosenAudio,
                        videoDeviceId: chosenCam,
                      ),
                    );
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка звонка: $e')),
                    );
                  }
                },
                child: Text(primaryActionLabel),
              ),
            ],
          );
        },
      );
    },
  );
}

