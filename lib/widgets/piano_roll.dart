// lib/widgets/piano_roll.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';
import '../models/piano_state.dart';
import '../utils/constants.dart';

const _blackSemitones = {1, 3, 6, 8, 10};
bool _isBlack(int midi) => _blackSemitones.contains(midi % 12);

final Map<int, (double xFrac, double wFrac)> _noteLayout = () {
  final map = <int, (double, double)>{};
  final totalWhites =
      [for (int m = 21; m <= 108; m++) if (!_isBlack(m)) m].length;
  final ww = 1.0 / totalWhites;
  final bw = ww * 0.6;
  int wi = 0;
  for (int m = 21; m <= 108; m++) {
    if (!_isBlack(m)) {
      map[m] = (wi * ww, ww * 0.8);
      wi++;
    } else {
      final x = (wi - 1) * ww + (ww - bw / 2) * 0.9;
      map[m] = (x, bw * 0.8);
    }
  }
  return map;
}();

class PianoRollVisualizer extends StatefulWidget {
  const PianoRollVisualizer({super.key});

  @override
  State<PianoRollVisualizer> createState() => _PianoRollVisualizerState();
}

class _PianoRollVisualizerState extends State<PianoRollVisualizer>
    with SingleTickerProviderStateMixin {

  final Map<int, DateTime> _liveNoteStart = {};
  final _repaintNotifier = ValueNotifier<int>(0);

  Set<int> _lastNotes = {};
  bool? _lastMode;
  bool _isFalling = true;
  double _canvasHeight = 600;

  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();

    _ticker = createTicker((_) {
      final state = context.read<PianoState>();
      final now   = DateTime.now();

      state.bars.removeWhere((bar) {
        _updateBarPosition(bar, now);
        if (_isFalling) return bar.y > _canvasHeight + 50;
        return bar.y + bar.height < -50;
      });

      _repaintNotifier.value++;
    })..start();
  }

  void _updateBarPosition(NoteBar bar, DateTime now) {
    if (!bar.isPlayback) {
      final elapsedMs = now.difference(bar.spawnedAt).inMicroseconds / 1000.0;
      final travelled = (elapsedMs / kFallDurationMs) * _canvasHeight;

      if (_isFalling) {
        // Bar bottom starts at top (y=0), moves down
        // Height grows until full bar height is revealed
        final visibleHeight = min(travelled, bar.height);
        bar.y = travelled - visibleHeight;
        bar.visibleHeight = visibleHeight;
      } else {
        final visibleHeight = min(travelled, bar.height);
        bar.y = _canvasHeight - travelled;
        bar.visibleHeight = visibleHeight;
      }
    } else {
      final elapsedMs   = now.difference(bar.spawnedAt).inMicroseconds / 1000.0;
      final travelTotal = _canvasHeight + bar.height;
      final travelled   = (elapsedMs / kFallDurationMs) * travelTotal;
      bar.y = _isFalling ? -bar.height + travelled : _canvasHeight - travelled;
      bar.visibleHeight = bar.height; // playback bars always full height
    }
    bar.phase = (bar.phase + 0.1) % (2 * pi);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _repaintNotifier.dispose();
    super.dispose();
  }

  void _handleLiveNotes(PianoState state, Set<int> currentNotes, bool isFalling) {
    final now = DateTime.now();
    for (final midi in currentNotes.difference(_lastNotes)) {
      _liveNoteStart[midi] = now;
    }
    for (final midi in _lastNotes.difference(currentNotes)) {
      final start = _liveNoteStart.remove(midi);
      if (start != null) {
        final height =
        (now.difference(start).inMilliseconds / 5).clamp(20, 300).toDouble();
        state.bars.add(NoteBar.live(
          midi: midi, y: isFalling ? -height : _canvasHeight,
          height: height, velocity: 100,
        ));
      }
    }
    _lastNotes = Set.of(currentNotes);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _canvasHeight = constraints.maxHeight;

      return Consumer<PianoState>(builder: (_, state, __) {
        _isFalling = state.fallingMode;

        if (_lastMode != state.fallingMode) {
          state.bars.clear();
          _liveNoteStart.clear();
          _lastNotes.clear();
          _lastMode = state.fallingMode;
        }

        if (!state.isPlaying) {
          _handleLiveNotes(state, state.activeNotes, state.fallingMode);
        }

        return CustomPaint(
          painter: _RollPainter(
            bars:     state.bars,
            state:    state,
            isFalling: _isFalling,
            repaint:  _repaintNotifier,
          ),
          size: Size.infinite,
        );
      });
    });
  }
}

// ── Data ──────────────────────────────────────────────────────────────────────

class NoteBar {
  final int midi;
  double y;
  final double height;
  double visibleHeight;
  final int velocity;
  double phase;
  final bool isPlayback;
  final DateTime spawnedAt;

  NoteBar.playback({
    required this.midi, required this.height,
    required this.velocity, required this.spawnedAt,
  })  : y = 0, phase = 0, isPlayback = true, visibleHeight=0;

  NoteBar.live({
    required this.midi, required this.y,
    required this.height, required this.velocity,
  })  : phase = 0, isPlayback = false, visibleHeight=0,
        spawnedAt = DateTime.now();
}

// ── Painter ───────────────────────────────────────────────────────────────────

class _RollPainter extends CustomPainter {
  final List<NoteBar> bars;
  final PianoState state; // needed for colorForNote()
  final bool isFalling;

  _RollPainter({
    required this.bars,
    required this.state,
    required this.isFalling,
    required ValueNotifier<int> repaint,
  }) : super(repaint: repaint);

  final _fillPaint   = Paint();
  final _glowPaint   = Paint()..maskFilter = null;
  final _borderPaint = Paint()
    ..color       = Colors.black.withOpacity(0.4)
    ..style       = PaintingStyle.stroke
    ..strokeWidth = 1.2;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF0A0A0F),
    );

    final w = size.width;

    for (final bar in bars) {
      final layout = _noteLayout[bar.midi];
      if (layout == null) continue;

      final x     = layout.$1 * w;
      final width = layout.$2 * w;
      final rect  = Rect.fromLTWH(x, bar.y, width, bar.visibleHeight);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));

      final brightness = (bar.velocity / 127).clamp(0.4, 1.0);
      final pulse      = 0.5 + 0.5 * sin(bar.phase);

      // Use colorForNote() so single/dual mode is handled in one place
      final baseColor = state
          .colorForNote(bar.midi)
          .withOpacity(brightness.toDouble());

      _fillPaint.shader = LinearGradient(
        begin: Alignment.topCenter,
        end:   Alignment.bottomCenter,
        colors: [
          baseColor.withOpacity(0.5 + 0.3 * pulse),
          baseColor,
        ],
      ).createShader(rect);
      canvas.drawRRect(rrect, _fillPaint);

      final glowOpacity = 0.18 * pulse;
      if (glowOpacity > 0.01) {
        _glowPaint.color = baseColor.withOpacity(glowOpacity);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(6), const Radius.circular(8)),
          _glowPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect.inflate(3), const Radius.circular(6)),
          _glowPaint,
        );
      }

      canvas.drawRRect(rrect, _borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => true;
}