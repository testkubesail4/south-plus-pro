import 'package:html/dom.dart' as dom;

class ForumFormParser {
  const ForumFormParser();

  Map<String, String> defaults(dom.Element form) {
    final fields = <String, String>{};
    for (final input in form.querySelectorAll('input[name]')) {
      final name = input.attributes['name'];
      if (name == null || name.isEmpty) continue;
      final type = (input.attributes['type'] ?? '').toLowerCase();
      if (type == 'submit' || type == 'reset' || type == 'button') continue;
      if ((type == 'radio' || type == 'checkbox') &&
          !input.attributes.containsKey('checked')) {
        continue;
      }
      fields[name] = input.attributes['value'] ?? '';
    }

    for (final select in form.querySelectorAll('select[name]')) {
      final name = select.attributes['name'];
      if (name == null || name.isEmpty) continue;
      final option = select.querySelector('option[selected]') ??
          select.querySelector('option');
      if (option == null) continue;
      fields[name] = option.attributes['value'] ?? _cleanText(option.text);
    }

    for (final textarea in form.querySelectorAll('textarea[name]')) {
      final name = textarea.attributes['name'];
      if (name == null || name.isEmpty) continue;
      fields[name] = textarea.text;
    }
    return fields;
  }

  String _cleanText(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
