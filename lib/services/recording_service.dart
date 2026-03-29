// lib/services/recording_service.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/piano_state.dart';
import '../utils/constants.dart';
import 'video_export_service.dart';

class MidiEvent {
  final int note;
  final int velocity;
  final int time;
  final bool isOn;

  MidiEvent({
    required this.note,
    required this.velocity,
    required this.time,
    required this.isOn,
  });

  Map<String, dynamic> toJson() => {
    'note':     note,
    'velocity': velocity,
    'time':     time,
    'isOn':     isOn,
  };

  factory MidiEvent.fromJson(Map<String, dynamic> j) => MidiEvent(
    note:     j['note'],
    velocity: j['velocity'],
    time:     j['time'],
    isOn:     j['isOn'],
  );
}

class SavedRecording {
  final String name;
  final String filePath;
  final DateTime savedAt;
  final int durationMs;

  SavedRecording({
    required this.name,
    required this.filePath,
    required this.savedAt,
    required this.durationMs,
  });
}

// Stores raw RGBA pixel data + the canvas dimensions + wall-clock timestamp.
// Using raw RGBA (ImageByteFormat.rawRgba) instead of PNG means captureFrame()
// does zero compression work — it just copies GPU pixels to RAM, which is
// ~10x faster. The JPEG encoding happens later in a background isolate during
// export, not on the UI thread during playback.
class CapturedFrame {
  final Uint8List rgbaBytes; // raw RGBA, width * height * 4 bytes
  final int width;
  final int height;
  final DateTime capturedAt;

  CapturedFrame({
    required this.rgbaBytes,
    required this.width,
    required this.height,
    required this.capturedAt,
  });
}

class RecordingService extends ChangeNotifier {
  final List<MidiEvent> events = [];
  DateTime? _startTime;
  bool isRecording = false;
  bool isPlaying   = false;
  int _playbackId  = 0;

  List<SavedRecording> savedRecordings = [];

  final List<CapturedFrame> capturedFrames = [];
  bool isCapturing = false;

  void start() {
    events.clear();
    _startTime  = DateTime.now();
    isRecording = true;
    notifyListeners();
  }

  void stop() {
    isRecording = false;
    notifyListeners();
  }

  void recordNoteOn(int note, int velocity) {
    if (!isRecording || _startTime == null) return;
    events.add(MidiEvent(
      note:     note,
      velocity: velocity,
      time:     DateTime.now().difference(_startTime!).inMilliseconds,
      isOn:     true,
    ));
  }

  void recordNoteOff(int note) {
    if (!isRecording || _startTime == null) return;
    events.add(MidiEvent(
      note:     note,
      velocity: 0,
      time:     DateTime.now().difference(_startTime!).inMilliseconds,
      isOn:     false,
    ));
  }

  // ── Save / Load / Delete ─────────────────────────────────────────────────

  Future<bool> saveRecording(String name) async {
    if (events.isEmpty) return false;
    try {
      final dir      = await _recordingsDir();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.json';
      final file     = File('${dir.path}/$fileName');
      final durationMs = events.last.time;
      final json = jsonEncode({
        'name':       name,
        'savedAt':    DateTime.now().toIso8601String(),
        'durationMs': durationMs,
        'events':     events.map((e) => e.toJson()).toList(),
      });
      await file.writeAsString(json);
      await loadSavedRecordings();
      return true;
    } catch (e) {
      debugPrint('Save error: $e');
      return false;
    }
  }

  Future<void> loadSavedRecordings() async {
    try {
      final dir   = await _recordingsDir();
      final files = dir.listSync().whereType<File>().toList();
      final loaded = <SavedRecording>[];
      for (final file in files) {
        try {
          final content = await file.readAsString();
          final json    = jsonDecode(content);
          loaded.add(SavedRecording(
            name:       json['name'],
            filePath:   file.path,
            savedAt:    DateTime.parse(json['savedAt']),
            durationMs: json['durationMs'],
          ));
        } catch (_) {}
      }
      loaded.sort((a, b) => b.savedAt.compareTo(a.savedAt));
      savedRecordings = loaded;
      notifyListeners();
    } catch (e) {
      debugPrint('Load list error: $e');
    }
  }

