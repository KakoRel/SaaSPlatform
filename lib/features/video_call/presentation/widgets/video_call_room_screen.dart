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

  MediaStream? _localStream;

  RealtimeChannel? _signalsChannel;
  RealtimeChannel? _participantsChannel;

  bool _isConnecting = true;

  String? get _currentUserId => SupabaseClientService.instance.currentUserId;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _localRenderer.initialize();

    try {
      await _startLocalStream();
      await _setupRealtime();

      final participants = await _fetchParticipants();
      final others = participants
          .map((p) => p['user_id'] as String?)
          .where((id) => id != null && id != _currentUserId)
          .cast<String>()
          .toList();

      for (final peerId in others) {
        await _connectToPeerAndOffer(peerId);
      }
    } finally {
      if (mounted) setState(() => _isConnecting = false);
    }
  }

  Future<void> _startLocalStream() async {
    final audioConstraints = widget.audioDeviceId == null
        ? true
        : <String, dynamic>{
            'deviceId': widget.audioDeviceId,
          };

    final videoConstraints = widget.videoDeviceId == null
        ? true
        : <String, dynamic>{
            'deviceId': widget.videoDeviceId,
          };

    final constraints = <String, dynamic>{
      'audio': audioConstraints,
      'video': videoConstraints,
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

  Future<void> _setupRealtime() async {
    _signalsChannel?.unsubscribe();
    _participantsChannel?.unsubscribe();

    _signalsChannel = SupabaseClientService.instance.subscribeToTable(
      tableName: 'video_call_signals',
      channelId: 'video_call_signals_${widget.roomId}',
      callback: (payload) async {
        final newRecord = payload.newRecord as Map<String, dynamic>?;
        if (newRecord == null) return;

        final roomId = newRecord['room_id'] as String?;
        if (roomId != widget.roomId) return;

        final targetId = newRecord['target_id'] as String?;
        if (targetId != _currentUserId) return;

        final senderId = newRecord['sender_id'] as String?;
        if (senderId == null || senderId.isEmpty) return;

        final signalType = newRecord['signal_type'] as String?;
        final payloadData = newRecord['payload'] as Map<String, dynamic>?;
        if (signalType == null || payloadData == null) return;

        try {
          if (signalType == 'offer') {
            await _handleOffer(senderId, payloadData);
          } else if (signalType == 'answer') {
            await _handleAnswer(senderId, payloadData);
          } else if (signalType == 'ice') {
            await _handleIce(senderId, payloadData);
          }
        } catch (_) {
          // Avoid crashing on bad signals.
        }
      },
    );
    _signalsChannel?.subscribe();

    _participantsChannel = SupabaseClientService.instance.subscribeToTable(
      tableName: 'video_call_participants',
      channelId: 'video_call_participants_${widget.roomId}',
      callback: (payload) async {
        final newRecord = payload.newRecord as Map<String, dynamic>?;
        if (newRecord == null) return;

        final roomId = newRecord['room_id'] as String?;
        if (roomId != widget.roomId) return;

        final joinedUserId = newRecord['user_id'] as String?;
        if (joinedUserId == null || joinedUserId == _currentUserId) return;

        if (!_peerConnections.containsKey(joinedUserId)) {
          await _connectToPeerAndOffer(joinedUserId);
        }
      },
    );

    _participantsChannel?.subscribe();
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
      final stream = event.streams.isNotEmpty ? event.streams[0] : null;
      if (stream == null) return;
      final renderer = _remoteRenderers[peerId];
      renderer?.srcObject = stream;
    };

    pc.onIceCandidate = (candidate) async {
      await _sendIce(peerId, candidate);
    };

    // Add local tracks
    final localStream = _localStream;
    if (localStream != null) {
      for (final track in localStream.getTracks()) {
        pc.addTrack(track, localStream);
      }
    }

    _peerConnections[peerId] = pc;
    return pc;
  }

  Future<void> _connectToPeerAndOffer(String peerId) async {
    final pc = await _ensurePeerConnection(peerId);

    final offer = await pc.createOffer({
      'offerToReceiveVideo': 1,
      'offerToReceiveAudio': 1,
    });
    await pc.setLocalDescription(offer);

    await _sendOffer(peerId, offer);
  }

  Future<void> _handleOffer(
    String senderId,
    Map<String, dynamic> payloadData,
  ) async {
    final pc = await _ensurePeerConnection(senderId);

    final sdp = payloadData['sdp'] as String?;
    final type = payloadData['type'] as String?;
    if (sdp == null || type == null) return;

    await pc.setRemoteDescription(RTCSessionDescription(sdp, type));

    final answer = await pc.createAnswer({
      'offerToReceiveVideo': 1,
      'offerToReceiveAudio': 1,
    });
    await pc.setLocalDescription(answer);

    await _sendAnswer(senderId, answer);
  }

  Future<void> _handleAnswer(
    String senderId,
    Map<String, dynamic> payloadData,
  ) async {
    final pc = _peerConnections[senderId];
    if (pc == null) return;

    final sdp = payloadData['sdp'] as String?;
    final type = payloadData['type'] as String?;
    if (sdp == null || type == null) return;

    await pc.setRemoteDescription(RTCSessionDescription(sdp, type));
  }

  Future<void> _handleIce(
    String senderId,
    Map<String, dynamic> payloadData,
  ) async {
    final pc = _peerConnections[senderId];
    if (pc == null) return;

    final candidate = payloadData['candidate'] as String?;
    final sdpMid = payloadData['sdpMid'] as String?;
    final sdpMLineIndex = payloadData['sdpMLineIndex'] as int?;
    if (candidate == null || sdpMid == null || sdpMLineIndex == null) return;

    await pc.addCandidate(
      RTCIceCandidate(candidate, sdpMid, sdpMLineIndex),
    );
  }

  Future<void> _sendOffer(
    String targetId,
    RTCSessionDescription offer,
  ) async {
    final fromId = _currentUserId;
    if (fromId == null) return;

    final client = SupabaseClientService.instance.client;
    await client.from('video_call_signals').insert({
      'room_id': widget.roomId,
      'sender_id': fromId,
      'target_id': targetId,
      'signal_type': 'offer',
      'payload': {
        'sdp': offer.sdp,
        'type': offer.type,
      },
    });
  }

  Future<void> _sendAnswer(
    String targetId,
    RTCSessionDescription answer,
  ) async {
    final fromId = _currentUserId;
    if (fromId == null) return;

    final client = SupabaseClientService.instance.client;
    await client.from('video_call_signals').insert({
      'room_id': widget.roomId,
      'sender_id': fromId,
      'target_id': targetId,
      'signal_type': 'answer',
      'payload': {
        'sdp': answer.sdp,
        'type': answer.type,
      },
    });
  }

  Future<void> _sendIce(
    String targetId,
    RTCIceCandidate candidate,
  ) async {
    final fromId = _currentUserId;
    if (fromId == null) return;

    final client = SupabaseClientService.instance.client;
    await client.from('video_call_signals').insert({
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

  @override
  void dispose() {
    _signalsChannel?.unsubscribe();
    _participantsChannel?.unsubscribe();

    try {
      _localStream?.getTracks().forEach((t) => t.stop());
    } catch (_) {}

    for (final r in _remoteRenderers.values) {
      try {
        r.dispose();
      } catch (_) {}
    }
    try {
      _localRenderer.dispose();
    } catch (_) {}

    for (final pc in _peerConnections.values) {
      try {
        pc.close();
      } catch (_) {}
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localWidget = Positioned(
      top: 12,
      left: 12,
      width: 160,
      height: 120,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
        ),
        clipBehavior: Clip.antiAlias,
        child: RTCVideoView(
          _localRenderer,
          mirror: true,
          objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
        ),
      ),
    );

    final remoteWidgets = _remoteRenderers.entries.map((entry) {
      return RTCVideoView(
        entry.value,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Видеозвонок'),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: remoteWidgets.isEmpty
                ? const Center(child: Text('Ждём подключения...'))
                : GridView.count(
                    crossAxisCount: 2,
                    children: remoteWidgets,
                  ),
          ),
          if (_localStream != null) localWidget,
          if (_isConnecting)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.08),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

