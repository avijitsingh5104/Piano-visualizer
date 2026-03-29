import 'dart:async';
import 'package:flutter_midi_command/flutter_midi_command.dart';
import '../models/piano_state.dart';
import 'recording_service.dart';

class MidiService {
  final PianoState       _state;
  final RecordingService _recording;
  final _midi = MidiCommand();
  StreamSubscription? _dataSub;
  Timer?              _pollTimer;

  MidiService(this._state, this._recording);

  Future<void> init() async {
    _dataSub = _midi.onMidiDataReceived?.listen((packet) {
      final data = packet.data;
      if (data.length < 3) return;

      final status = data[0] & 0xF0;
      final note   = data[1];
      final vel    = data[2];

      if (status == 0x90 && vel > 0) {
        _state.pressNote(note);          // plays sound via PianoState
        _recording.recordNoteOn(note, vel);
      } else if (status == 0x80 || (status == 0x90 && vel == 0)) {
        _state.releaseNote(note);        // stops sound via PianoState
        _recording.recordNoteOff(note);
      }
    });

    _pollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _refreshDevices();
    });

    await _refreshDevices();
  }

  Future<void> _refreshDevices() async {
    final devices = await _midi.devices ?? [];
    _state.updateDevices(devices);
  }

  Future<void> connectDevice(MidiDevice device) async {
    try {
      await _midi.connectToDevice(device);
      await _refreshDevices();
    } catch (e) {
      print('Connect error: $e');
    }
  }

  Future<void> disconnectDevice(MidiDevice device) async {
    try {
      _midi.disconnectDevice(device);
      await _refreshDevices();
    } catch (e) {
      print('Disconnect error: $e');
    }
  }

  Future<void> refreshNow() async => _refreshDevices();

  void dispose() {
    _pollTimer?.cancel();
    _dataSub?.cancel();
    _state.releaseAll();
  }
}