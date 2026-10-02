import 'prayer.dart';

class PrayerRecord {
  final int? id;
  final DateTime date;
  final PrayerName prayerName;
  final PrayerStatus status;
  final DateTime? prayedAt;

  PrayerRecord({
    this.id,
    required this.date,
    required this.prayerName,
    required this.status,
    this.prayedAt,
  });

  Map<String, dynamic> toMap() { //dynamic for different Data type
    return {
      'id': id,
      'date': date.toIso8601String().substring(0, 10), //store Date with time and only date needed so .substring() 10 char
      'prayer_name': prayerName.index,
      'status': status.index,
      'prayed_at': prayedAt?.toIso8601String(),
    };
  }

  factory PrayerRecord.fromMap(Map<String, dynamic> map) { //creating object from sql Database from map
    return PrayerRecord(
      id: map['id'],
      date: DateTime.parse(map['date']),
      prayerName: PrayerName.values[map['prayer_name']],
      status: PrayerStatus.values[map['status']],
      prayedAt: map['prayed_at'] != null ? DateTime.parse(map['prayed_at']) : null,
    );
  }

  PrayerRecord copyWith({PrayerStatus? status, DateTime? prayedAt}) {
    return PrayerRecord(
      id: id,
      date: date,
      prayerName: prayerName,
      status: status ?? this.status,
      prayedAt: prayedAt ?? this.prayedAt,
    );
  }
}
