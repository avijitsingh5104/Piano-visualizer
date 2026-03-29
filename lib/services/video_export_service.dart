// lib/services/video_export_service.dart
//
// Uses ffmpeg_kit_flutter_new on Android/iOS/macOS,
// and dart:io Process.run (system ffmpeg) on Windows/Linux.
//
// ── pubspec.yaml changes ──────────────────────────────────────────────────
//   REMOVE:  ffmpeg_kit_flutter: any
//   ADD:     ffmpeg_kit_flutter_new: ^6.0.3
//             share_plus: ^7.2.2
// ─────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import 'recording_service.dart' show CapturedFrame;

/// Raw RGBA frame returned by captureFrame().
class RawFrame {
  final Uint8List bytes; // RGBA, width * height * 4 bytes
  final int width;
  final int height;
  RawFrame(this.bytes, this.width, this.height);
}

class VideoExportService {
  VideoExportService._();
  static final instance = VideoExportService._();

  bool   isExporting = false;
  double progress    = 0.0;
  String status      = '';

  void Function()? onStateChanged;

  /// Attach this key to the RepaintBoundary wrapping PianoRollVisualizer.
  GlobalKey? boundaryKey;

  // ── Frame capture ──────────────────────────────────────────────────────

  /// Returns raw RGBA pixels with zero compression work.
  /// rawRgba is ~10x faster than PNG because it skips all encoding —
  /// Flutter just copies the GPU framebuffer into a byte array.
  /// pixelRatio 1.0 (vs the old 1.5) quarters the pixel count,
  /// making both this call and later BMP writing significantly faster.
  Future<RawFrame?> captureFrame() async {
    await Future.delayed(Duration.zero);
    await WidgetsBinding.instance.endOfFrame;

    final key = boundaryKey;
    if (key == null) return null;

    final boundary =
    key.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    try {
      final image    = await boundary.toImage(pixelRatio: 1.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) return null;
      return RawFrame(byteData.buffer.asUint8List(), image.width, image.height);
    } catch (e) {
      debugPrint('captureFrame error: $e');
      return null;
    }
  }

  // ── Main export entry point ────────────────────────────────────────────

