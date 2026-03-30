import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import '../services/audio_service.dart';
import 'package:flutter/material.dart';
import '../widgets/piano_roll.dart' show NoteBar;

class PianoState extends ChangeNotifier {
  final Set<int> activeNotes = {};
  List<MidiDevice> devices = [];
  final AudioService audio = AudioService();

  bool fallingMode = true;
  void toggleMode() {
    fallingMode = !fallingMode;
    bars.clear();
    notifyListeners();
  }

  // ── Single color mode ────────────────────────────────────────────────────
  Color noteColor = const Color(0xFFD060F0);
  void setColor(Color color) {
    noteColor = color;
    notifyListeners();
  }

  // ── Dual color mode ──────────────────────────────────────────────────────
  // When enabled, bars are colored based on which side of splitMidi the note
  // falls on. Notes below splitMidi get leftColor, notes above get rightColor,
  // with a smooth gradient interpolation across the full 88-key range.
  bool dualColorMode = false;
  Color leftColor  = const Color(0xFF4060FF); // blue  — left hand
  Color rightColor = const Color(0xFFFF4060); // red   — right hand
  int   splitMidi  = 60;                      // middle C default

  void setDualColorMode(bool value) {
    dualColorMode = value;
    notifyListeners();
  }

  void setLeftColor(Color color) {
    leftColor = color;
    notifyListeners();
  }

  void setRightColor(Color color) {
    rightColor = color;
    notifyListeners();
  }

  void setSplitMidi(int midi) {
    splitMidi = midi;
    notifyListeners();
  }

  /// Returns the correct color for a given MIDI note number, respecting
  /// single vs dual color mode. Used by the painter to color each bar.
  Color colorForNote(int midi) {
    if (!dualColorMode) return noteColor;
    // Smooth gradient: map midi 21–108 to 0.0–1.0, then lerp left→right.
    // This means the transition is gradual across the whole keyboard rather
    // than a hard cut at splitMidi — splitMidi just marks the midpoint.
    const int kMin = 21;
    const int kMax = 108;
    final double t = ((midi - kMin) / (kMax - kMin)).clamp(0.0, 1.0);
    // Remap so splitMidi maps to t=0.5: notes left of split lean toward
    // leftColor, notes right of split lean toward rightColor.
    final double splitT = ((splitMidi - kMin) / (kMax - kMin)).clamp(0.0, 1.0);
    final double normalized = splitT == 0
        ? t
        : splitT == 1
        ? t
        : t < splitT
        ? (t / splitT) * 0.5
        : 0.5 + ((t - splitT) / (1.0 - splitT)) * 0.5;
    return Color.lerp(leftColor, rightColor, normalized)!;
  }

  // ── Playback ─────────────────────────────────────────────────────────────
  bool isPlaying = false;
  void setPlaying(bool value) {
    isPlaying = value;
    notifyListeners();
  }

  Future<void> initAudio() async {
    await audio.init();
  }

  // Shared bar list — both PianoRollVisualizer instances read from this
  final List<NoteBar> bars = [];

  void Function(int midi, int velocity)? onSpawnBar;

  void spawnBar(int midi, int velocity) {
    bars.add(NoteBar.playback(
      midi:      midi,
      height:    40,
      velocity:  velocity,
      spawnedAt: DateTime.now(),
    ));
    onSpawnBar?.call(midi, velocity);
    notifyListeners();
  }

  void pressNote(int midi) {
    activeNotes.add(midi);
    audio.playNote(midi);
    notifyListeners();
  }

  void releaseNote(int midi) {
    activeNotes.remove(midi);
    audio.stopNote(midi);
    notifyListeners();
  }

  void releaseAll() {
    for (final n in activeNotes) {
      audio.stopNote(n);
    }
    activeNotes.clear();
    notifyListeners();
  }

  bool isActive(int midi) => activeNotes.contains(midi);

  void updateDevices(List<MidiDevice> d) {
    devices = d;
    notifyListeners();
  }
}