  Future<bool> loadRecording(SavedRecording recording) async {
    try {
      final file    = File(recording.filePath);
      final content = await file.readAsString();
      final json    = jsonDecode(content);
      events.clear();
      for (final e in (json['events'] as List)) {
        events.add(MidiEvent.fromJson(e));
      }
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Load error: $e');
      return false;
    }
  }

  Future<void> deleteRecording(SavedRecording recording) async {
    try {
      final file = File(recording.filePath);
      if (await file.exists()) await file.delete();
      await loadSavedRecordings();
    } catch (e) {
      debugPrint('Delete error: $e');
    }
  }

  Future<Directory> _recordingsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir  = Directory('${base.path}/piano_viz_recordings');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // ── Playback ─────────────────────────────────────────────────────────────

  String? currentlyPlayingPath;

  Future<void> play(
      PianoState pianoState,
      String filePath, {
        bool captureVideo = false,
      }) async {
    if (events.isEmpty || isPlaying) return;
    currentlyPlayingPath = filePath;
    _playbackId++;
    final myId = _playbackId;

    isPlaying = true;
    pianoState.setPlaying(true);
    notifyListeners();

    // ── task scheduler ────────────────────────────────────────────────────
    final tasks = <_Task>[];
    for (final event in events) {
      if (event.isOn) {
        tasks.add(_Task(ms: event.time,
            action: () => pianoState.spawnBar(event.note, event.velocity)));
        tasks.add(_Task(ms: event.time + kFallDurationMs - 400,
            action: () => pianoState.pressNote(event.note)));
      } else {
        tasks.add(_Task(ms: event.time + kFallDurationMs - 400,
            action: () => pianoState.releaseNote(event.note)));
      }
    }
    tasks.sort((a, b) => a.ms.compareTo(b.ms));

    // ── frame capture ─────────────────────────────────────────────────────
    if (captureVideo) {
      capturedFrames.clear();
      isCapturing = true;

      // captureFrame() now returns raw RGBA (no PNG compression) so it runs
      // fast enough to get 20-30 real fps during playback. Timestamps are
      // stored so the concat demuxer can assign the exact per-frame duration.
      Future(() async {
        while (isCapturing) {
          final capturedAt = DateTime.now();
          final frame = await VideoExportService.instance.captureFrame();
          if (frame != null && isCapturing) {
            capturedFrames.add(CapturedFrame(
              rgbaBytes:  frame.bytes,
              width:      frame.width,
              height:     frame.height,
              capturedAt: capturedAt,
            ));
          }
          await Future.delayed(Duration.zero);
        }
      });
    }

    final playbackStart = DateTime.now();
    for (final task in tasks) {
      if (_playbackId != myId || !isPlaying) break;
      final elapsed = DateTime.now().difference(playbackStart).inMilliseconds;
      final wait    = task.ms - elapsed;
      if (wait > 0) await Future.delayed(Duration(milliseconds: wait));
      if (_playbackId != myId || !isPlaying) break;
      task.action();
    }

    if (_playbackId == myId && isPlaying) {
      await Future.delayed(const Duration(milliseconds: 500));
    }

    isCapturing = false;

    if (_playbackId == myId && isPlaying) {
      pianoState.releaseAll();
      isPlaying = false;
      pianoState.setPlaying(false);
      currentlyPlayingPath = null;
      notifyListeners();
    }
  }

  void stopPlayback(PianoState pianoState) {
    _playbackId++;
    isPlaying = false;
    isCapturing = false;
    pianoState.setPlaying(false);
    pianoState.releaseAll();
    currentlyPlayingPath = null;
    notifyListeners();
  }
}

class _Task {
  final int ms;
  final VoidCallback action;
  _Task({required this.ms, required this.action});
}