  Future<String?> exportFramesToMp4({
    required List<CapturedFrame> frames,
    required String audioPath,
    String outputName = 'piano_viz',
  }) async {
    if (frames.isEmpty) return null;

    _setState(exporting: true, progress: 0, status: 'Preparing frames…');

    try {
      final tmp   = await getTemporaryDirectory();
      final stamp = DateTime.now().millisecondsSinceEpoch;
      final frDir = Directory('${tmp.path}/piano_frames_$stamp');
      await frDir.create(recursive: true);

      // Write each frame as a BMP file.
      //
      // Why BMP?
      //   • dart:ui exposes rawRgba pixels but has no JPEG/PNG encoder we can
      //     call cheaply here. PNG encode is slow (that was the original problem).
      //   • BMP is a trivial format: a small fixed header + the raw BGR pixels.
      //     Writing it is O(pixels) with zero compression — extremely fast.
      //   • ffmpeg decodes BMP in one pass with no decompression overhead,
      //     so encoding to MP4 is just as fast as it would be from JPEG.
      //
      // The concat demuxer script carries real per-frame durations derived from
      // wall-clock timestamps, so playback speed is always correct regardless
      // of how fast capture ran on this device.
      final concatBuf = StringBuffer();

      for (int i = 0; i < frames.length; i++) {
        final frame    = frames[i];
        final filePath =
            '${frDir.path}/frame_${i.toString().padLeft(6, '0')}.bmp';

        // Convert RGBA → BMP off the main thread via compute()
        final bmpBytes = await compute(
          _rgbaToBmp,
          _BmpArgs(frame.rgbaBytes, frame.width, frame.height),
        );
        await File(filePath).writeAsBytes(bmpBytes, flush: false);

        // Real duration from wall-clock timestamps
        double durationSec;
        if (i < frames.length - 1) {
          final ms = frames[i + 1].capturedAt
              .difference(frames[i].capturedAt)
              .inMicroseconds / 1000.0;
          durationSec = ms.clamp(1.0, 200.0) / 1000.0;
        } else {
          durationSec = i > 0
              ? (frames[i].capturedAt
              .difference(frames[i - 1].capturedAt)
              .inMicroseconds / 1000.0)
              .clamp(1.0, 200.0) / 1000.0
              : 1.0 / 30.0;
        }

        // Escape single quotes so paths with apostrophes don't break concat
        final safePath = filePath.replaceAll("'", r"'\''");
        concatBuf.writeln("file '$safePath'");
        concatBuf.writeln('duration $durationSec');

        _setState(
          progress: i / frames.length * 0.5,
          status:   'Writing frame $i / ${frames.length}',
        );
      }

      // Duplicate last entry — required by the concat demuxer spec so ffmpeg
      // knows exactly when the last frame ends.
      final lastPath =
      '${frDir.path}/frame_${(frames.length - 1).toString().padLeft(6, '0')}.bmp'
          .replaceAll("'", r"'\''");
      concatBuf.writeln("file '$lastPath'");

      final concatFile = File('${frDir.path}/concat.txt');
      await concatFile.writeAsString(concatBuf.toString());

      final outDir   = await getApplicationDocumentsDirectory();
      final safeName = outputName.replaceAll(RegExp(r'[^\w]'), '_');
      final outPath  = '${outDir.path}/${safeName}_$stamp.mp4';

      _setState(progress: 0.5, status: 'Encoding video…');

      bool ok;
      if (Platform.isWindows || Platform.isLinux) {
        ok = await _encodeWithProcess(concatFile.path, outPath, audioPath);
      } else {
        ok = await _encodeWithPlugin(concatFile.path, outPath, audioPath);
      }

      await frDir.delete(recursive: true);

      if (!ok) {
        _setState(exporting: false, progress: 0, status: 'Export failed');
        return null;
      }

      _setState(exporting: false, progress: 1.0, status: 'Done!');
      return outPath;

    } catch (e) {
      _setState(exporting: false, progress: 0, status: 'Error: $e');
      debugPrint('VideoExportService error: $e');
      return null;
    }
  }

  // ── BMP encoder (top-level so compute() can call it) ──────────────────

  // Converts raw RGBA bytes into a 24-bit BMP file.
  // BMP stores pixels as BGR with each row padded to a 4-byte boundary.
  static Uint8List _rgbaToBmp(_BmpArgs args) {
    final rgba   = args.rgba;
    final width  = args.width;
    final height = args.height;

    final rowSize  = (width * 3 + 3) & ~3; // pad each row to 4 bytes
    final dataSize = rowSize * height;
    final fileSize = 54 + dataSize;
    final bmp      = ByteData(fileSize);

    // ── BITMAPFILEHEADER (14 bytes) ──────────────────────────────────────
    bmp.setUint8 (0, 0x42); bmp.setUint8(1, 0x4D); // signature 'BM'
    bmp.setUint32(2,  fileSize, Endian.little);     // file size
    bmp.setUint32(6,  0,        Endian.little);     // reserved
    bmp.setUint32(10, 54,       Endian.little);     // pixel data offset

    // ── BITMAPINFOHEADER (40 bytes) ──────────────────────────────────────
    bmp.setUint32(14, 40,      Endian.little); // header size
    bmp.setInt32 (18, width,   Endian.little); // image width
    bmp.setInt32 (22, -height, Endian.little); // negative = top-down scan
    bmp.setUint16(26, 1,       Endian.little); // color planes
    bmp.setUint16(28, 24,      Endian.little); // bits per pixel (RGB24)
    bmp.setUint32(30, 0,       Endian.little); // BI_RGB, no compression
    bmp.setUint32(34, dataSize,Endian.little); // image data size
    // remaining INFOHEADER fields (resolution, palette) stay zero

    // ── Pixel data: RGBA → BGR ───────────────────────────────────────────
    final out = bmp.buffer.asUint8List();
    for (int y = 0; y < height; y++) {
      final rowStart = 54 + y * rowSize;
      for (int x = 0; x < width; x++) {
        final src = (y * width + x) * 4; // RGBA source index
        final dst = rowStart + x * 3;    // BGR destination index
        out[dst + 0] = rgba[src + 2];    // B ← src R... wait: BMP is BGR
        out[dst + 1] = rgba[src + 1];    // G
        out[dst + 2] = rgba[src + 0];    // R
      }
    }
    return out;
  }

