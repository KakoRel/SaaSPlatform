import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/supabase_client.dart';

class VideoCallRoomScreen extends StatefulWidget {
  const VideoCallRoomScreen({
    super.key,
    required this.boardId,
    required this.roomId,
    required this.audioDeviceId,
    required this.videoDeviceId,
  });

  final String boardId;
  final String roomId;
  final String? audioDeviceId;
  final String? videoDeviceId;

  @override
  State<VideoCallRoomScreen> createState() => _VideoCallRoomScreenState();
}

class _VideoCallRoomScreenState extends State<VideoCallRoomScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final Map<String, RTCVideoRenderer> _remoteRenderers = {};
  final Map<String, RTCPeerConnection> _peerConnections = {};
  final Map<String, String> _participantNames = {};
  final Map<String, String?> _avatarUrls = {};
  final Map<String, List<RTCIceCandidate>> _pendingIceByPeer = {};

  MediaStream? _localStream;

  RealtimeChannel? _signalsChannel;
  RealtimeChannel? _participantsChannel;

  bool _isConnecting = true;
  bool _isMicEnabled = true;
  bool _isCamEnabled = true;
  bool _hadRemoteParticipant = false;

  String? get _currentUserId => SupabaseClientService.instance.currentUserId;

  String? _activeSpeakerId;
  Timer? _activeSpeakerTimer;
  Timer? _participantsSyncTimer;
  bool _isPollingActiveSpeaker = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _localRenderer.initialize();
    try {
      await _startLocalStream();
      await _syncParticipants();
      await _setupRealtime();

      final currentParticipants = await _fetchParticipants();
      final others = currentParticipants
          .map((p) => p['user_id'] as String?)
          .where((id) => id != null && id != _currentUserId)
          .cast<String>()
          .toList();

      for (final peerId in others) {
        if (_shouldInitiateOffer(peerId)) {
          await _connectToPeerAndOffer(peerId);
        }
      }

      _activeSpeakerTimer ??= Timer.periodic(
        const Duration(milliseconds: 500),
        (_) => _pollActiveSpeaker(),
      );
      _participantsSyncTimer ??= Timer.periodic(
        const Duration(seconds: 3),
        (_) => _syncParticipants(),
      );
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  bool _shouldInitiateOffer(String peerId) {
    final me = _currentUserId;
    if (me == null) return false;
    return me.compareTo(peerId) < 0;
  }

  Future<void> _pollActiveSpeaker() async {
    if (_isPollingActiveSpeaker) return;
    if (_peerConnections.isEmpty) return;
    _isPollingActiveSpeaker = true;

    try {
      double bestLevel = 0;
      String? bestPeerId;

      for (final entry in _peerConnections.entries) {
        final peerId = entry.key;
        final pc = entry.value;
        try {
          final stats = await pc.getStats();
          double level = 0;
          for (final report in stats) {
            final raw = report.values['audioLevel'];
            if (raw is num) {
              level = raw.toDouble();
              break;
            }
            if (raw is String) {
              final parsed = double.tryParse(raw);
              if (parsed != null) {
                level = parsed;
                break;
              }
            }
          }

          if (level > bestLevel) {
            bestLevel = level;
            bestPeerId = peerId;
          }
        } catch (_) {
          // ignore peer stats errors
        }
      }

      const threshold = 0.05;
      if (!mounted) return;
      setState(() {
        _activeSpeakerId = bestLevel >= threshold ? bestPeerId : null;
      });
    } finally {
      _isPollingActiveSpeaker = false;
    }
  }

  Future<void> _startLocalStream() async {
    final constraints = <String, dynamic>{
      'audio': widget.audioDeviceId == null ? true : {'deviceId': widget.audioDeviceId},
      'video': widget.videoDeviceId == null ? true : {'deviceId': widget.videoDeviceId},
    };
    _localStream = await Helper.openCamera(constraints);
    _localRenderer.srcObject = _localStream;
  }

  Future<List<Map<String, dynamic>>> _fetchParticipants() async {
    final client = SupabaseClientService.instance.client;
    final data = await client
        .from('video_call_participants')
        .select('user_id,display_name')
        .eq('room_id', widget.roomId);
    return (data as List).cast<Map<String, dynamic>>();
  }

  Future<void> _ensureAvatarsForParticipants(Set<String> userIds) async {
    final missing = userIds.where((id) => !_avatarUrls.containsKey(id)).toList();
    if (missing.isEmpty) return;

    final futures = missing.map((id) async {
      final user = await SupabaseClientService.instance.fetchSingle<Map<String, dynamic>>(
        tableName: 'users',
        select: 'id,avatar_url',
        fromJson: (json) => json,
        filters: [QueryFilter('id', 'eq', id)],
      );
      return MapEntry(id, user?['avatar_url'] as String?);
    }).toList();

    final results = await Future.wait(futures);
    for (final entry in results) {
      _avatarUrls[entry.key] = entry.value;
    }

    if (mounted) setState(() {});
  }

  Future<void> _syncParticipants() async {
    final participants = await _fetchParticipants();
    final participantIds = participants
        .map((p) => p['user_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    _participantNames
      ..clear()
      ..addEntries(
        participants.map(
          (p) => MapEntry(
            p['user_id']?.toString() ?? '',
            p['display_name']?.toString() ?? 'Пользователь',
          ),
        ),
      );

    await _ensureAvatarsForParticipants(participantIds);

    // Fallback for setups where realtime events for participants are not delivered.
    // If someone joined and this client should be offerer, initiate from polling.
    for (final peerId in participantIds) {
      if (peerId == _currentUserId) continue;
      if (_peerConnections.containsKey(peerId)) continue;
      if (_shouldInitiateOffer(peerId)) {
        await _connectToPeerAndOffer(peerId);
      }
    }

    if (participants.length > 1) {
      _hadRemoteParticipant = true;
    } else if (_hadRemoteParticipant && participants.length <= 1) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('В конференции никого не осталось, выходим...')),
        );
      }
      await _leaveAndPop();
      return;
    }

    if (mounted) setState(() {});
  }

  Future<void> _setupRealtime() async {
    _signalsChannel?.unsubscribe();
    _participantsChannel?.unsubscribe();

    _signalsChannel = SupabaseClientService.instance.subscribeToTable(
      tableName: 'video_call_signals',
      channelId: 'video_call_signals_${widget.roomId}',
      callback: (payload) async {
        final record = payload.newRecord as Map<String, dynamic>?;
        if (record == null) return;

        final roomId = record['room_id'] as String?;
        if (roomId != widget.roomId) return;

        final targetId = record['target_id'] as String?;
        if (targetId != _currentUserId) return;

        final senderId = record['sender_id'] as String?;
        final type = record['signal_type'] as String?;
        final signal = record['payload'] as Map<String, dynamic>?;
        if (senderId == null || type == null || signal == null) return;

        if (type == 'offer') {
          await _handleOffer(senderId, signal);
        } else if (type == 'answer') {
          await _handleAnswer(senderId, signal);
        } else if (type == 'ice') {
          await _handleIce(senderId, signal);
        }
      },
    )..subscribe();

    _participantsChannel = SupabaseClientService.instance.subscribeToTable(
      tableName: 'video_call_participants',
      channelId: 'video_call_participants_${widget.roomId}',
      callback: (payload) async {
        final record = (payload.newRecord.isNotEmpty ? payload.newRecord : payload.oldRecord)
            as Map<String, dynamic>?;
        if (record == null) return;
        if (record['room_id']?.toString() != widget.roomId) return;

        final joinedUserId = record['user_id']?.toString();
        if (joinedUserId != null &&
            joinedUserId != _currentUserId &&
            !_peerConnections.containsKey(joinedUserId) &&
            _shouldInitiateOffer(joinedUserId)) {
          await _connectToPeerAndOffer(joinedUserId);
        }
        await _syncParticipants();
      },
    )..subscribe();
  }

  Future<RTCPeerConnection> _ensurePeerConnection(String peerId) async {
    final existing = _peerConnections[peerId];
    if (existing != null) return existing;

    final pc = await createPeerConnection({
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
      ],
    });

    final remoteRenderer = RTCVideoRenderer();
    await remoteRenderer.initialize();
    _remoteRenderers[peerId] = remoteRenderer;

    pc.onTrack = (event) {
      if (event.streams.isEmpty) return;
      _remoteRenderers[peerId]?.srcObject = event.streams[0];
      if (mounted) setState(() {});
    };

    pc.onIceCandidate = (candidate) async {
      await _sendIce(peerId, candidate);
    };

    final stream = _localStream;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        pc.addTrack(track, stream);
      }
    }

    _peerConnections[peerId] = pc;
    return pc;
  }

  Future<void> _connectToPeerAndOffer(String peerId) async {
    final pc = await _ensurePeerConnection(peerId);
    final offer = await pc.createOffer({'offerToReceiveVideo': 1, 'offerToReceiveAudio': 1});
    await pc.setLocalDescription(offer);
    await _sendOffer(peerId, offer);
  }

  Future<void> _handleOffer(String senderId, Map<String, dynamic> payload) async {
    final pc = await _ensurePeerConnection(senderId);
    final sdp = payload['sdp'] as String?;
    final type = payload['type'] as String?;
    if (sdp == null || type == null) return;

    await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
    await _flushPendingIce(senderId);
    final answer = await pc.createAnswer({'offerToReceiveVideo': 1, 'offerToReceiveAudio': 1});
    await pc.setLocalDescription(answer);
    await _sendAnswer(senderId, answer);
  }

  Future<void> _handleAnswer(String senderId, Map<String, dynamic> payload) async {
    final pc = _peerConnections[senderId];
    if (pc == null) return;
    final sdp = payload['sdp'] as String?;
    final type = payload['type'] as String?;
    if (sdp == null || type == null) return;
    await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
    await _flushPendingIce(senderId);
  }

  Future<void> _handleIce(String senderId, Map<String, dynamic> payload) async {
    final candidate = payload['candidate'] as String?;
    final sdpMid = payload['sdpMid']?.toString();
    final rawIndex = payload['sdpMLineIndex'];
    final sdpMLineIndex = rawIndex is int
        ? rawIndex
        : (rawIndex is num ? rawIndex.toInt() : int.tryParse(rawIndex?.toString() ?? ''));
    if (candidate == null || sdpMLineIndex == null) return;

    final ice = RTCIceCandidate(candidate, sdpMid, sdpMLineIndex);
    final pc = _peerConnections[senderId];
    if (pc == null) {
      _pendingIceByPeer.putIfAbsent(senderId, () => []).add(ice);
      return;
    }
    try {
      await pc.addCandidate(ice);
    } catch (_) {
      _pendingIceByPeer.putIfAbsent(senderId, () => []).add(ice);
    }
  }

  Future<void> _flushPendingIce(String peerId) async {
    final pc = _peerConnections[peerId];
    if (pc == null) return;
    final pending = _pendingIceByPeer.remove(peerId);
    if (pending == null || pending.isEmpty) return;
    for (final candidate in pending) {
      try {
        await pc.addCandidate(candidate);
      } catch (_) {}
    }
  }

  Future<void> _sendOffer(String targetId, RTCSessionDescription offer) async {
    final fromId = _currentUserId;
    if (fromId == null) return;
    await SupabaseClientService.instance.client.from('video_call_signals').insert({
      'room_id': widget.roomId,
      'sender_id': fromId,
      'target_id': targetId,
      'signal_type': 'offer',
      'payload': {'sdp': offer.sdp, 'type': offer.type},
    });
  }

  Future<void> _sendAnswer(String targetId, RTCSessionDescription answer) async {
    final fromId = _currentUserId;
    if (fromId == null) return;
    await SupabaseClientService.instance.client.from('video_call_signals').insert({
      'room_id': widget.roomId,
      'sender_id': fromId,
      'target_id': targetId,
      'signal_type': 'answer',
      'payload': {'sdp': answer.sdp, 'type': answer.type},
    });
  }

  Future<void> _sendIce(String targetId, RTCIceCandidate candidate) async {
    final fromId = _currentUserId;
    if (fromId == null) return;
    await SupabaseClientService.instance.client.from('video_call_signals').insert({
      'room_id': widget.roomId,
      'sender_id': fromId,
      'target_id': targetId,
      'signal_type': 'ice',
      'payload': {
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      },
    });
  }

  Future<void> _toggleMic() async {
    final stream = _localStream;
    if (stream == null) return;
    final next = !_isMicEnabled;
    for (final track in stream.getAudioTracks()) {
      track.enabled = next;
    }
    setState(() => _isMicEnabled = next);
  }

  Future<void> _toggleCam() async {
    final stream = _localStream;
    if (stream == null) return;
    final next = !_isCamEnabled;
    for (final track in stream.getVideoTracks()) {
      track.enabled = next;
    }
    setState(() => _isCamEnabled = next);
  }

  Future<void> _leaveAndPop() async {
    final userId = _currentUserId;
    if (userId != null) {
      await SupabaseClientService.instance.client
          .from('video_call_participants')
          .delete()
          .eq('room_id', widget.roomId)
          .eq('user_id', userId);
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  void dispose() {
    _signalsChannel?.unsubscribe();
    _participantsChannel?.unsubscribe();

    final userId = _currentUserId;
    if (userId != null) {
      SupabaseClientService.instance.client
          .from('video_call_participants')
          .delete()
          .eq('room_id', widget.roomId)
          .eq('user_id', userId);
    }

    try {
      _localStream?.getTracks().forEach((t) => t.stop());
    } catch (_) {}
    for (final r in _remoteRenderers.values) {
      try {
        r.dispose();
      } catch (_) {}
    }
    for (final pc in _peerConnections.values) {
      try {
        pc.close();
      } catch (_) {}
    }
    _localRenderer.dispose();
    _activeSpeakerTimer?.cancel();
    _participantsSyncTimer?.cancel();
    super.dispose();
  }

  Widget _buildVideoTile({
    required Widget child,
    required String title,
    String? avatarUrl,
    bool isActive = false,
  }) {
    final borderColor = isActive
        ? Colors.greenAccent.withValues(alpha: 0.95)
        : Colors.white.withValues(alpha: 0.14);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: borderColor,
            width: isActive ? 2 : 1,
          ),
          color: Colors.black,
        ),
        child: Stack(
          children: [
            Positioned.fill(child: child),
            if (avatarUrl != null && avatarUrl.isNotEmpty)
              Positioned(
                top: 10,
                left: 10,
                child: CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.white.withValues(alpha: 0.15),
                  backgroundImage: NetworkImage(avatarUrl),
                  onBackgroundImageError: (error, stackTrace) {},
                ),
              ),
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            if (isActive)
              const Positioned(
                right: 10,
                top: 10,
                child: Icon(Icons.mic, color: Colors.greenAccent, size: 18),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localName = _participantNames[_currentUserId] ?? 'Вы';
    final remoteEntries = _remoteRenderers.entries.toList();
    final totalTiles = 1 + remoteEntries.length;
    final crossAxisCount = totalTiles <= 1
        ? 1
        : (totalTiles <= 4 ? 2 : 3);

    return Scaffold(
      backgroundColor: const Color(0xFF0E1014),
      appBar: AppBar(
        title: const Text('Видеоконференция'),
        backgroundColor: const Color(0xFF0E1014),
      ),
      body: Column(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: GridView.count(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                children: [
                  _buildVideoTile(
                    title: '$localName (вы)',
                    child: RTCVideoView(
                      _localRenderer,
                      mirror: true,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                    avatarUrl: _avatarUrls[_currentUserId ?? ''],
                    isActive: _activeSpeakerId == _currentUserId,
                  ),
                  ...remoteEntries.map((entry) {
                    final peerId = entry.key;
                    final name = _participantNames[peerId] ?? 'Участник';
                    return _buildVideoTile(
                      title: name,
                      child: RTCVideoView(
                        entry.value,
                        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                      ),
                      avatarUrl: _avatarUrls[peerId],
                      isActive: _activeSpeakerId == peerId,
                    );
                  }),
                ],
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF141821),
              border: Border(top: BorderSide(color: Color(0x22FFFFFF))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filled(
                  onPressed: _toggleMic,
                  icon: Icon(_isMicEnabled ? Icons.mic : Icons.mic_off),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  onPressed: _toggleCam,
                  icon: Icon(_isCamEnabled ? Icons.videocam : Icons.videocam_off),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.red.withValues(alpha: 0.2),
                    foregroundColor: Colors.red.shade200,
                  ),
                  onPressed: _leaveAndPop,
                  icon: const Icon(Icons.call_end),
                  label: const Text('Покинуть'),
                ),
              ],
            ),
          ),
          if (_isConnecting)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }
}

