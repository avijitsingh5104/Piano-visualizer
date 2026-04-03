// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/piano_state.dart';
import '../widgets/keyboard_widget.dart';
import '../widgets/midi_device_panel.dart';
import '../widgets/piano_roll.dart';
import '../services/recording_service.dart';
import '../services/video_export_service.dart';
import '../widgets/recordings_panel.dart';
import '../widgets/color_picker_dialog.dart';
import 'dart:io';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _exportBoundaryKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    VideoExportService.instance.boundaryKey = _exportBoundaryKey;
  }

  @override
  void dispose() {
    if (VideoExportService.instance.boundaryKey == _exportBoundaryKey) {
      VideoExportService.instance.boundaryKey = null;
    }
    super.dispose();
  }

  // ── Save dialog ────────────────────────────────────────────────────────────

  Future<void> _showSaveDialog(
      BuildContext context, RecordingService recorder) async {
    if (recorder.events.isEmpty) return;
    final ctrl = TextEditingController(text: 'Recording');
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        bool saving = false;
        return StatefulBuilder(builder: (ctx, setState) {
          return Dialog(
            backgroundColor: const Color(0xFF16161F),
            shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Save recording',
                    style: TextStyle(
                        color: Color(0xFFDDDDFF),
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: ctrl,
                    autofocus: true,
                    style: const TextStyle(
                        fontSize: 13, color: Color(0xFFDDDDFF)),
                    decoration: InputDecoration(
                      hintText: 'Recording name…',
                      hintStyle: const TextStyle(
                          color: Color(0xFF555577), fontSize: 13),
                      filled: true,
                      fillColor: const Color(0xFF0A0A0F),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: Color(0xFF33334A), width: 1),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: Color(0xFF33334A), width: 1),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: Color(0xFFD060F0), width: 1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: saving ? null : () => Navigator.pop(ctx),
                        style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF555577)),
                        child: const Text('Discard'),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: saving
                            ? null
                            : () async {
                          final name = ctrl.text.trim();
                          if (name.isEmpty) return;
                          setState(() => saving = true);
                          await recorder.saveRecording(name);
                          if (ctx.mounted) Navigator.pop(ctx);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 9),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A1040),
                            borderRadius: BorderRadius.circular(8),
                            border:
                            Border.all(color: const Color(0xFFD060F0)),
                          ),
                          child: saving
                              ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Color(0xFFD060F0)),
                          )
                              : const Text('Save',
                              style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFFD060F0))),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());

  }

  // ── Source picker shown before starting a recording ────────────────────────

  Future<void> _startRecording(
      BuildContext context, RecordingService recorder) async {
    final source = await showDialog<RecordingSource>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: const Color(0xFF16161F),
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'What do you want to record?',
                style: TextStyle(
                    color: Color(0xFFDDDDFF),
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              _SourceOption(
                icon: Icons.piano,
                label: 'MIDI device',
                description: 'Records notes from your connected MIDI keyboard',
                color: const Color(0xFF4090FF),
                onTap: () => Navigator.pop(ctx, RecordingSource.midi),
              ),
              const SizedBox(height: 10),
              _SourceOption(
                icon: Icons.touch_app,
                label: 'On-screen keyboard',
                description: 'Records notes you play by tapping the screen',
                color: const Color(0xFFD060F0),
                onTap: () => Navigator.pop(ctx, RecordingSource.onScreen),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, null),
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF555577)),
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null) return; // user cancelled
    recorder.start(source: source);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: Stack(
        children: [

          // ── Layer 0: clean export canvas ─────────────────────────────────
          Positioned.fill(
            child: RepaintBoundary(
              key: _exportBoundaryKey,
              child: Container(
                color: const Color(0xFF0A0A0F),
                child: Column(
                  children: [
                    const Expanded(child: PianoRollVisualizer()),
                    Container(
                      height: 150,
                      decoration: const BoxDecoration(
                        color: Color(0xFF111118),
                        border: Border(
                          top: BorderSide(
                              color: Color(0x33FFFFFF), width: 1),
                        ),
                      ),
                      child: const PianoKeyboard(),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Layer 1: visible UI ──────────────────────────────────────────
          Container(
            color: const Color(0xFF0A0A0F),
            child: Column(
              children: [
                const Expanded(child: PianoRollVisualizer()),
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
          ),

          // Falling / Rising toggle
          Positioned(
            top: Platform.isAndroid? 32: 16,
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
                      border: Border.all(color: const Color(0xFF44446A)),
                    ),
                    child: Text(
                      state.fallingMode ? "Falling ↓" : "Rising ↑",
                      style: const TextStyle(
                          color: Color(0xFFD060F0), fontSize: 12),
                    ),
                  ),
                );
              },
            ),
          ),

          // Color picker button
          Positioned(
            bottom: 180,
            right: 16,
            child: Consumer<PianoState>(
              builder: (context, state, _) {
                final iconColor =
                state.dualColorMode ? state.leftColor : state.noteColor;
                return GestureDetector(
                  onTap: () {
                    showDialog(
                      context: context,
                      builder: (_) => ChangeNotifierProvider.value(
                        value: state,
                        child: const ColorPickerDialog(),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A28),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF44446A)),
                    ),
                    child: state.dualColorMode
                        ? ShaderMask(
                      shaderCallback: (bounds) => LinearGradient(
                        colors: [state.leftColor, state.rightColor],
                      ).createShader(bounds),
                      child: const Icon(Icons.palette,
                          color: Colors.white),
                    )
                        : Icon(Icons.palette, color: iconColor),
                  ),
                );
              },
            ),
          ),

          // ── Record / Stop button ─────────────────────────────────────────
          Positioned(
            top: Platform.isAndroid? 32:16,
            right: 16,
            child: Consumer<RecordingService>(
              builder: (context, recorder, _) {
                // While recording, show a coloured badge indicating the source
                final isOnScreen =
                    recorder.currentSource == RecordingSource.onScreen;
                final activeColor =
                isOnScreen ? const Color(0xFFD060F0) : const Color(0xFF4090FF);

                return ElevatedButton.icon(
                  style: recorder.isRecording
                      ? ElevatedButton.styleFrom(
                    backgroundColor:
                    activeColor.withOpacity(0.15),
                    side: BorderSide(color: activeColor),
                  )
                      : null,
                  icon: Icon(
                    recorder.isRecording ? Icons.stop : Icons.fiber_manual_record,
                    size: 16,
                    color: recorder.isRecording ? activeColor : null,
                  ),
                  label: Text(
                    recorder.isRecording
                        ? 'Stop  (${isOnScreen ? "Screen" : "MIDI"})'
                        : 'Record',
                    style: TextStyle(
                        color: recorder.isRecording ? activeColor : null),
                  ),
                  onPressed: () {
                    if (recorder.isRecording) {
                      recorder.stop();
                      _showSaveDialog(context, recorder);
                    } else {
                      _startRecording(context, recorder);
                    }
                  },
                );
              },
            ),
          ),

          // Recordings panel
          Positioned(
            top: Platform.isAndroid? 76:60,
            right: 16,
            child: RecordingsPanel(),
          ),

          // MIDI device panel
          const MidiDeviceButton(),
        ],
      ),
    );
  }
}

// ── Small helper widget for the source picker dialog ─────────────────────────

class _SourceOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const _SourceOption({
    required this.icon,
    required this.label,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: color,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(description,
                      style: const TextStyle(
                          color: Color(0xFF777799), fontSize: 11)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color.withOpacity(0.6), size: 18),
          ],
        ),
      ),
    );
  }
}