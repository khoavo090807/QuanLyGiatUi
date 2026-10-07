import 'package:intl/intl.dart';

class FormatterUtils {
  FormatterUtils._();

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
