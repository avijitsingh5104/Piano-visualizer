// lib/widgets/color_picker_dialog.dart

import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/piano_state.dart';

// ── Entry point ───────────────────────────────────────────────────────────────

class ColorPickerDialog extends StatefulWidget {
  const ColorPickerDialog({super.key});

  @override
  State<ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<ColorPickerDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    final state = context.read<PianoState>();
    _tab = TabController(
      length: 2,
      vsync: this,
      initialIndex: state.dualColorMode ? 1 : 0,
    );
    _tab.addListener(() {
      context.read<PianoState>().setDualColorMode(_tab.index == 1);
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Dialog(
      backgroundColor: const Color(0xFF16161F),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Tab bar
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF0E0E18),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: TabBar(
                controller: _tab,
                indicatorColor: const Color(0xFFD060F0),
                labelColor: const Color(0xFFD060F0),
                unselectedLabelColor: const Color(0xFF555577),
                labelStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(text: 'Single Color'),
                  Tab(text: 'Dual Color'),
                ],
              ),
            ),
            SizedBox(
              height: screenHeight * 0.42,
              child: TabBarView(
                controller: _tab,
                children: [
                  // ── Tab 0: single color ──────────────────────────────
                  _SingleColorTab(
                    color: context.watch<PianoState>().noteColor,
                    onChanged: (c) => context.read<PianoState>().setColor(c),
                  ),
                  // ── Tab 1: dual color ────────────────────────────────
                  const _DualColorTab(),
                ],
              ),
            ),
            // Close button
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFD060F0),
                    backgroundColor: const Color(0xFF2A1040),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Done'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Single color tab ──────────────────────────────────────────────────────────

class _SingleColorTab extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onChanged;
  const _SingleColorTab({required this.color, required this.onChanged});

  @override
  State<_SingleColorTab> createState() => _SingleColorTabState();
}

class _SingleColorTabState extends State<_SingleColorTab> {
  late HSVColor _hsv;
  final _hexCtrl = TextEditingController();
  bool _editingHex = false;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.color);
    _hexCtrl.text = _colorToHex(widget.color);
  }

  @override
  void didUpdateWidget(_SingleColorTab old) {
    super.didUpdateWidget(old);
    if (!_editingHex && old.color != widget.color) {
      _hsv = HSVColor.fromColor(widget.color);
      _hexCtrl.text = _colorToHex(widget.color);
    }
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    super.dispose();
  }

  void _emit() => widget.onChanged(_hsv.toColor());

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // SV canvas
          _SvCanvas(
            hue: _hsv.hue,
            saturation: _hsv.saturation,
            value: _hsv.value,
            height: 110,
            onChanged: (s, v) {
              setState(() => _hsv = _hsv.withSaturation(s).withValue(v));
              _hexCtrl.text = _colorToHex(_hsv.toColor());
              _emit();
            },
          ),
          const SizedBox(height: 12),
          // Hue slider
          _Label('Hue'),
          _HueSlider(
            hue: _hsv.hue,
            onChanged: (h) {
              setState(() => _hsv = _hsv.withHue(h));
              _hexCtrl.text = _colorToHex(_hsv.toColor());
              _emit();
            },
          ),
          const SizedBox(height: 10),
          // Preview + hex
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _hsv.toColor(),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF44446A)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _hexCtrl,
                  style: const TextStyle(
                      color: Color(0xFFDDDDFF),
                      fontSize: 13,
                      fontFamily: 'monospace'),
                  decoration: InputDecoration(
                    prefixText: '#',
                    prefixStyle:
                    const TextStyle(color: Color(0xFF888899)),
                    filled: true,
                    fillColor: const Color(0xFF0A0A0F),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: Color(0xFF33334A))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: Color(0xFF33334A))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: Color(0xFFD060F0))),
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                        RegExp(r'[0-9a-fA-F]')),
                    LengthLimitingTextInputFormatter(6),
                  ],
                  onTap: () => setState(() => _editingHex = true),
                  onChanged: (val) {
                    if (val.length == 6) {
                      try {
                        final color =
                        Color(int.parse('FF$val', radix: 16));
                        setState(() {
                          _hsv = HSVColor.fromColor(color);
                        });
                        _emit();
                      } catch (_) {}
                    }
                  },
                  onEditingComplete: () {
                    setState(() => _editingHex = false);
                    _hexCtrl.text = _colorToHex(_hsv.toColor());
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Preset swatches
          _Label('Presets'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _kPresets
                .map((c) => GestureDetector(
              onTap: () {
                setState(() {
                  _hsv = HSVColor.fromColor(c);
                  _hexCtrl.text = _colorToHex(c);
                });
                _emit();
              },
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _hsv.toColor().value == c.value
                        ? Colors.white
                        : Colors.transparent,
                    width: 2,
                  ),
                ),
              ),
            ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

// ── Dual color tab ────────────────────────────────────────────────────────────

class _DualColorTab extends StatelessWidget {
  const _DualColorTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<PianoState>(builder: (_, state, __) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Left color picker
            _Label('Left hand color'),
            const SizedBox(height: 6),
            _InlineColorPicker(
              color: state.leftColor,
              onChanged: state.setLeftColor,
            ),
            const SizedBox(height: 14),
            // Right color picker
            _Label('Right hand color'),
            const SizedBox(height: 6),
            _InlineColorPicker(
              color: state.rightColor,
              onChanged: state.setRightColor,
            ),
            const SizedBox(height: 16),
            // Gradient preview
            _Label('Color gradient preview'),
            const SizedBox(height: 6),
            _GradientBar(
              leftColor: state.leftColor,
              rightColor: state.rightColor,
              splitMidi: state.splitMidi,
            ),
            const SizedBox(height: 14),
            // Split point slider
            _Label('Split point  —  ${_midiName(state.splitMidi)}'),
            const SizedBox(height: 4),
            _KeyboardSplitSlider(
              splitMidi: state.splitMidi,
              leftColor: state.leftColor,
              rightColor: state.rightColor,
              onChanged: state.setSplitMidi,
            ),
          ],
        ),
      );
    });
  }
}

