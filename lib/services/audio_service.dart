import 'package:audioplayers/audioplayers.dart';

class AudioService {
  final Map<int, AudioPlayer> _players = {};

  final names = [
    'C','Db','D','Eb','E','F','Gb','G','Ab','A','Bb','B'
  ];

  String _noteToFile(int midi) {
    final note = names[midi % 12];
    final octave = (midi ~/ 12) - 1;
    return 'sounds/$note$octave.mp3';
  }

  Future<void> init() async {
    // 🔥 PRELOAD players
    for (int midi = 21; midi <= 108; midi++) {
      final player = AudioPlayer();
      await player.setSource(AssetSource(_noteToFile(midi)));
      player.setReleaseMode(ReleaseMode.stop);
      _players[midi] = player;
    }
  }

  void playNote(int midi) {
    final player = _players[midi];
    if (player == null) return;

    player.seek(Duration.zero);
    player.resume();            
  }

  void stopNote(int midi) {
    _players[midi]?.stop();
  }

  void dispose() {
    for (final p in _players.values) {
      p.dispose();
    }
  }
}