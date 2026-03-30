// lib/widgets/keyboard_widget.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/piano_state.dart';
import '../services/recording_service.dart';

// Semitones 0–11 that are black keys
const _blackSemitones = {1, 3, 6, 8, 10};
bool _isBlack(int midi) => _blackSemitones.contains(midi % 12);

// — Widget —
class PianoKeyboard extends StatefulWidget {
  const PianoKeyboard({super.key});

  @override
  State<PianoKeyboard> createState() => _PianoKeyboardState();
}

class _PianoKeyboardState extends State<PianoKeyboard> {
  // Maps each active pointer ID → the midi note it is currently holding.
  // This is what enables true polyphony: each finger is tracked independently.
  final Map<int, int> _pointerNotes = {};

  // ── Pointer down: a new finger touches the screen ──────────────────────
  void _onPointerDown(PointerDownEvent event, PianoState state,
      RecordingService recorder) {
    final midi = _midiAt(event.localPosition);
    if (midi == null) return;

    // If this pointer is somehow already tracked (shouldn't happen), release it first.
    _releasePointer(event.pointer, state, recorder);

    _pointerNotes[event.pointer] = midi;
    state.pressNote(midi);

    if (recorder.isRecording &&
        recorder.currentSource == RecordingSource.onScreen) {
      recorder.recordNoteOn(midi, 100);
    }
  }

  // ── Pointer move: finger slides to a different key ─────────────────────
  void _onPointerMove(PointerMoveEvent event, PianoState state,
      RecordingService recorder) {
    final newMidi = _midiAt(event.localPosition);
    final oldMidi = _pointerNotes[event.pointer];

    // Nothing changed — same key or outside keyboard
    if (newMidi == oldMidi) return;

    // Release the old note for this finger
    if (oldMidi != null) {
      // Only fully release the note if no OTHER finger is still holding it
      final stillHeld = _pointerNotes.entries
          .any((e) => e.key != event.pointer && e.value == oldMidi);
      if (!stillHeld) {
        state.releaseNote(oldMidi);
        if (recorder.isRecording &&
            recorder.currentSource == RecordingSource.onScreen) {
          recorder.recordNoteOff(oldMidi);
        }
      }
      _pointerNotes.remove(event.pointer);
    }

    // Press the new note (if still on the keyboard)
    if (newMidi != null) {
      _pointerNotes[event.pointer] = newMidi;
      state.pressNote(newMidi);
      if (recorder.isRecording &&
          recorder.currentSource == RecordingSource.onScreen) {
        recorder.recordNoteOn(newMidi, 100);
      }
    }
  }

  // ── Pointer up / cancel: finger lifts ─────────────────────────────────
  void _onPointerUp(int pointerId, PianoState state,
      RecordingService recorder) {
    _releasePointer(pointerId, state, recorder);
  }

  // ── Internal: release one pointer's note if nothing else holds it ─────
  void _releasePointer(int pointerId, PianoState state,
      RecordingService recorder) {
    final midi = _pointerNotes.remove(pointerId);
    if (midi == null) return;

    // Only send note-off if no other finger is holding the same note
    final stillHeld = _pointerNotes.values.contains(midi);
    if (!stillHeld) {
      state.releaseNote(midi);
      if (recorder.isRecording &&
          recorder.currentSource == RecordingSource.onScreen) {
        recorder.recordNoteOff(midi);
      }
    }
  }

