import 'package:supabase_flutter/supabase_flutter.dart';

class CustomerAddress {
  const CustomerAddress({
    required this.id,
    required this.recipient,
    required this.phone,
    required this.address,
    required this.isDefault,
    this.note,
  });

  final int id;
  final String recipient;
  final String phone;
  final String address;
  final bool isDefault;
  final String? note;

  factory CustomerAddress.fromJson(Map<String, dynamic> json) {
    return CustomerAddress(
      id: (json['diachiid'] as num).toInt(),
      recipient: json['tennguoinhan'] as String,
      phone: json['sodienthoai'] as String,
      address: json['diachi'] as String,
      isDefault: json['macdinh'] as bool,
      note: json['ghichu'] as String?,
    );
  }
}

class AddressRepository {
  AddressRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<CustomerAddress>> getAddresses() async {
    final rows = await _client
        .from('khachhang_diachi')
        .select('diachiid,tennguoinhan,sodienthoai,diachi,ghichu,macdinh')
        .order('macdinh', ascending: false)
        .order('ngaytao', ascending: false);
    return (rows as List<dynamic>)
        .map((row) => CustomerAddress.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<void> saveAddress({
    int? id,
    required String recipient,
    required String phone,
    required String address,
    String? note,
    required bool isDefault,
  }) async {
    await _client.rpc(
      'save_customer_address',
      params: {
        'p_diachiid': id,
        'p_tennguoinhan': recipient,
        'p_sodienthoai': phone,
        'p_diachi': address,
        'p_ghichu': note,
        'p_macdinh': isDefault,
      },
    );
  }

  Future<void> deleteAddress(int id) async {
    await _client.from('khachhang_diachi').delete().eq('diachiid', id);
  }
}