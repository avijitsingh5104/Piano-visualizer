// lib/widgets/recordings_panel.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/recording_service.dart';
import '../services/video_export_service.dart';
import '../models/piano_state.dart';
import '../services/audio_export_service.dart';

class RecordingsPanel extends StatefulWidget {
  const RecordingsPanel({super.key});

  @override
  State<RecordingsPanel> createState() => _RecordingsPanelState();
}

class _RecordingsPanelState extends State<RecordingsPanel> {
  bool _open = false;

  bool _exporting    = false;
  double _progress   = 0.0;
  String _status     = '';
  String? _exportingRecordingPath;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<RecordingService>().loadSavedRecordings();
    });

    VideoExportService.instance.onStateChanged = () {
      if (!mounted) return;
      setState(() {
        _exporting = VideoExportService.instance.isExporting;
        _progress  = VideoExportService.instance.progress;
        _status    = VideoExportService.instance.status;
      });
    };
  }

  @override
  void dispose() {
    VideoExportService.instance.onStateChanged = null;
    super.dispose();
  }

  String _formatDuration(int ms) {
    final s  = (ms / 1000).round();
    final m  = s ~/ 60;
    final ss = s % 60;
    return '$m:${ss.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}  '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _exportVideo(
      BuildContext context,
      RecordingService recorder,
      PianoState piano,
      SavedRecording rec,
      ) async {
    if (_exporting || recorder.isPlaying) return;

    setState(() => _exportingRecordingPath = rec.filePath);

    final loaded = await recorder.loadRecording(rec);
    if (!loaded) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Playing back to capture frames… please wait.',
            style: TextStyle(color: Colors.white)),
        backgroundColor: Color(0xFF2A1040),
        duration: Duration(seconds: 3),
      ),
    );

    await recorder.play(piano, rec.filePath, captureVideo: true);

    if (recorder.capturedFrames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No frames captured. Try again.',
              style: TextStyle(color: Colors.white)),
          backgroundColor: Color(0xFF400A0A),
        ),
      );
      setState(() => _exportingRecordingPath = null);
      return;
    }

    final audioPath = await AudioExportService.instance
        .generateAudio(recorder.events);

    if (audioPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Audio generation failed')),
      );
      setState(() => _exportingRecordingPath = null);
      return;
    }

    // FIX: pass List<CapturedFrame> (with timestamps) instead of List<Uint8List>
    final outputPath = await VideoExportService.instance.exportFramesToMp4(
      frames:     List.of(recorder.capturedFrames),
      audioPath:  audioPath,
      outputName: rec.name.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_'),
    );

    setState(() => _exportingRecordingPath = null);

    if (outputPath != null && context.mounted) {
      final wantSave = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          backgroundColor: const Color(0xFF16161F),
          title: const Text('Video ready!',
              style: TextStyle(fontSize: 15, color: Color(0xFFDDDDFF))),
          content: const Text(
            'What would you like to do with the exported MP4?',
            style: TextStyle(color: Color(0xFF888899), fontSize: 13),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.folder_open, size: 16,
                  color: Color(0xFF6090CC)),
              label: const Text('Save to folder',
                  style: TextStyle(color: Color(0xFF6090CC))),
              onPressed: () => Navigator.pop(context, true),
            ),
            TextButton.icon(
              icon: const Icon(Icons.share, size: 16,
                  color: Color(0xFFD060F0)),
              label: const Text('Share',
                  style: TextStyle(color: Color(0xFFD060F0))),
              onPressed: () => Navigator.pop(context, false),
            ),
          ],
        ),
      );

      if (wantSave == true) {
        final saved = await VideoExportService.instance
            .saveToFile(outputPath, rec.name);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(saved ? 'Video saved!' : 'Save cancelled.',
                style: const TextStyle(color: Colors.white)),
            backgroundColor:
            saved ? const Color(0xFF0A2A0A) : const Color(0xFF2A1040),
          ));
        }
      } else if (wantSave == false) {
        await VideoExportService.instance.shareFile(outputPath, rec.name);
      }
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Export failed. Check logs.',
              style: TextStyle(color: Colors.white)),
          backgroundColor: Color(0xFF400A0A),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<RecordingService, PianoState>(
      builder: (context, recorder, piano, _) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [

            // ── Toggle button ─────────────────────────────────────
            GestureDetector(
              onTap: () => setState(() => _open = !_open),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A28),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF44446A)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.library_music,
                        size: 14, color: Color(0xFF6060A0)),
                    const SizedBox(width: 6),
                    Text(
                      'Recordings (${recorder.savedRecordings.length})',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF6060A0)),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      _open ? Icons.expand_less : Icons.expand_more,
                      size: 14,
                      color: const Color(0xFF6060A0),
                    ),
                  ],
                ),
              ),
            ),

            // ── Export progress bar ────────────────────────────────
            if (_exporting)
              Container(
                width: 300,
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161F),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF3060A0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_status,
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF6090CC))),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: _progress,
                      backgroundColor: const Color(0xFF1A2A3A),
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF3060A0)),
                    ),
                  ],
                ),
              ),

            // ── Recordings list ────────────────────────────────────
            if (_open)
              Container(
                width: 300,
                margin: const EdgeInsets.only(top: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF16161F),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF33334A)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (recorder.savedRecordings.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('No recordings yet.',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF555577))),
                      )
                    else
                      ...recorder.savedRecordings.map((rec) => _RecordingRow(
                        recording:            rec,
                        currentlyPlayingPath: recorder.currentlyPlayingPath,
                        recordingPath:        rec.filePath,
                        formatDuration:       _formatDuration,
                        formatDate:           _formatDate,
                        isExportingThis:      _exportingRecordingPath == rec.filePath,
                        onPlay: () async {
                          final ok = await recorder.loadRecording(rec);
                          if (ok) recorder.play(piano, rec.filePath);
                        },
                        onStop:        () => recorder.stopPlayback(piano),
                        onDelete:      () => recorder.deleteRecording(rec),
                        onExportVideo: () =>
                            _exportVideo(context, recorder, piano, rec),
                      )),

                    const Divider(color: Color(0xFF22223A), height: 1),

                    // Save row
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: _SaveRow(
                        onSave: (name) async {
                          await recorder.saveRecording(name);
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Save row ──────────────────────────────────────────────────────────────────

class _SaveRow extends StatefulWidget {
  final Future<void> Function(String name) onSave;
  const _SaveRow({required this.onSave});

  @override
  State<_SaveRow> createState() => _SaveRowState();
}

class _SaveRowState extends State<_SaveRow> {
  final _ctrl  = TextEditingController();
  bool _saving = false;

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            style: const TextStyle(fontSize: 13, color: Color(0xFFDDDDFF)),
            decoration: InputDecoration(
              hintText: 'Recording name…',
              hintStyle: const TextStyle(color: Color(0xFF555577), fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF0A0A0F),
              contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                const BorderSide(color: Color(0xFF33334A), width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                const BorderSide(color: Color(0xFF33334A), width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                const BorderSide(color: Color(0xFFD060F0), width: 1),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _saving ? null : () async {
            final name = _ctrl.text.trim();
            if (name.isEmpty) return;
            setState(() => _saving = true);
            await widget.onSave(name);
            _ctrl.clear();
            setState(() => _saving = false);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF2A1040),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD060F0)),
            ),
            child: _saving
                ? const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFFD060F0)),
            )
                : const Text('Save',
                style: TextStyle(fontSize: 12, color: Color(0xFFD060F0))),
          ),
        ),
      ],
    );
  }
}

