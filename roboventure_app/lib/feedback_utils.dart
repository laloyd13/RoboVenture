import 'package:vibration/vibration.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:sound_mode/sound_mode.dart';
import 'package:sound_mode/utils/ringer_mode_statuses.dart';

class FeedbackUtils {
  // ── Shared audio player (lazy singleton) ─────────────────────────────────
  static final AudioPlayer _player = AudioPlayer();

  // ── Ringer mode detection ─────────────────────────────────────────────────
  // Reads the actual ringer switch state via AudioManager (not media volume).
  // On iOS, sound_mode has experimental support — falls back to normal on error.
  static Future<_RingerMode> _getRingerMode() async {
    try {
      final RingerModeStatus status = await SoundMode.ringerModeStatus;
      switch (status) {
        case RingerModeStatus.normal:
          return _RingerMode.normal;
        case RingerModeStatus.vibrate:
          return _RingerMode.vibrateOnly;
        case RingerModeStatus.silent:
          return _RingerMode.silent;
        default:
          // Unknown — default to normal so feedback is never silently dropped.
          return _RingerMode.normal;
      }
    } catch (_) {
      return _RingerMode.normal;
    }
  }

  // ── Internal vibrate helper ───────────────────────────────────────────────
  static Future<void> _vibrate({
    int duration = 40,
    int amplitude = 40,
    List<int>? pattern,
    List<int>? intensities,
  }) async {
    final bool hasVibrator = await Vibration.hasVibrator();
    if (!hasVibrator) return;

    if (pattern != null) {
      Vibration.vibrate(
        pattern: pattern,
        intensities: intensities ?? [],
      );
    } else {
      Vibration.vibrate(duration: duration, amplitude: amplitude);
    }
  }

  // ── Light tap — counter / score button pressed ───────────────────────────
  /// Short click — vibrates only when NOT on silent mode.
  static Future<void> counterTap() async {
    final mode = await _getRingerMode();
    if (mode == _RingerMode.silent) return;
    await _vibrate(duration: 15, amplitude: 40);
  }

  // ── Medium tap — timer START / PAUSE / RESET ─────────────────────────────
  /// Medium pulse — vibrates only when NOT on silent mode.
  static Future<void> controlTap() async {
    final mode = await _getRingerMode();
    if (mode == _RingerMode.silent) return;
    await _vibrate(duration: 25, amplitude: 40);
  }

  // ── Time's up — countdown reaches 0:00 ───────────────────────────────────
  /// Vibration mirrors the ~8-second audio waveform: 8 short distinct bursts
  /// arranged in two halves (4 bursts each), matching the audio shape.
  ///
  /// Pattern format for vibration package: [delay, ON, OFF, ON, OFF, …]
  ///   • delay = initial wait before first buzz (always 0 here)
  ///   • ON    = vibration duration in ms
  ///   • OFF   = silence/gap between bursts in ms
  ///
  ///   Half 1 — 4 bursts:  buzz(60) gap(120) × 3, buzz(60)
  ///   Mid pause           : 350 ms  (matches the visible gap in the waveform)
  ///   Half 2 — 4 bursts:  same as half 1
  ///
  /// Total: 8 distinct vibration pulses across ~8 seconds.
  static Future<void> timesUp() async {
    final _RingerMode mode = await _getRingerMode();

    // 1. Vibration — normal or vibrate-only; suppressed on silent.
    if (mode != _RingerMode.silent) {
      const List<int> pattern = [
        0,   60, 120,  // half 1 — burst 1
             60, 120,  // half 1 — burst 2
             60, 120,  // half 1 — burst 3
             60, 350,  // half 1 — burst 4 + mid-point pause
             60, 120,  // half 2 — burst 1
             60, 120,  // half 2 — burst 2
             60, 120,  // half 2 — burst 3
             60,       // half 2 — burst 4
      ];

      final List<int> intensities = List.filled(pattern.length, 40);
      await _vibrate(pattern: pattern, intensities: intensities);
    }

    // 2. Sound — only in normal (ring) mode.
    if (mode != _RingerMode.normal) return;

    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/timesup.mp3'));
    } catch (_) {
      // Audio failure must never crash the app.
    }
  }
}

// ── Ringer mode enum ──────────────────────────────────────────────────────────
enum _RingerMode { normal, vibrateOnly, silent }