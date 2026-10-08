import 'package:flutter/widgets.dart' show Locale;
import 'package:geocoding/geocoding.dart';

/// Resolves typed addresses through the device's geocoder and returns
/// standardized street addresses that the customer can explicitly select.
class AddressSuggestionService {
  final Geocoding _geocoding = Geocoding(locale: const Locale('vi', 'VN'));

  Future<List<String>> suggest(String query) async {
    final locations = await _geocoding.locationFromAddress(query);
    final suggestions = <String>{};
    for (final location in locations.take(5)) {
      final placemarks = await _geocoding.placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      for (final placemark in placemarks) {
        final address = _format(placemark);
        if (address.isNotEmpty) suggestions.add(address);
      }
    }
    return suggestions.take(5).toList(growable: false);
  }

  String _format(Placemark placemark) {
    final street = placemark.street?.trim();
    final parts = <String?>[
      if (street != null && street.isNotEmpty) street,
      placemark.subLocality,
      placemark.locality,
      placemark.subAdministrativeArea,
      placemark.administrativeArea,
      placemark.country,
    ].whereType<String>().map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
    final unique = <String>[];
    for (final part in parts) {
      if (!unique.contains(part)) unique.add(part);
    }
    return unique.join(', ');
  }
}