// ── Inline compact color picker (used inside dual tab) ────────────────────────

class _InlineColorPicker extends StatefulWidget {
  final Color color;
  final ValueChanged<Color> onChanged;
  const _InlineColorPicker(
      {required this.color, required this.onChanged});

  @override
  State<_InlineColorPicker> createState() => _InlineColorPickerState();
}

class _InlineColorPickerState extends State<_InlineColorPicker> {
  late HSVColor _hsv;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(widget.color);
  }

  @override
  void didUpdateWidget(_InlineColorPicker old) {
    super.didUpdateWidget(old);
    if (old.color != widget.color) {
      _hsv = HSVColor.fromColor(widget.color);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SvCanvas(
          hue: _hsv.hue,
          saturation: _hsv.saturation,
          value: _hsv.value,
          height: 80,
          onChanged: (s, v) {
            setState(() => _hsv = _hsv.withSaturation(s).withValue(v));
            widget.onChanged(_hsv.toColor());
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _hsv.toColor(),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF44446A)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _HueSlider(
                hue: _hsv.hue,
                onChanged: (h) {
                  setState(() => _hsv = _hsv.withHue(h));
                  widget.onChanged(_hsv.toColor());
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Preset row
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _kPresets
              .map((c) => GestureDetector(
            onTap: () {
              setState(() => _hsv = HSVColor.fromColor(c));
              widget.onChanged(c);
            },
            child: Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: _hsv.toColor().value == c.value
                      ? Colors.white
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
          ))
              .toList(),
        ),
      ],
    );
  }
}

// ── Gradient bar ──────────────────────────────────────────────────────────────

class _GradientBar extends StatelessWidget {
  final Color leftColor;
  final Color rightColor;
  final int splitMidi;
  const _GradientBar(
      {required this.leftColor,
        required this.rightColor,
        required this.splitMidi});

  @override
  Widget build(BuildContext context) {
    final splitFrac =
    ((splitMidi - 21) / (108 - 21)).clamp(0.0, 1.0);
    return LayoutBuilder(builder: (ctx, box) {
      return Container(
        height: 28,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          gradient: LinearGradient(colors: [leftColor, rightColor]),
          border: Border.all(color: const Color(0xFF33334A)),
        ),
        child: Stack(
          children: [
            Positioned(
              left: splitFrac * box.maxWidth - 1,
              top: 0,
              bottom: 0,
              child: Container(
                  width: 2,
                  color: Colors.white.withOpacity(0.8)),
            ),
          ],
        ),
      );
    });
  }
}

