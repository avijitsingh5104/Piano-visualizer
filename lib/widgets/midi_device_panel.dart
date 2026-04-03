import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/piano_state.dart';
import '../services/midi_service.dart';
import 'dart:io';

class MidiDeviceButton extends StatefulWidget {
  const MidiDeviceButton({super.key});
  @override
  State<MidiDeviceButton> createState() => _MidiDevicePanelState();
}

class _MidiDevicePanelState extends State<MidiDeviceButton> {
  bool _open = false;
  bool _scanning = true;

  @override
  void initState() {
    super.initState();
    // Show scanning for 2 seconds on startup then let real state take over
    Future.delayed(const Duration(seconds: 18), () {
      if (mounted) setState(() => _scanning = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<PianoState>(
      builder: (context, state, _) {
        final connected = state.devices.where((d) => d.connected).length;
        final hasDevices = state.devices.isNotEmpty;

        return Stack(
          children: [
            // ── Floating button ───────────────────────────────────
            Positioned(
              top: Platform.isAndroid? 76:60,
              left: 16,
              child: GestureDetector(
                onTap: () => setState(() => _open = !_open),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: connected > 0
                        ? const Color(0xFF2A1040)
                        : const Color(0xFF1A1A28),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: connected > 0
                          ? const Color(0xFFD060F0)
                          : const Color(0xFF44446A),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.piano,
                        size: 16,
                        color: connected > 0
                            ? const Color(0xFFD060F0)
                            : const Color(0xFF6060A0),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _scanning && !hasDevices
                            ? 'Scanning…'
                            : connected > 0
                            ? '$connected connected'
                            : hasDevices
                            ? '${state.devices.length} device${state.devices.length > 1 ? 's' : ''} found'
                            : 'No MIDI devices',
                        style: TextStyle(
                          fontSize: 12,
                          color: connected > 0
                              ? const Color(0xFFD060F0)
                              : const Color(0xFF6060A0),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _open ? Icons.expand_less : Icons.expand_more,
                        size: 14,
                        color: const Color(0xFF6060A0),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Device panel ──────────────────────────────────────
            if (_open)
              Positioned(
                top: 96,
                left: 16,
                child: Container(
                  width: 280,
                  decoration: BoxDecoration(
                    color: const Color(0xFF16161F),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF33334A),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
                        child: Row(
                          children: [
                            const Text(
                              'MIDI Devices',
                              style: TextStyle(
                                color: Color(0xFFAAAAAA),
                                fontSize: 11,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const Spacer(),
                            // Manual refresh button
                            GestureDetector(
                              onTap: () async {
                                final midi = context.read<MidiService>();
                                await midi.refreshNow();
                              },
                              child: const Icon(
                                Icons.refresh,
                                size: 16,
                                color: Color(0xFF6060A0),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const Divider(color: Color(0xFF22223A), height: 1),

                      // Device list
                      if (state.devices.isEmpty)
                        Padding(
                          padding: EdgeInsets.all(16),
                          child: Text(
                            _scanning
                                ? 'Scanning for MIDI devices…'
                                : 'No MIDI devices detected.\nPlug in your keyboard and wait\na moment, or tap ↻ to scan.',
                            style: TextStyle(
                              color: _scanning ? const Color(0xFF8888AA) : const Color(0xFF555577),
                              fontSize: 12,
                              height: 1.5,
                            ),
                          ),
                        )
                      else
                        ...state.devices.map((device) => _DeviceRow(
                          device: device,
                          onConnect: () async {
                            final midi = context.read<MidiService>();
                            await midi.connectDevice(device);
                          },
                          onDisconnect: () async {
                            final midi = context.read<MidiService>();
                            await midi.disconnectDevice(device);
                          },
                        )),

                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DeviceRow extends StatelessWidget {
  final dynamic device;
  final VoidCallback onConnect;
  final VoidCallback onDisconnect;

  const _DeviceRow({
    required this.device,
    required this.onConnect,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    final connected = device.connected as bool;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // Status dot
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: connected
                  ? const Color(0xFF50E090)
                  : const Color(0xFF444466),
            ),
          ),
          const SizedBox(width: 10),
          // Device name
          Expanded(
            child: Text(
              device.name as String,
              style: TextStyle(
                color: connected
                    ? const Color(0xFFDDDDFF)
                    : const Color(0xFF888899),
                fontSize: 13,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Connect / Disconnect button
          GestureDetector(
            onTap: connected ? onDisconnect : onConnect,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: connected
                    ? const Color(0xFF1A2A1A)
                    : const Color(0xFF2A1040),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: connected
                      ? const Color(0xFF50E090)
                      : const Color(0xFFD060F0),
                  width: 1,
                ),
              ),
              child: Text(
                connected ? 'Disconnect' : 'Connect',
                style: TextStyle(
                  fontSize: 11,
                  color: connected
                      ? const Color(0xFF50E090)
                      : const Color(0xFFD060F0),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}