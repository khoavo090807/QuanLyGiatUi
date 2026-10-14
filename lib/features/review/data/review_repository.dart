import 'package:supabase_flutter/supabase_flutter.dart';

enum ServiceReviewFilter { all, singleService, mixedOrder }

class ServiceReview {
  const ServiceReview({
    required this.reviewId,
    required this.serviceId,
    required this.serviceName,
    required this.rating,
    required this.reviewedAt,
    required this.serviceCount,
    required this.serviceNames,
    this.orderCode,
    this.customerName,
    this.comment,
    this.shopResponse,
  });

  final int reviewId;
  final int serviceId;
  final String serviceName;
  final int rating;
  final DateTime reviewedAt;
  final int serviceCount;
  final List<String> serviceNames;
  final String? orderCode;
  final String? customerName;
  final String? comment;
  final String? shopResponse;

  bool get isMixedOrder => serviceCount > 1;

  factory ServiceReview.fromJson(Map<String, dynamic> json) {
    final serviceNames = json['service_names'];
    return ServiceReview(
      reviewId: (json['review_id'] as num).toInt(),
      serviceId: (json['service_id'] as num).toInt(),
      serviceName: json['service_name'] as String,
      rating: (json['rating'] as num).toInt(),
      reviewedAt: DateTime.parse(json['reviewed_at'] as String),
      serviceCount: (json['service_count'] as num).toInt(),
      serviceNames: serviceNames is List
          ? serviceNames.map((name) => name.toString()).toList(growable: false)
          : const [],
      orderCode: json['order_code'] as String?,
      customerName: json['customer_name'] as String?,
      comment: json['comment'] as String?,
      shopResponse: json['shop_response'] as String?,
    );
  }
}

class ReviewRepository {
  ReviewRepository({SupabaseClient? client})
    : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  Future<List<ServiceReview>> getServiceReviews(
    int serviceId, {
    required ServiceReviewFilter filter,
    int offset = 0,
    int pageSize = 10,
  }) async {
    final filterValue = switch (filter) {
      ServiceReviewFilter.all => 'all',
      ServiceReviewFilter.singleService => 'single',
      ServiceReviewFilter.mixedOrder => 'mixed',
    };
    final rows = await _client.rpc(
      'get_service_reviews_v2',
      params: {
        'p_service_id': serviceId,
        'p_filter': filterValue,
        'p_offset': offset,
        'p_limit': pageSize,
      },
    );
    return (rows as List<dynamic>)
        .map((row) => ServiceReview.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<Map<String, dynamic>?> getReviewForOrder(int orderId) async {
    return _client
        .from('DanhGia')
        .select('SoSao,BinhLuan')
        .eq('DonHangID', orderId)
        .maybeSingle();
  }

  Future<void> submitReview({
    required int orderId,
    required int rating,
    required String comment,
  }) async {
    await _client.rpc(
      'submit_order_review',
      params: {
        'p_donhangid': orderId,
        'p_sosao': rating,
        'p_binhluan': comment.trim().isEmpty ? null : comment.trim(),
      },
    );
  }
}
