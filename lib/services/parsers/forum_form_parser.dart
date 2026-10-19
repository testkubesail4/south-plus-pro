import 'package:html/dom.dart' as dom;

class ForumFormParser {
  const ForumFormParser();

  Map<String, String> defaults(dom.Element form) =>
      Map<String, String>.fromEntries(defaultEntries(form));

  List<MapEntry<String, String>> defaultEntries(dom.Element form) {
    final fields = <MapEntry<String, String>>[];
    for (final input in form.querySelectorAll('input[name]')) {
      final name = input.attributes['name'];
      if (name == null || name.isEmpty || _disabled(input)) continue;
      final type = (input.attributes['type'] ?? '').toLowerCase();
      if (const {'submit', 'reset', 'button', 'file'}.contains(type)) continue;
      if ((type == 'radio' || type == 'checkbox') &&
          !input.attributes.containsKey('checked')) {
        continue;
      }
      fields.add(
        MapEntry(
          name,
          input.attributes['value'] ??
              ((type == 'checkbox' || type == 'radio') ? 'on' : ''),
        ),
      );
    }

    for (final select in form.querySelectorAll('select[name]')) {
      final name = select.attributes['name'];
      if (name == null || name.isEmpty || _disabled(select)) continue;
      final selected = select.querySelectorAll('option[selected]');
      final options = select.attributes.containsKey('multiple')
          ? selected
          : [selected.firstOrNull ?? select.querySelector('option')];
      for (final option in options) {
        if (option == null || _disabled(option)) continue;
        fields.add(
          MapEntry(name, option.attributes['value'] ?? _cleanText(option.text)),
        );
      }
    }

    for (final textarea in form.querySelectorAll('textarea[name]')) {
      final name = textarea.attributes['name'];
      if (name == null || name.isEmpty || _disabled(textarea)) continue;
      fields.add(MapEntry(name, textarea.text));
    }
    return fields;
  }

  bool _disabled(dom.Element element) {
    if (element.attributes.containsKey('disabled')) return true;
    var parent = element.parent;
    while (parent != null) {
      if (parent.localName == 'fieldset' &&
          parent.attributes.containsKey('disabled')) return true;
      parent = parent.parent;
    }
    return false;
  }

  String _cleanText(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
