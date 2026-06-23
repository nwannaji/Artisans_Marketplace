// lib/widgets/audio_player_bubble.dart

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

class AudioPlayerBubble extends StatefulWidget {
  final String audioUrl;
  final double? durationSeconds;
  final bool isSender;

  const AudioPlayerBubble({
    super.key,
    required this.audioUrl,
    this.durationSeconds,
    required this.isSender,
  });

  @override
  State<AudioPlayerBubble> createState() => _AudioPlayerBubbleState();
}

class _AudioPlayerBubbleState extends State<AudioPlayerBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  bool _isLoading = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds.remainder(60);
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
      setState(() => _isPlaying = false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      _player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _duration = d);
      });
      _player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _position = p);
      });
      _player.onPlayerComplete.listen((_) {
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _position = Duration.zero;
          });
        }
      });

      await _player.play(UrlSource(widget.audioUrl));
      setState(() {
        _isPlaying = true;
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isPlaying = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to play audio'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalDuration = widget.durationSeconds != null
        ? Duration(seconds: widget.durationSeconds!.round())
        : _duration;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Play/Pause button
        GestureDetector(
          onTap: _isLoading ? null : _togglePlay,
          child: _isLoading
              ? const SizedBox(
                  width: 32,
                  height: 32,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  _isPlaying ? Icons.pause_circle : Icons.play_circle,
                  size: 32,
                  color: widget.isSender ? Theme.of(context).primaryColor : Colors.grey.shade700,
                ),
        ),
        const SizedBox(width: 8),
        // Progress bar and time
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Simple progress indicator
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: totalDuration.inMilliseconds > 0
                      ? _position.inMilliseconds / totalDuration.inMilliseconds
                      : 0,
                  backgroundColor: Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    widget.isSender ? Theme.of(context).primaryColor : Colors.grey.shade600,
                  ),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _isPlaying
                    ? '${_formatDuration(_position)} / ${_formatDuration(totalDuration)}'
                    : _formatDuration(totalDuration),
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}