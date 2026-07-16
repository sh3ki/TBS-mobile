class PreRecord {
  final int pId;
  final String gateStatus;
  final String containerNo;
  final String plateNo;
  final String hauler;
  final String clientName;
  final int? clientId;
  final int? runtime;
  final String dateAdded;

  const PreRecord({
    required this.pId,
    required this.gateStatus,
    required this.containerNo,
    required this.plateNo,
    required this.hauler,
    required this.clientName,
    required this.clientId,
    required this.runtime,
    required this.dateAdded,
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
      runtime: (json['runtime'] as num?)?.toInt(),
      dateAdded: (json['date_added'] ?? '').toString(),
    );
  }
}
