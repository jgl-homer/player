import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio/just_audio.dart';
import '../providers/audio_provider.dart';
import '../theme/app_theme.dart';

class EqualizerModal extends StatelessWidget {
  const EqualizerModal({super.key});

  @override
  Widget build(BuildContext context) {
    final audioProvider = Provider.of<AudioProvider>(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      height: MediaQuery.of(context).size.height * 0.65,
      decoration: const BoxDecoration(
        color: AppTheme.surfaceColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              height: 5,
              width: 50,
              decoration: BoxDecoration(
                color: Colors.grey[600],
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            "Efectos Acústicos",
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 15),

          // Presets
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _PresetChip(
                label: "Studio",
                isActive: audioProvider.currentPreset == AudioPreset.studio,
                onTap: () => audioProvider.setAudioPreset(AudioPreset.studio),
              ),
              _PresetChip(
                label: "Hall",
                isActive: audioProvider.currentPreset == AudioPreset.hall,
                onTap: () => audioProvider.setAudioPreset(AudioPreset.hall),
              ),
              _PresetChip(
                label: "Room",
                isActive: audioProvider.currentPreset == AudioPreset.room,
                onTap: () => audioProvider.setAudioPreset(AudioPreset.room),
              ),
              _PresetChip(
                label: "Club",
                isActive: audioProvider.currentPreset == AudioPreset.club,
                onTap: () => audioProvider.setAudioPreset(AudioPreset.club),
              ),
            ],
          ),
          const SizedBox(height: 25),

          // Controles de Efectos DSP Independientes
          Wrap(
            spacing: 15,
            runSpacing: -5, // Reduce vertical spacing between switches
            alignment: WrapAlignment.start,
            children: [
              _ControlSwitch("PreAmp (Gain)", audioProvider.isGainEnabled, audioProvider.toggleGain),
              _ControlSwitch("Reverb", audioProvider.isReverbEnabled, audioProvider.toggleReverb),
              _ControlSwitch("Virtualizer", audioProvider.isVirtualizerEnabled, audioProvider.toggleVirtualizer),
              _ControlSwitch("Bass Boost", audioProvider.isBassBoostEnabled, audioProvider.toggleBass),
            ],
          ),
          const SizedBox(height: 10),
          
          // Slider de Ganancia PreAmp
          StatefulBuilder(
            builder: (context, setState) {
              // Retrieve initial target gain if possible or default to 0.0
              // just_audio doesn't provide a getter for targetGain directly. 
              // En app real guardamos el valor en AudioProvider.
              return SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppTheme.primaryColor,
                  inactiveTrackColor: Colors.black45,
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  // We'll use a mocked value or access it from AudioProvider if added.
                  // For now let's refer to audioProvider.currentLoudnessGain.
                  value: audioProvider.currentLoudnessGain.clamp(0.0, 1500.0),
                  min: 0.0,
                  max: 1500.0,
                  onChanged: (value) {
                    audioProvider.setLoudnessGain(value);
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 20),

          // Equalizer Bands
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Ecualizador (Global)",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Switch(
                value: audioProvider.isEqEnabled,
                onChanged: audioProvider.toggleEq,
                activeColor: AppTheme.primaryColor,
              ),
            ],
          ),
          const SizedBox(height: 5),
          Expanded(
            child: FutureBuilder<AndroidEqualizerParameters>(
              future: audioProvider.equalizer.parameters,
              builder: (context, snapshot) {
                final parameters = snapshot.data;
                if (!snapshot.hasData || parameters == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                final bands = parameters.bands;
                final maxDb = parameters.maxDecibels;
                final minDb = parameters.minDecibels;
                
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: bands.map((band) {
                    return Expanded(
                      child: Column(
                        children: [
                          Expanded(
                            child: RotatedBox(
                              quarterTurns: 3,
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  activeTrackColor: Colors.blueAccent,
                                  inactiveTrackColor: Colors.black45,
                                  thumbColor: Colors.white,
                                  trackHeight: 4,
                                ),
                                child: StatefulBuilder(
                                  builder: (context, setState) {
                                    return Slider(
                                      min: minDb,
                                      max: maxDb,
                                      value: band.gain.clamp(minDb, maxDb),
                                      onChanged: (value) async {
                                        await audioProvider.equalizer.setEnabled(true);
                                        await band.setGain(value);
                                        setState(() {});
                                      },
                                    );
                                  }
                                )
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "${(band.centerFrequency / 1000).toStringAsFixed(1)}k",
                            style: const TextStyle(color: Colors.white54, fontSize: 10),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          )
        ],
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _PresetChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? AppTheme.primaryColor : Colors.grey[700]!,
            width: 1.5,
          ),
          boxShadow: isActive ? [
            BoxShadow(
              color: AppTheme.primaryColor.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 2),
            )
          ] : [],
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white70,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

class _ControlSwitch extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ControlSwitch(this.label, this.value, this.onChanged);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppTheme.primaryColor,
        ),
      ],
    );
  }
}
