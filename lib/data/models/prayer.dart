//putting the options, and convert the prayer name to string and logics of enum
enum PrayerStatus { onTime, qaza, missed, upcoming, prayed, pending } //enum -> option point

enum PrayerName { fajr, dhuhr, asr, maghrib, isha }

extension PrayerNameExtension on PrayerName { //declared in the package
  String get displayName {
    switch (this) {
      case PrayerName.fajr:
        return 'Fajr';
      case PrayerName.dhuhr:
        return 'Dhuhr';
      case PrayerName.asr:
        return 'Asr';
      case PrayerName.maghrib:
        return 'Maghrib';
      case PrayerName.isha:
        return 'Isha';
    }
  }

  String get arabicName {
    switch (this) {
      case PrayerName.fajr:
        return 'الفجر';
      case PrayerName.dhuhr:
        return 'الظهر';
      case PrayerName.asr:
        return 'العصر';
      case PrayerName.maghrib:
        return 'المغرب';
      case PrayerName.isha:
        return 'العشاء';
    }
  }

  /// Returns 'Jumah' on Fridays for male users (Dhuhr-> Jumah), else displayName.
  String localizedName(String gender, DateTime date) {
    if (this == PrayerName.dhuhr &&
        gender == 'Male' &&
        date.weekday == DateTime.friday) {
      return 'Jumah';
    }
    return displayName;
  }
}

class Prayer {
  final PrayerName name;
  final DateTime time;
  final PrayerStatus status;

  Prayer({
    required this.name,
    required this.time,
    this.status = PrayerStatus.upcoming,
  });

  bool get isPrayed => status == PrayerStatus.onTime || status == PrayerStatus.qaza || status == PrayerStatus.prayed;

  /// Once a final status is set, it cannot be changed
  bool get isLocked =>
      status == PrayerStatus.onTime ||
      status == PrayerStatus.qaza ||
      status == PrayerStatus.missed;

  String get statusLabel {
    switch (status) {
      case PrayerStatus.onTime:
        return 'On Time';
      case PrayerStatus.qaza:
        return 'Qaza';
      case PrayerStatus.missed:
        return 'Missed';
      case PrayerStatus.upcoming:
        return 'Upcoming';
      case PrayerStatus.prayed:
        return 'Prayed';
      case PrayerStatus.pending:
        return 'Pending';
    }
  }

  Prayer copyWith({PrayerStatus? status}) {
    return Prayer(
      name: name,
      time: time,
      status: status ?? this.status,
    );
  }
}
