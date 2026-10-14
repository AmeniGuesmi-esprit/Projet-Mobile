/// TeleDoc input rules, shared by the app (UX hints) and the server
/// (authoritative). Each function returns a French error message, or `null`
/// when the value is valid.
library;

/// Symptom photo limits.
class TeledocPhotoRules {
  const TeledocPhotoRules._();

  static const int maxBytes = 2 * 1024 * 1024;
}

String? _length(String? value, String field, int min, int max) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return '$field obligatoire';
  if (text.length < min) {
    return '$field : au moins $min caractères';
  }
  if (text.length > max) {
    return '$field : $max caractères maximum';
  }
  return null;
}

String? teledocMotifError(String? value) => _length(value, 'Motif', 3, 80);

String? teledocDescriptionError(String? value) =>
    _length(value, 'Description', 10, 1000);

String? teledocOrdonnanceError(String? value) =>
    _length(value, 'Ordonnance', 3, 2000);
