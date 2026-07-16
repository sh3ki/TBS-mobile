class LookupItem {
  final int id;
  final String label;
  final String extra;

  const LookupItem({
    required this.id,
    required this.label,
    this.extra = '',
  });

  factory LookupItem.fromClientJson(Map<String, dynamic> json) {
    final name = (json['client_name'] ?? '').toString();
    final code = (json['client_code'] ?? '').toString();
    return LookupItem(
      id: (json['c_id'] as num?)?.toInt() ?? 0,
      label: code.isNotEmpty && code != '-' ? '$code - $name' : name,
      extra: (json['hashed_c_id'] ?? '').toString(),
    );
  }

  factory LookupItem.fromStatusJson(Map<String, dynamic> json) {
    return LookupItem(
      id: (json['s_id'] as num?)?.toInt() ?? 0,
      label: (json['status'] ?? '').toString(),
    );
  }

  factory LookupItem.fromSizeTypeJson(Map<String, dynamic> json) {
    final size = (json['size'] ?? '').toString();
    final type = (json['type'] ?? '').toString();
    return LookupItem(
      id: (json['s_id'] as num?)?.toInt() ?? 0,
      label: '$size$type',
    );
  }

  factory LookupItem.fromLoadTypeJson(Map<String, dynamic> json) {
    return LookupItem(
      id: (json['l_id'] as num?)?.toInt() ?? 0,
      label: (json['type'] ?? '').toString(),
    );
  }
}