// ── Keyboard split slider ─────────────────────────────────────────────────────

class _KeyboardSplitSlider extends StatelessWidget {
  final int splitMidi;
  final Color leftColor;
  final Color rightColor;
  final ValueChanged<int> onChanged;

  const _KeyboardSplitSlider({
    required this.splitMidi,
    required this.leftColor,
    required this.rightColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _KeyboardVisualizer(
            splitMidi: splitMidi,
            leftColor: leftColor,
            rightColor: rightColor),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 4,
            thumbShape:
            const RoundSliderThumbShape(enabledThumbRadius: 8),
            overlayShape:
            const RoundSliderOverlayShape(overlayRadius: 16),
            activeTrackColor: leftColor,
            inactiveTrackColor: rightColor,
            thumbColor: Colors.white,
            overlayColor: Colors.white24,
          ),
          child: Slider(
            min: 21,
            max: 108,
            divisions: 87,
            value: splitMidi.toDouble(),
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('A0', style: _labelStyle),
            Text('C8', style: _labelStyle),
          ],
        ),
      ],
    );
  }

  static const _labelStyle =
  TextStyle(color: Color(0xFF555577), fontSize: 10);
}

// ── Mini keyboard visualizer ──────────────────────────────────────────────────

class _KeyboardVisualizer extends StatelessWidget {
  final int splitMidi;
  final Color leftColor;
  final Color rightColor;

  const _KeyboardVisualizer({
    required this.splitMidi,
    required this.leftColor,
    required this.rightColor,
  });

  static const _blackSemitones = {1, 3, 6, 8, 10};

  @override
  Widget build(BuildContext context) {
    const int kMin = 21;
    const int kMax = 108;
    final whites = [
      for (int m = kMin; m <= kMax; m++)
        if (!_blackSemitones.contains(m % 12)) m
    ];
    final totalWhites = whites.length;

    return SizedBox(
      height: 44,
      child: LayoutBuilder(builder: (ctx, box) {
        final ww = box.maxWidth / totalWhites;
        final bw = ww * 0.6;

        return Stack(children: [
          // White keys
          ...whites.asMap().entries.map((e) {
            final i    = e.key;
            final midi = e.value;
            final t    = (midi - kMin) / (kMax - kMin);
            final splitT =
            ((splitMidi - kMin) / (kMax - kMin)).clamp(0.0, 1.0);
            final norm = splitT == 0
                ? t
                : splitT == 1
                ? t
                : t < splitT
                ? (t / splitT) * 0.5
                : 0.5 + ((t - splitT) / (1.0 - splitT)) * 0.5;
            final color = Color.lerp(leftColor, rightColor, norm)!;

            return Positioned(
              left: i * ww,
              top: 0,
              bottom: 0,
              width: ww - 1,
              child: Container(
                decoration: BoxDecoration(
                  color: color.withOpacity(0.35),
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(3)),
                  border: Border.all(
                    color: midi == splitMidi
                        ? Colors.white.withOpacity(0.8)
                        : const Color(0xFF333344),
                    width: midi == splitMidi ? 2 : 0.5,
                  ),
                ),
              ),
            );
          }),

          // Black keys
          ...List.generate(kMax - kMin + 1, (i) => kMin + i)
              .where((m) => _blackSemitones.contains(m % 12))
              .map((midi) {
            int wi = whites.indexOf(midi - 1);
            if (wi < 0) return const SizedBox.shrink();
            final x = (wi + 1) * ww - bw / 2;
            final t = (midi - kMin) / (kMax - kMin);
            final splitT =
            ((splitMidi - kMin) / (kMax - kMin)).clamp(0.0, 1.0);
            final norm = splitT == 0
                ? t
                : splitT == 1
                ? t
                : t < splitT
                ? (t / splitT) * 0.5
                : 0.5 + ((t - splitT) / (1.0 - splitT)) * 0.5;
            final color = Color.lerp(leftColor, rightColor, norm)!;

            return Positioned(
              left: x,
              top: 0,
              height: 28,
              width: bw - 1,
              child: Container(
                decoration: BoxDecoration(
                  color: color.withOpacity(0.6),
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(2)),
                  border: Border.all(
                      color: const Color(0xFF111122), width: 0.5),
                ),
              ),
            );
          }),
        ]);
      }),
    );
  }
}

// ── HSV saturation/value canvas ───────────────────────────────────────────────