  // ── Backend A: ffmpeg_kit_flutter_new (Android / iOS / macOS) ─────────

  Future<bool> _encodeWithPlugin(
      String concatPath, String outPath, String audioPath) async {
    final cmd =
        '-y '
        '-f concat -safe 0 -i "$concatPath" '
        '-i "$audioPath" '
        '-vf "pad=ceil(iw/2)*2:ceil(ih/2)*2:0:0:color=black" '
        '-af apad '
        '-c:v libx264 -pix_fmt yuv420p -preset fast -crf 23 '
        '-c:a aac -b:a 192k '
        '-shortest '
        '"$outPath"';

    final session = await FFmpegKit.execute(cmd);
    final rc      = await session.getReturnCode();

    if (!ReturnCode.isSuccess(rc)) {
      final log = await session.getOutput();
      debugPrint('FFmpeg plugin error:\n$log');
      return false;
    }
    return true;
  }

  // ── Backend B: system ffmpeg binary (Windows / Linux) ─────────────────

  Future<bool> _encodeWithProcess(
      String concatPath, String outPath, String audioPath) async {
    final result = await Process.run(
      'ffmpeg',
      [
        '-y',
        '-f', 'concat',
        '-safe', '0',
        '-i', concatPath,
        '-i', audioPath,
        '-vf', 'pad=ceil(iw/2)*2:ceil(ih/2)*2:0:0:color=black',
        '-af', 'apad',
        '-c:v', 'libx264',
        '-pix_fmt', 'yuv420p',
        '-preset', 'fast',
        '-crf', '23',
        '-c:a', 'aac',
        '-b:a', '192k',
        '-shortest',
        outPath,
      ],
      runInShell: true,
    );

    if (result.exitCode != 0) {
      debugPrint('System ffmpeg stderr:\n${result.stderr}');
      return false;
    }
    return true;
  }

  // ── Share / save ───────────────────────────────────────────────────────

  Future<bool> saveToFile(String srcPath, String recordingName) async {
    final safeName = recordingName.replaceAll(RegExp(r'[^\w\s]'), '_');
    final destPath = await FilePicker.platform.saveFile(
      dialogTitle:       'Save video as…',
      fileName:          '$safeName.mp4',
      type:              FileType.video,
      allowedExtensions: ['mp4'],
    );
    if (destPath == null) return false;
    try {
      await File(srcPath).copy(destPath);
      return true;
    } catch (e) {
      debugPrint('saveToFile error: $e');
      return false;
    }
  }

  Future<bool> shareFile(String filePath, String recordingName) async {
    final result = await Share.shareXFiles(
      [XFile(filePath, mimeType: 'video/mp4', name: '$recordingName.mp4')],
      subject: 'PianoViz – $recordingName',
    );
    return result.status == ShareResultStatus.success ||
        result.status == ShareResultStatus.dismissed;
  }

  // ── Internal ───────────────────────────────────────────────────────────

  void _setState({bool? exporting, double? progress, String? status}) {
    if (exporting != null) isExporting = exporting;
    if (progress  != null) this.progress = progress;
    if (status    != null) this.status   = status;
    onStateChanged?.call();
  }
}

// Args struct for compute() — must be a plain data class (no closures)
class _BmpArgs {
  final Uint8List rgba;
  final int width;
  final int height;
  const _BmpArgs(this.rgba, this.width, this.height);
}