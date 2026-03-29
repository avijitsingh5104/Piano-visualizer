import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'models/piano_state.dart';
import 'services/midi_service.dart';
import 'services/recording_service.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const PianoVizApp());
}

class PianoVizApp extends StatelessWidget {
  const PianoVizApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => PianoState(),
      child: const _AppRoot(),
    );
  }
}

class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  late final MidiService _midi;
  late final RecordingService _recording;

  @override
  void initState() {
    super.initState();

    // Create single instances
    _recording = RecordingService();

    // ⚠️ DO NOT use context.read here for async work
    final state = context.read<PianoState>();
    _midi = MidiService(state, _recording);

    // ✅ Safe initialization AFTER first frame
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final state = context.read<PianoState>();
      await state.initAudio();
      await _midi.init();
    });
  }

  @override
  void dispose() {
    _midi.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider.value(value: _midi),
        ChangeNotifierProvider.value(value: _recording),
      ],
      child: MaterialApp(
        title: 'PianoViz',
        theme: ThemeData.dark(),
        debugShowCheckedModeBanner: false,
        home: const HomeScreen(),
      ),
    );
  }
}