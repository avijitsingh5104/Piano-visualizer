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
    bars.clear(); // clear bars on mode switch
    notifyListeners();
  }

  Color noteColor = const Color(0xFFD060F0);
  void setColor(Color color) {
    noteColor = color;
    notifyListeners();
  }

  bool isPlaying = false;
  void setPlaying(bool value) {
    isPlaying = value;
    notifyListeners();
  }

  Future<void> initAudio() async {
    await audio.init();
  }

  // ADDED: shared bar list so both PianoRollVisualizer instances (the
  // visible one and the hidden export canvas) draw the exact same bars.
  // Previously each instance had its own private list and competed over
  // the single onSpawnBar callback slot — whichever registered last won.
  final List<NoteBar> bars = [];

  // onSpawnBar kept for any external code that still references it.
  void Function(int midi, int velocity)? onSpawnBar;

  // CHANGED: now adds directly to the shared bars list instead of only
  // calling the callback. Both visualizers pick it up automatically.
  void spawnBar(int midi, int velocity) {
    bars.add(NoteBar.playback(
      midi:      midi,
      height:    40,
      velocity:  velocity,
      spawnedAt: DateTime.now(),
    ));
    onSpawnBar?.call(midi, velocity); // legacy callback, still fires if set
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