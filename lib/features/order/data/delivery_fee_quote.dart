class DeliveryFeeQuote {
  const DeliveryFeeQuote({
    required this.quoteId,
    required this.expiresAt,
    required this.pickupDistanceMeters,
    required this.pickupFeeVnd,
    required this.deliveryDistanceMeters,
    required this.deliveryFeeVnd,
  });

  final String quoteId;
  final DateTime expiresAt;
  final int pickupDistanceMeters;
  final int pickupFeeVnd;
  final int deliveryDistanceMeters;
  final int deliveryFeeVnd;

  int get totalFeeVnd => pickupFeeVnd + deliveryFeeVnd;

  factory DeliveryFeeQuote.fromJson(Map<String, dynamic> json) {
    return DeliveryFeeQuote(
      quoteId: json['quoteId'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      pickupDistanceMeters: (json['pickupDistanceMeters'] as num).toInt(),
      pickupFeeVnd: (json['pickupFeeVnd'] as num).toInt(),
      deliveryDistanceMeters: (json['deliveryDistanceMeters'] as num).toInt(),
      deliveryFeeVnd: (json['deliveryFeeVnd'] as num).toInt(),
    );
  }
}
