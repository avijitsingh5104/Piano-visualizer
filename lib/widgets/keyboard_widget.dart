// lib/widgets/keyboard_widget.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/piano_state.dart';

// Semitones 0–11 that are black keys
const _blackSemitones = {1, 3, 6, 8, 10};
bool _isBlack(int midi) => _blackSemitones.contains(midi % 12);

// — Widget —
class PianoKeyboard extends StatelessWidget {
  const PianoKeyboard({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<PianoState>(
      builder: (context, state, _) {
        return GestureDetector(
          onTapDown: (d) =>
              _onTouch(context, d.localPosition, state, reset: true),
          onTapUp: (_) => state.releaseAll(),
          onPanStart: (d) =>
              _onTouch(context, d.localPosition, state, reset: true),
          onPanUpdate: (d) =>
              _onTouch(context, d.localPosition, state, reset: false),
          onPanEnd: (_) => state.releaseAll(),
          child: CustomPaint(
            painter: _KeyboardPainter(
              Set.of(state.activeNotes),
              state.noteColor, // 🔥 pass color
            ),
            size: Size.infinite,
          ),
        );
      },
    );
  }
}

void _onTouch(
    BuildContext ctx,
    Offset pos,
    PianoState state, {
      required bool reset,
    }) {
  final box = ctx.findRenderObject() as RenderBox;
  final midi = _KeyboardPainter.midiAt(pos, box.size);
  if (midi != null) {
    if (reset) state.releaseAll();
    state.pressNote(midi);
  }
}

// — Painter —
class _KeyboardPainter extends CustomPainter {
  final Set<int> activeNotes;
  final Color noteColor;

  _KeyboardPainter(this.activeNotes, this.noteColor);

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
      final midi = whites[i];
      final active = activeNotes.contains(midi);
      final rect = Rect.fromLTWH(i * ww + 0.5, 0, ww - 1.5, size.height - 2);

      // Fill
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: active
                ? [
              noteColor.withOpacity(0.7),
              noteColor,
            ]
                : [
              const Color(0xFFF5F5FA),
              const Color(0xFFD0D0E0),
            ],
          ).createShader(rect),
      );

      // Border
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        Paint()
          ..color = active
              ? noteColor.withOpacity(0.8)
              : const Color(0xFFAAAAAA)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );

      // Glow
      if (active) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)),
          Paint()
            ..color = noteColor.withOpacity(0.25)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
        );
      }
    }

    // — Black keys —
    int wi = 0;
    for (int midi = _start; midi <= _end; midi++) {
      if (!_isBlack(midi)) {
        wi++;
        continue;
      }

      final active = activeNotes.contains(midi);
      final x = (wi - 1) * ww + (ww - bw / 2) * 0.9;
      final rect = Rect.fromLTWH(x, 0, bw, bh);

      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()
          ..color = active
              ? noteColor
              : const Color(0xFF1A1A25),
      );

      if (active) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          Paint()
            ..color = noteColor.withOpacity(0.4)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
        );
      }
    }

    // — Top glow bar —
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, 3),
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.transparent,
            noteColor.withOpacity(0.6),
            noteColor.withOpacity(0.9),
            noteColor.withOpacity(0.6),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, 3)),
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
      if (!_isBlack(midi)) {
        wi++;
        continue;
      }

      final x = (wi - 1) * ww + (ww - bw / 2) * 0.9;
      if (pos.dx >= x && pos.dx <= x + bw && pos.dy <= bh) {
        return midi;
      }
    }

    final idx = (pos.dx / ww).floor();
    if (idx >= 0 && idx < whites.length) return whites[idx];
    return null;
  }

  @override
  bool shouldRepaint(_KeyboardPainter old) =>
      !setEquals(old.activeNotes, activeNotes) ||
          old.noteColor != noteColor;
}