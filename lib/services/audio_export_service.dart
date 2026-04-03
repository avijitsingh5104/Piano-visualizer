import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'recording_service.dart';
import '../utils/constants.dart';

class AudioExportService {
  AudioExportService._();
  static final instance = AudioExportService._();

  final names = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'];

  // Must match the visual press offset in play() so audio is in sync
  static const int _audioOffset = kFallDurationMs - 400;

  // Max note-on events per ffmpeg call. Keeps the command line well under
  // Windows's 8191-char limit and Linux/macOS open-file-descriptor limits.
  static const int _chunkSize = 50;

  // ── ffmpeg runner: Process on Windows/Linux, plugin on Android/iOS ──────

  Future<bool> _runFfmpeg(List<String> args) async {
    if (Platform.isWindows || Platform.isLinux) {
      final result = await Process.run('ffmpeg', args, runInShell: true);
      if (result.exitCode != 0) {
        print('ffmpeg error:\n${result.stderr}');
        return false;
      }
      return true;
    } else {
      // Android / iOS / macOS — use ffmpeg_kit plugin
      // Wrap args that contain spaces in quotes
      final cmd = args.map((a) => a.contains(' ') ? '"$a"' : a).join(' ');
      final session = await FFmpegKit.execute(cmd);
      final rc = await session.getReturnCode();
      if (!ReturnCode.isSuccess(rc)) {
        final log = await session.getOutput();
        print('ffmpeg_kit error:\n$log');
        return false;
      }
      return true;
    }
  }

  // ── Main entry point ─────────────────────────────────────────────────────

  Future<String?> generateAudio(List<MidiEvent> events) async {
    if (events.isEmpty) return null;

    final noteOns = events.where((e) => e.isOn).toList();
    if (noteOns.isEmpty) return null;

    final tmp   = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;

    // ── Step 1: mix notes in chunks of _chunkSize ────────────────────────
    final chunkPaths = <String>[];

    for (int start = 0; start < noteOns.length; start += _chunkSize) {
      final end   = (start + _chunkSize).clamp(0, noteOns.length);
      final chunk = noteOns.sublist(start, end);

      final chunkPath = '${tmp.path}/chunk_${stamp}_$start.wav';
      final ok = await _mixChunk(chunk, chunkPath);
      if (!ok) return null;
      chunkPaths.add(chunkPath);
    }

    // ── Step 2: if only one chunk, that is the final file ────────────────
    if (chunkPaths.length == 1) return chunkPaths.first;

    // ── Step 3: merge all chunk WAVs into a single output ────────────────
    final outPath = '${tmp.path}/audio_$stamp.wav';
    final merged  = await _mergeChunks(chunkPaths, outPath);

    // Clean up intermediate chunk files
    for (final p in chunkPaths) {
      try { await File(p).delete(); } catch (_) {}
    }

    return merged ? outPath : null;
  }

  // ── Mix one chunk of note-on events into a WAV ───────────────────────────

  Future<bool> _mixChunk(List<MidiEvent> notes, String outPath) async {
    final args    = <String>['-y'];
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
      filters.add(
          '${mixInputs}amix=inputs=${notes.length}:dropout_transition=0:normalize=0[aout]');
    }

    args.addAll([
      '-filter_complex', filters.join('; '),
      '-map', '[aout]',
      '-c:a', 'pcm_s16le',
      outPath,
    ]);

    return await _runFfmpeg(args);
  }

  // ── Merge pre-mixed chunk WAVs into the final output ─────────────────────

  Future<bool> _mergeChunks(List<String> paths, String outPath) async {
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
        final dest   = isLast
            ? outPath
            : '${tmp.path}/merge_${stamp}_${pass}_$start.wav';

        if (batch.length == 1) {
          // Nothing to mix, just copy
          final ok = await _runFfmpeg(
              ['-y', '-i', batch[0], '-c:a', 'pcm_s16le', dest]);
          if (!ok) return false;
        } else {
          final args         = <String>['-y'];
          final mergeFilters = <String>[];

          for (int i = 0; i < batch.length; i++) {
            args.addAll(['-i', batch[i]]);
            mergeFilters.add('[$i:a]anull[a$i]');
          }

          final mixInputs =
          List.generate(batch.length, (i) => '[a$i]').join();
          mergeFilters.add(
              '${mixInputs}amix=inputs=${batch.length}:dropout_transition=0:normalize=0[aout]');

          args.addAll([
            '-filter_complex', mergeFilters.join('; '),
            '-map', '[aout]',
            '-c:a', 'pcm_s16le',
            dest,
          ]);

          final ok = await _runFfmpeg(args);
          if (!ok) return false;
        }

        next.add(dest);
      }

      // Clean up intermediate pass files
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

  // ── Helpers ──────────────────────────────────────────────────────────────

  Future<String> _noteToFile(int midi) async {
    final note      = names[midi % 12];
    final octave    = (midi ~/ 12) - 1;
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