// ── Single recording row ──────────────────────────────────────────────────────

class _RecordingRow extends StatelessWidget {
  final SavedRecording recording;
  final String? currentlyPlayingPath;
  final String recordingPath;
  final String Function(int) formatDuration;
  final String Function(DateTime) formatDate;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final VoidCallback onDelete;
  final VoidCallback onExportVideo;
  final bool isExportingThis;

  const _RecordingRow({
    required this.recording,
    required this.currentlyPlayingPath,
    required this.recordingPath,
    required this.formatDuration,
    required this.formatDate,
    required this.onPlay,
    required this.onStop,
    required this.onDelete,
    required this.onExportVideo,
    required this.isExportingThis,
  });

  @override
  Widget build(BuildContext context) {
    final isThisPlaying = currentlyPlayingPath == recordingPath;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recording.name,
                      style: const TextStyle(
                        color: Color(0xFFDDDDFF),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${formatDuration(recording.durationMs)}  ·  '
                          '${formatDate(recording.savedAt)}',
                      style: const TextStyle(
                        color: Color(0xFF555577),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),

              // Play / Stop
              GestureDetector(
                onTap: isThisPlaying ? onStop : onPlay,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A1040),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFD060F0)),
                  ),
                  child: Icon(
                    isThisPlaying ? Icons.stop : Icons.play_arrow,
                    size: 16, color: const Color(0xFFD060F0),
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // Delete
              GestureDetector(
                onTap: onDelete,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A0A0A),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF883030)),
                  ),
                  child: const Icon(Icons.delete_outline,
                      size: 16, color: Color(0xFFCC4040)),
                ),
              ),
            ],
          ),

          // Export Video button
          const SizedBox(height: 6),
          GestureDetector(
            onTap: isExportingThis ? null : onExportVideo,
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF0A1A2A),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isExportingThis
                      ? const Color(0xFF335566)
                      : const Color(0xFF3060A0),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isExportingThis)
                    const SizedBox(
                      width: 12, height: 12,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Color(0xFF6090CC)),
                    )
                  else
                    const Icon(Icons.videocam_outlined,
                        size: 14, color: Color(0xFF6090CC)),
                  const SizedBox(width: 6),
                  Text(
                    isExportingThis ? 'Exporting…' : 'Export as MP4',
                    style: const TextStyle(
                        fontSize: 11, color: Color(0xFF6090CC)),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 4),
        ],
      ),
    );
  }
}