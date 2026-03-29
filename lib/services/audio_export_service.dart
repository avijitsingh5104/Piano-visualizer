import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'recording_service.dart';
import '../utils/constants.dart';

class AudioExportService {
  AudioExportService._();
  static final instance = AudioExportService._();

  final names = ['C','Db','D','Eb','E','F','Gb','G','Ab','A','Bb','B'];

  // Must match the visual press offset in play() so audio is in sync
  static const int _audioOffset = kFallDurationMs - 400;

  // Max note-on events per ffmpeg call. Keeps the command line well under
  // Windows's 8191-char limit and Linux/macOS open-file-descriptor limits.
  // Each input adds ~55 chars on Windows paths, so 50 gives ~2750 chars of
  // inputs — safe even with long usernames / deep temp paths.
  static const int _chunkSize = 50;

  Future<String?> generateAudio(List<MidiEvent> events) async {
    if (events.isEmpty) return null;

    final noteOns = events.where((e) => e.isOn).toList();
    if (noteOns.isEmpty) return null;

    final tmp   = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;

    // ── Step 1: mix notes in chunks of _chunkSize ────────────────────────
    // Each chunk produces one intermediate WAV that already has the correct
    // delays baked in (relative to t=0 of the full recording).
    final chunkPaths = <String>[];

    for (int start = 0; start < noteOns.length; start += _chunkSize) {
      final end   = (start + _chunkSize).clamp(0, noteOns.length);
      final chunk = noteOns.sublist(start, end);

      final chunkPath = '${tmp.path}/chunk_${stamp}_${start}.wav';
      final ok = await _mixChunk(chunk, chunkPath);
      if (!ok) return null;
      chunkPaths.add(chunkPath);
    }

    // ── Step 2: if only one chunk, that is the final file ────────────────
    if (chunkPaths.length == 1) return chunkPaths.first;

    // ── Step 3: merge all chunk WAVs into a single output ────────────────
    // The chunks are already time-aligned (each baked from t=0), so we just
    // amix them with no additional delay.
    final outPath = '${tmp.path}/audio_$stamp.wav';
    final merged  = await _mergeChunks(chunkPaths, outPath);

    // Clean up intermediate chunk files
    for (final p in chunkPaths) {
      try { await File(p).delete(); } catch (_) {}
    }

    return merged ? outPath : null;
  }

  // ── Mix one chunk of note-on events into a WAV ──────────────────────────

  Future<bool> _mixChunk(List<MidiEvent> notes, String outPath) async {
    final args    = <String>[];
    final filters = <String>[];

    for (int i = 0; i < notes.length; i++) {
      final filePath = await _noteToFile(notes[i].note);
      args.addAll(['-i', filePath]);
      final delay = notes[i].time + _audioOffset;
      filters.add('[$i:a]adelay=${delay}|${delay}[a$i]');
    }

    final mixInputs = List.generate(notes.length, (i) => '[a$i]').join();

    if (notes.length == 1) {
      filters.add('[a0]anull[aout]');
    } else {
      filters.add('${mixInputs}amix=inputs=${notes.length}:dropout_transition=0:normalize=0[aout]');
    }

    args.addAll([
      '-filter_complex', filters.join('; '),
      '-map', '[aout]',
      '-c:a', 'pcm_s16le',
      outPath,
    ]);

    final result = await Process.run('ffmpeg', args, runInShell: true);
    if (result.exitCode != 0) {
      print('Chunk mix error:\n${result.stderr}');
      return false;
    }
    return true;
  }

  // ── Merge pre-mixed chunk WAVs into the final output ────────────────────
  // Also chunked: if there are more than _chunkSize chunks (extremely unlikely
  // but possible for multi-hour recordings), recurse until one file remains.

  Future<bool> _mergeChunks(List<String> paths, String outPath) async {
    // Merge in batches if somehow even the chunk count is large
    var current = paths;
    int pass    = 0;
    final tmp   = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;

    while (current.length > 1) {
      final next = <String>[];
      for (int start = 0; start < current.length; start += _chunkSize) {
        final end   = (start + _chunkSize).clamp(0, current.length);
        final batch = current.sublist(start, end);

        final isLast = end == current.length && start == 0;
        final dest   = isLast ? outPath
            : '${tmp.path}/merge_${stamp}_${pass}_$start.wav';

        final args    = <String>[];
        final filters = <String>[];

        for (int i = 0; i < batch.length; i++) {
          args.addAll(['-i', batch[i]]);
          filters.add('[$i:a]anull[a$i]'); // no extra delay; already baked
        }

        final mixInputs = List.generate(batch.length, (i) => '[a$i]').join();
        if (batch.length == 1) {
          // nothing to mix, just copy
          args.addAll(['-c:a', 'pcm_s16le', dest]);
          // drop the useless anull filter
          final r = await Process.run(
            'ffmpeg',
            ['-y', '-i', batch[0], '-c:a', 'pcm_s16le', dest],
            runInShell: true,
          );
          if (r.exitCode != 0) { print(r.stderr); return false; }
        } else {
          // amix with no normalization — chunks are already at full volume
          final mergeFilters = <String>[];
          for (int i = 0; i < batch.length; i++) {
            mergeFilters.add('[$i:a]anull[a$i]');
          }
          mergeFilters.add('${mixInputs}amix=inputs=${batch.length}:dropout_transition=0:normalize=0[aout]');

          final r = await Process.run(
            'ffmpeg',
            [
              '-y',
              ...args,
              '-filter_complex', mergeFilters.join('; '),
              '-map', '[aout]',
              '-c:a', 'pcm_s16le',
              dest,
            ],
            runInShell: true,
          );
          if (r.exitCode != 0) { print(r.stderr); return false; }
        }

        next.add(dest);
      }

      // Clean up intermediate pass files (not the originals or the final)
      if (pass > 0) {
        for (final p in current) {
          if (p != outPath && !paths.contains(p)) {
            try { await File(p).delete(); } catch (_) {}
          }
        }
      }

      current = next;
      pass++;
    }

    return true;
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  Future<String> _noteToFile(int midi) async {
    final note     = names[midi % 12];
    final octave   = (midi ~/ 12) - 1;
    final assetPath = 'assets/sounds/$note$octave.mp3';
    return await _copyAsset(assetPath);
  }

  Future<String> _copyAsset(String assetPath) async {
    final tmp  = await getTemporaryDirectory();
    final file = File('${tmp.path}/${assetPath.split('/').last}');
    // Always re-extract to avoid stale cached files
    final data = await rootBundle.load(assetPath);
    await file.writeAsBytes(data.buffer.asUint8List());
    return file.path;
  }
}