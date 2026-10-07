import 'prayer.dart'; //package imported

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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'date': date.toIso8601String().substring(0, 10), //convert date ansd time like 10-12-2026;14:16:56
      'prayer_name': prayerName.index,
      'status': status.index,
      'prayed_at': prayedAt?.toIso8601String(),
    };
  }

  factory PrayerRecord.fromMap(Map<String, dynamic> map) { //the actuall object to sotre data or string
    return PrayerRecord(
      id: map['id'],
      date: DateTime.parse(map['date']),
      prayerName: PrayerName.values[map['prayer_name']],
      status: PrayerStatus.values[map['status']],
      prayedAt: map['prayed_at'] != null ? DateTime.parse(map['prayed_at']) : null,
    );
  }

  PrayerRecord copyWith({PrayerStatus? status, DateTime? prayedAt}) {//the qaza prayer record will store or change here only by copy
    return PrayerRecord(
      id: id,
      date: date,
      prayerName: prayerName,
      status: status ?? this.status,
      prayedAt: prayedAt ?? this.prayedAt,
    );
  }
}
