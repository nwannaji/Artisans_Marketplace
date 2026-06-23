// lib/services/voice_note_service.dart

import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

class VoiceNoteService {
  final Record _recorder = Record();
  String? _currentRecordingPath;
  bool _isRecording = false;
  DateTime? _recordingStartTime;

  bool get isRecording => _isRecording;

  /// Request microphone permission
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Start recording a voice note
  Future<bool> startRecording() async {
    if (_isRecording) return false;

    final hasPermission = await requestPermission();
    if (!hasPermission) return false;

    try {
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/voice_note_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        path: path,
        encoder: AudioEncoder.aacLc,
        numChannels: 1,
        samplingRate: 44100,
        bitRate: 64000,
      );

      _currentRecordingPath = path;
      _recordingStartTime = DateTime.now();
      _isRecording = true;
      return true;
    } catch (e) {
      debugPrint('Error starting recording: $e');
      return false;
    }
  }

  /// Stop recording and return the file. Returns null if not recording.
  Future<VoiceNoteResult?> stopRecording() async {
    if (!_isRecording) return null;

    try {
      final path = await _recorder.stop();
      _isRecording = false;

      if (path == null || _currentRecordingPath == null) return null;

      final file = File(path);
      if (!await file.exists()) return null;

      final duration = _recordingStartTime != null
          ? DateTime.now().difference(_recordingStartTime!).inMilliseconds / 1000.0
          : null;

      // Discard very short recordings (likely accidental taps)
      if (duration != null && duration < 0.5) {
        await file.delete();
        return null;
      }

      return VoiceNoteResult(
        file: file,
        durationSeconds: duration ?? 0.0,
      );
    } catch (e) {
      debugPrint('Error stopping recording: $e');
      _isRecording = false;
      return null;
    }
  }

  /// Cancel the current recording without saving
  Future<void> cancelRecording() async {
    if (!_isRecording) return;
    try {
      await _recorder.stop();
      _isRecording = false;
      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) await file.delete();
      }
    } catch (_) {
      _isRecording = false;
    }
  }

  /// Get the elapsed duration of the current recording in seconds
  double get recordingDurationSeconds {
    if (_recordingStartTime == null) return 0;
    return DateTime.now().difference(_recordingStartTime!).inMilliseconds / 1000.0;
  }

  /// Dispose the recorder
  Future<void> dispose() async {
    await _recorder.dispose();
  }
}

class VoiceNoteResult {
  final File file;
  final double durationSeconds;

  const VoiceNoteResult({required this.file, required this.durationSeconds});
}