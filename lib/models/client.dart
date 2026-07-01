class Client {
  String id;
  String companyName;
  String contactPerson;
  String phone;
  String email;
  String address;
  String gstin;
  /// When this client was created — used for "newest first" sorting in
  /// both the Clients list screen and the client picker dropdown.
  /// Defaults to epoch for any client that existed before this field was
  /// added, so they sort to the bottom (oldest) without breaking anything.
  DateTime createdAt;

  Client({
    required this.id,
    this.companyName = '',
    this.contactPerson = '',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.gstin = '',
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
        'id': id,
        'companyName': companyName,
        'contactPerson': contactPerson,
        'phone': phone,
        'email': email,
        'address': address,
        'gstin': gstin,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Client.fromMap(Map<dynamic, dynamic> m) => Client(
        id: m['id'],
        companyName: m['companyName'] ?? '',
        contactPerson: m['contactPerson'] ?? '',
        phone: m['phone'] ?? '',
        email: m['email'] ?? '',
        address: m['address'] ?? '',
        gstin: m['gstin'] ?? '',
        // Clients saved before this field existed get epoch (earliest
        // possible time), so they sort reliably to the bottom of "newest
        // first" lists without crashing on the missing key.
        createdAt: m['createdAt'] != null
            ? DateTime.tryParse(m['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0)
            : DateTime.fromMillisecondsSinceEpoch(0),
      );
}
