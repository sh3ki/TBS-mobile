class PreRecord {
  final int pId;
  final String gateStatus;
  final String containerNo;
  final String plateNo;
  final String hauler;
  final String clientName;
  final int? clientId;
  final int? sizeTypeId;
  final String sizeTypeDisplay;
  final String isoCode;
  final int? runtime;
  final String dateAdded;
  final String dateCompleted;

  const PreRecord({
    required this.pId,
    required this.gateStatus,
    required this.containerNo,
    required this.plateNo,
    required this.hauler,
    required this.clientName,
    required this.clientId,
    required this.sizeTypeId,
    required this.sizeTypeDisplay,
    required this.isoCode,
    required this.runtime,
    required this.dateAdded,
    required this.dateCompleted,
  });

  factory PreRecord.fromJson(Map<String, dynamic> json) {
    return PreRecord(
      pId: (json['p_id'] as num?)?.toInt() ?? 0,
      gateStatus: (json['gate_status'] ?? '').toString(),
      containerNo: (json['container_no'] ?? '').toString(),
      plateNo: (json['plate_no'] ?? '').toString(),
      hauler: (json['hauler'] ?? '').toString(),
      clientName: (json['client_name'] ?? '-').toString(),
      clientId: (json['client_id'] as num?)?.toInt(),
      sizeTypeId: (json['sizetype_id'] as num?)?.toInt(),
      sizeTypeDisplay: (json['size_type_display'] ?? '').toString(),
      isoCode: (json['iso_code'] ?? '').toString(),
      runtime: (json['runtime'] as num?)?.toInt(),
      dateAdded: (json['date_added'] ?? '').toString(),
      dateCompleted: (json['date_completed'] ?? '').toString(),
    );
  }
}
