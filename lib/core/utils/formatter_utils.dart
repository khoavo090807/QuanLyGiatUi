import 'package:intl/intl.dart';

class FormatterUtils {
  FormatterUtils._();

  /// Normalize numeric order codes to the display format DH + 8 digits.
  /// Non-order codes (such as booking codes) are returned unchanged.
  static String formatOrderCode(String code) {
    final match = RegExp(r'^DH(\d+)$', caseSensitive: false).firstMatch(code);
    if (match == null) return code;

    return 'DH${match.group(1)!.padLeft(8, '0')}';
  }

  /// Normalize order codes embedded in server-generated notification text.
  static String formatOrderCodesInText(String text) => text.replaceAllMapped(
    RegExp(r'\bDH\d+\b', caseSensitive: false),
    (match) => formatOrderCode(match.group(0)!),
  );

  /// Build the canonical display code when only the numeric order ID is known.
  static String formatOrderId(int orderId) =>
      'DH${orderId.toString().padLeft(8, '0')}';

  /// Format money (e.g., 100000 -> "100.000 đ")
  static String formatCurrency(double amount) {
    return formatVnd(amount);
  }

  /// Format whole Vietnamese đồng with dot group separators (e.g. 100000 -> 100.000 đ).
  static String formatVnd(num amount) {
    final formatter = NumberFormat('#,##0', 'vi_VN');
    return '${formatter.format(amount.round())} đ';
  }

  /// Format date (e.g., DateTime -> "19/09/2026")
  static String formatDate(DateTime date) {
    final formatter = DateFormat('dd/MM/yyyy');
    return formatter.format(date);
  }

  /// Format time (e.g., DateTime -> "14:30")
  static String formatTime(DateTime date) {
    final formatter = DateFormat('HH:mm');
    return formatter.format(date);
  }

  /// Format date and time (e.g., DateTime -> "14:30 - 19/09/2026")
  static String formatDateTime(DateTime date) {
    final formatter = DateFormat('HH:mm - dd/MM/yyyy');
    return formatter.format(date);
  }

  /// Obscure phone number (e.g., "0901234567" -> "090****567")
  static String obscurePhone(String phone) {
    if (phone.length < 10) return phone;
    return '${phone.substring(0, 3)}****${phone.substring(phone.length - 3)}';
  }
}
