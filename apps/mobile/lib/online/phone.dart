/// Turns what a Ugandan player types into E.164 (+256 and 9 digits), or
/// null when it is not a Ugandan mobile number. Accepts 0772 123456,
/// 772123456, 256772123456 and +256 772 123 456.
String? normalizeUgandanPhone(String input) {
  var digits = input.replaceAll(RegExp(r'[\s\-()]'), '');
  if (digits.startsWith('+')) digits = digits.substring(1);
  if (!RegExp(r'^\d+$').hasMatch(digits)) return null;
  if (digits.startsWith('256')) {
    digits = digits.substring(3);
  } else if (digits.startsWith('0')) {
    digits = digits.substring(1);
  }
  if (digits.length != 9 || !digits.startsWith('7')) return null;
  return '+256$digits';
}