  // ── Hit-test helper (delegates to painter's static method) ────────────
  int? _midiAt(Offset localPos) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return _KeyboardPainter.midiAt(localPos, box.size);
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<PianoState, RecordingService>(
      builder: (context, state, recorder, _) {
        // Use Listener instead of GestureDetector so that every individual
        // pointer (finger) is reported separately — this is what makes
        // multi-touch / polyphonic playing possible.
        return Listener(
          onPointerDown:   (e) => _onPointerDown(e, state, recorder),
          onPointerMove:   (e) => _onPointerMove(e, state, recorder),
          onPointerUp:     (e) => _onPointerUp(e.pointer, state, recorder),
          onPointerCancel: (e) => _onPointerUp(e.pointer, state, recorder),
          child: CustomPaint(
            painter: _KeyboardPainter(Set.of(state.activeNotes), state),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Painter — unchanged from original except accepting state for color support
// ─────────────────────────────────────────────────────────────────────────────

class _KeyboardPainter extends CustomPainter {
  final Set<int> activeNotes;
  final PianoState state;

  _KeyboardPainter(this.activeNotes, this.state);

  Color get noteColor => state.noteColor;

  static const _start = 21;  // A0
  static const _end   = 108; // C8

  static List<int> get _whites =>
      [for (var m = _start; m <= _end; m++) if (!_isBlack(m)) m];

  @override
  void paint(Canvas canvas, Size size) {
    final whites = _whites;
    final ww = size.width / whites.length;
    final bw = ww * 0.60;
    final bh = size.height * 0.62;

    // — White keys —
    for (int i = 0; i < whites.length; i++) {
      final midi   = whites[i];
      final active = activeNotes.contains(midi);
      final rect   = Rect.fromLTWH(i * ww + 0.5, 0, ww - 1.5, size.height - 2);
      final keyColor = state.colorForNote(midi);

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end:   Alignment.bottomCenter,
            colors: active
                ? [keyColor.withOpacity(0.7), keyColor]
                : [const Color(0xFFF5F5FA), const Color(0xFFD0D0E0)],
          ).createShader(rect),
      );

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()
          ..color       = active ? keyColor.withOpacity(0.8) : const Color(0xFFAAAAAA)
          ..style       = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );

      if (active) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          Paint()
            ..color      = keyColor.withOpacity(0.25)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
        );
      }
    }

    // — Black keys —
    int wi = 0;
    for (int midi = _start; midi <= _end; midi++) {
      if (!_isBlack(midi)) { wi++; continue; }

      final active   = activeNotes.contains(midi);
      final x        = (wi - 1) * ww + (ww - bw / 2) * 0.9;
      final rect     = Rect.fromLTWH(x, 0, bw, bh);
      final keyColor = state.colorForNote(midi);

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..color = active ? keyColor : const Color(0xFF1A1A25),
      );

      if (active) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          Paint()
            ..color      = keyColor.withOpacity(0.4)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }
    }

    // — Top glow bar —
    final glowColors = state.dualColorMode
        ? [
      Colors.transparent,
      state.leftColor.withOpacity(0.7),
      state.rightColor.withOpacity(0.7),
      Colors.transparent,
    ]
        : [
      Colors.transparent,
      noteColor.withOpacity(0.6),
      noteColor.withOpacity(0.9),
      noteColor.withOpacity(0.6),
      Colors.transparent,
    ];
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 3),
      Paint()
        ..shader = LinearGradient(colors: glowColors)
            .createShader(Rect.fromLTWH(0, 0, size.width, 3)),
    );
  }

  // — Hit test —
  static int? midiAt(Offset pos, Size size) {
    final whites = _whites;
    final ww = size.width / whites.length;
    final bw = ww * 0.60;
    final bh = size.height * 0.62;

    int wi = 0;
    for (int midi = _start; midi <= _end; midi++) {
      if (!_isBlack(midi)) { wi++; continue; }
      final x = (wi - 1) * ww + (ww - bw / 2) * 0.9;
      if (pos.dx >= x && pos.dx <= x + bw && pos.dy <= bh) return midi;
    }

    final idx = (pos.dx / ww).floor();
    if (idx >= 0 && idx < whites.length) return whites[idx];
    return null;
  }

  @override
  bool shouldRepaint(_KeyboardPainter old) =>
      !setEquals(old.activeNotes, activeNotes) ||
          old.state.noteColor     != state.noteColor     ||
          old.state.dualColorMode != state.dualColorMode ||
          old.state.leftColor     != state.leftColor     ||
          old.state.rightColor    != state.rightColor    ||
          old.state.splitMidi     != state.splitMidi;
}