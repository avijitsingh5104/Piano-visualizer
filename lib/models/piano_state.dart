import 'package:flutter/foundation.dart';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import '../services/audio_service.dart';
import 'package:flutter/material.dart';

class PianoState extends ChangeNotifier {
  final Set<int> activeNotes = {};
  List<MidiDevice> devices = [];
  final AudioService audio = AudioService();

  bool fallingMode = true;
  void toggleMode() {
    fallingMode = !fallingMode;
    notifyListeners();
  }

  Color noteColor = const Color(0xFFD060F0);
  void setColor(Color color) {
    noteColor = color;
    notifyListeners();
  }

  // ✅ NEW: playback flag
  bool isPlaying = false;
  void setPlaying(bool value) {
    isPlaying = value;
    notifyListeners();
  }

  Future<void> initAudio() async {
    await audio.init();
  }

  // Callback for visual bars
  void Function(int midi, int velocity)? onSpawnBar;

  void spawnBar(int midi, int velocity) {
    onSpawnBar?.call(midi, velocity);
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