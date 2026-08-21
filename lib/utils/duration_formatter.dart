String formatRuntimeMinutes(int? minutes) {
  final mins = minutes ?? 0;
  if (mins <= 0) return '0m';

  const int minutesPerDay = 1440;
  const int minutesPerHour = 60;

  final days = mins ~/ minutesPerDay;
  final remainderAfterDays = mins % minutesPerDay;
  final hours = remainderAfterDays ~/ minutesPerHour;
  final remainingMinutes = remainderAfterDays % minutesPerHour;

  final parts = <String>[];
  if (days > 0) parts.add('${days}d');
  if (hours > 0) parts.add('${hours}h');
  parts.add('${remainingMinutes}m');

  return parts.join(' ');
}
