// lib/screens/home_screen.dart
// CHANGED: wrapped the full screen body in a RepaintBoundary so
// video capture picks up the dark background + piano roll + keyboard.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/piano_state.dart';
import '../widgets/keyboard_widget.dart';
import '../widgets/midi_device_panel.dart';
import '../widgets/piano_roll.dart';
import '../services/recording_service.dart';
import '../services/video_export_service.dart'; // NEW
import '../widgets/recordings_panel.dart';

class HomeScreen extends StatefulWidget {          // changed to StatefulWidget
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // This key is registered with VideoExportService so captureFrame() works.
  final _captureBoundaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    VideoExportService.instance.boundaryKey = _captureBoundaryKey;
  }

  @override
  void dispose() {
    if (VideoExportService.instance.boundaryKey == _captureBoundaryKey) {
      VideoExportService.instance.boundaryKey = null;
    }
    super.dispose();
  }

  static const _names = [
    'C','C#','D','D#','E','F','F#','G','G#','A','A#','B'
  ];

  static String _noteName(int midi) {
    final name = _names[midi % 12];
    final octave = (midi ~/ 12) - 1;
    return '$name$octave';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: RepaintBoundary(
        key: _captureBoundaryKey,
        child: Container(
          // Explicit background so captured frames aren't transparent/black
          color: const Color(0xFF0A0A0F),
          child: Stack(
            children: [
              // Main layout
              Column(
                children: [
                  Expanded(
                    child: const PianoRollVisualizer(),
                  ),
                  Container(
                    height: 150,
                    decoration: const BoxDecoration(
                      color: Color(0xFF111118),
                      border: Border(
                        top: BorderSide(color: Color(0x33FFFFFF), width: 1),
                      ),
                    ),
                    child: const PianoKeyboard(),
                  ),
                ],
              ),

              // MIDI device panel floating top-right
              const MidiDeviceButton(),
              Positioned(
                top: 16,
                left: 16,
                child: Consumer<PianoState>(
                  builder: (context, state, _) {
                    return GestureDetector(
                      onTap: () => state.toggleMode(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A28),
                          borderRadius: BorderRadius.circular(12),
                          border:
                          Border.all(color: const Color(0xFF44446A)),
                        ),
                        child: Text(
                          state.fallingMode ? "Falling ↓" : "Rising ↑",
                          style: const TextStyle(
                            color: Color(0xFFD060F0),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                bottom: 180,
                right: 16,
                child: Consumer<PianoState>(
                  builder: (context, state, _) {
                    return GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => const _ColorPickerDialog(),
                        );
                      },
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1A1A28),
                          borderRadius: BorderRadius.circular(12),
                          border:
                          Border.all(color: const Color(0xFF44446A)),
                        ),
                        child: Icon(
                          Icons.palette,
                          color: state.noteColor,
                        ),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                top: 16,
                right: 16,
                child: Consumer<RecordingService>(
                  builder: (context, recorder, _) {
                    return ElevatedButton(
                      onPressed: () {
                        if (recorder.isRecording) {
                          recorder.stop();
                        } else {
                          recorder.start();
                        }
                      },
                      child: Text(
                        recorder.isRecording ? "Stop" : "Record",
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                top: 60,
                right: 16,
                child: RecordingsPanel(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorPickerDialog extends StatelessWidget {
  const _ColorPickerDialog();

  static const colors = [
    Colors.purple,
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.cyan,
    Colors.pink,
    Colors.yellow,
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF16161F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: colors.map((c) {
            return GestureDetector(
              onTap: () {
                context.read<PianoState>().setColor(c);
                Navigator.pop(context);
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}