class _SvCanvas extends StatefulWidget {
  final double hue;
  final double saturation;
  final double value;
  final double height;
  final void Function(double s, double v) onChanged;

  const _SvCanvas({
    required this.hue,
    required this.saturation,
    required this.value,
    required this.onChanged,
    this.height = 110,
  });

  @override
  State<_SvCanvas> createState() => _SvCanvasState();
}

class _SvCanvasState extends State<_SvCanvas> {
  void _handle(Offset local, BoxConstraints box) {
    final s = (local.dx / box.maxWidth).clamp(0.0, 1.0);
    final v = (1.0 - local.dy / box.maxHeight).clamp(0.0, 1.0);
    widget.onChanged(s, v);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, box) {
      return GestureDetector(
        onPanStart:  (d) => _handle(d.localPosition, box),
        onPanUpdate: (d) => _handle(d.localPosition, box),
        onTapDown:   (d) => _handle(d.localPosition, box),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: widget.height,
            child: CustomPaint(
              painter: _SvPainter(
                hue: widget.hue,
                saturation: widget.saturation,
                value: widget.value,
              ),
              size: Size.infinite,
            ),
          ),
        ),
      );
    });
  }
}

class _SvPainter extends CustomPainter {
  final double hue, saturation, value;
  const _SvPainter(
      {required this.hue,
        required this.saturation,
        required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final baseColor = HSVColor.fromAHSV(1, hue, 1, 1).toColor();

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = LinearGradient(colors: [Colors.white, baseColor])
            .createShader(
            Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end:   Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(
            Rect.fromLTWH(0, 0, size.width, size.height)),
    );

    final tx = saturation * size.width;
    final ty = (1 - value) * size.height;
    canvas.drawCircle(Offset(tx, ty), 8,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    canvas.drawCircle(Offset(tx, ty), 6,
        Paint()
          ..color =
          HSVColor.fromAHSV(1, hue, saturation, value).toColor());
  }

  @override
  bool shouldRepaint(covariant _SvPainter old) =>
      old.hue != hue ||
          old.saturation != saturation ||
          old.value != value;
}

// ── Hue slider ────────────────────────────────────────────────────────────────

class _HueSlider extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;
  const _HueSlider({required this.hue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (d) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final x = d.localPosition.dx.clamp(0.0, box.size.width);
        onChanged((x / box.size.width * 360).clamp(0.0, 360.0));
      },
      onTapDown: (d) {
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final x = d.localPosition.dx.clamp(0.0, box.size.width);
        onChanged((x / box.size.width * 360).clamp(0.0, 360.0));
      },
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: SizedBox(
          height: 16,
          child: CustomPaint(
            painter: _HuePainter(hue: hue),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _HuePainter extends CustomPainter {
  final double hue;
  const _HuePainter({required this.hue});

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()
        ..shader = LinearGradient(colors: [
          for (int i = 0; i <= 6; i++)
            HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor(),
        ]).createShader(
            Rect.fromLTWH(0, 0, size.width, size.height)),
    );
    final tx = hue / 360 * size.width;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
            center: Offset(tx, size.height / 2),
            width: 4,
            height: size.height),
        const Radius.circular(2),
      ),
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _HuePainter old) => old.hue != hue;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Widget _Label(String text) => Text(
  text,
  style: const TextStyle(
      color: Color(0xFF888899),
      fontSize: 11,
      fontWeight: FontWeight.w600),
);

String _colorToHex(Color c) =>
    c.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();

String _midiName(int midi) {
  const names = [
    'C', 'Db', 'D', 'Eb', 'E', 'F', 'Gb', 'G', 'Ab', 'A', 'Bb', 'B'
  ];
  return '${names[midi % 12]}${(midi ~/ 12) - 1}';
}

const _kPresets = [
  Color(0xFFD060F0), Color(0xFF4060FF), Color(0xFFFF4060),
  Color(0xFF00D4FF), Color(0xFFFF8C00), Color(0xFF00E676),
  Color(0xFFFF1744), Color(0xFF00BCD4), Color(0xFFFFEB3B),
  Color(0xFF7C4DFF), Color(0xFFFF6D00), Color(0xFF1DE9B6),
  Color(0xFFFF4081), Color(0xFF69F0AE), Color(0xFF40C4FF),
  Color(0xFFFFD740),
];