/// Utility helpers for formatting durations, numbers, and strings across Shiei Mobile.
class FormatUtils {
  /// Converts minutes into human-readable hours and minutes.
  /// E.g.:
  /// - 900 -> '15 Jam'
  /// - 955 -> '15 Jam 55 Menit' (or '15 Jam 55 Mnt' if [shortSuffix] is true)
  /// - 125 -> '2 Jam 5 Menit'
  /// - 60  -> '1 Jam'
  /// - 45  -> '45 Menit'
  /// - 0   -> '0 Menit'
  static String formatDurationHoursMinutes(dynamic durationMinutes, {bool shortSuffix = false}) {
    final mins = int.tryParse(durationMinutes?.toString() ?? '') ?? 0;
    final minUnit = shortSuffix ? 'Mnt' : 'Menit';
    if (mins <= 0) return '0 $minUnit';

    final hours = mins ~/ 60;
    final remMins = mins % 60;

    if (hours > 0 && remMins > 0) {
      return '$hours Jam $remMins $minUnit';
    } else if (hours > 0) {
      return '$hours Jam';
    } else {
      return '$remMins $minUnit';
    }
  }
}
