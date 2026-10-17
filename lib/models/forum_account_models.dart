import 'dart:typed_data';

import '../services/forum_request_exception.dart';

enum ForumAccountFormKind { preferences, profile }

class ForumAccountOption {
  const ForumAccountOption(
      {required this.value, required this.label, this.imageUrl});
  final String value;
  final String label;
  final String? imageUrl;
}

class ForumAccountAvatarPage {
  ForumAccountAvatarPage(
      {required this.page,
      required List<ForumAccountOption> options,
      this.nextPage,
      this.previousPage})
      : options = List.unmodifiable(options);
  final int page;
  final List<ForumAccountOption> options;
  final int? nextPage;
  final int? previousPage;
}

class ForumAccountField {
  ForumAccountField({
    required this.name,
    required this.label,
    required this.type,
    required List<String> values,
    List<ForumAccountOption> options = const [],
    this.required = false,
    this.maxLength,
    this.min,
    this.max,
    this.pattern,
    this.accept,
    this.hint = '',
    this.group,
  })  : values = List.unmodifiable(values),
        options = List.unmodifiable(options);

  final String name;
  final String label;
  final String type;
  final List<String> values;
  final List<ForumAccountOption> options;
  final bool required;
  final int? maxLength;
  final num? min;
  final num? max;
  final String? pattern;
  final String? accept;
  final String hint;
  final String? group;
  String get value => values.isEmpty ? '' : values.first;
}

class ForumAccountForm {
  ForumAccountForm(
      {required this.kind, required List<ForumAccountField> fields})
      : fields = List.unmodifiable(fields);
  final ForumAccountFormKind kind;
  final List<ForumAccountField> fields;

  ForumAccountField? field(String name) {
    for (final field in fields) {
      if (field.name == name) return field;
    }
    return null;
  }
}

class ForumAccountValidationException extends ForumRequestException {
  ForumAccountValidationException(String field, String message)
      : fieldErrors = Map.unmodifiable({field: message}),
        super(ForumRequestKind.invalidInput, message);
  final Map<String, String> fieldErrors;
}

class ForumAccountUpload {
  ForumAccountUpload({
    required Uint8List bytes,
    required this.fileName,
    required this.mimeType,
  }) : bytes = Uint8List.fromList(bytes).asUnmodifiableView();
  final Uint8List bytes;
  final String fileName;
  final String mimeType;
}
