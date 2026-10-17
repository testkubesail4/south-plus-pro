import 'package:flutter_test/flutter_test.dart';
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/services/search_board_hierarchy.dart';

void main() {
  test('homepage nests authorized search scopes by fid without granting scopes',
      () {
    const options = [
      ForumSearchBoard(id: 'all', name: 'All boards'),
      ForumSearchBoard(id: '10', name: '>> Fixture section'),
      ForumSearchBoard(id: '11', name: '|- First parent', depth: 1),
      ForumSearchBoard(id: '19', name: '|- Search-only board', depth: 1),
      ForumSearchBoard(id: '12', name: '|- Shared child', depth: 1),
      ForumSearchBoard(
          id: '13', name: '|- Disabled child', depth: 1, selectable: false),
      ForumSearchBoard(id: '14', name: '|- Second parent', depth: 1),
      ForumSearchBoard(id: '15', name: '|- Shared child', depth: 1),
      ForumSearchBoard(id: '18', name: '|- Orphan child', depth: 1),
      ForumSearchBoard(id: '', name: '>> Search-only group', selectable: false),
      ForumSearchBoard(id: '88', name: '|- Other board', depth: 1),
    ];
    const sections = [
      ForumSection(title: 'Fixture section', items: [
        ForumBoard(
            name: 'First parent',
            url: 'https://south-plus.net/thread.php?fid-11.html',
            section: 'Fixture section',
            children: [
              ForumBoard(
                  name: 'Shared child',
                  url: 'https://south-plus.net/thread.php?fid-12.html',
                  section: 'Fixture section / First parent'),
              ForumBoard(
                  name: 'Disabled child',
                  url: 'https://south-plus.net/thread_new.php?fid=13',
                  section: 'Fixture section / First parent'),
              ForumBoard(
                  name: 'Homepage-only child',
                  url: 'https://south-plus.net/thread.php?fid-17.html',
                  section: 'Fixture section / First parent'),
            ]),
        ForumBoard(
            name: 'Second parent',
            url: 'https://south-plus.net/thread.php?fid-14.html',
            section: 'Fixture section',
            children: [
              ForumBoard(
                  name: 'Shared child',
                  url: 'https://south-plus.net/thread.php?fid-15.html',
                  section: 'Fixture section / Second parent'),
            ]),
        ForumBoard(
            name: 'Missing parent',
            url: 'https://south-plus.net/thread.php?fid-16.html',
            section: 'Fixture section',
            children: [
              ForumBoard(
                  name: 'Orphan child',
                  url: 'https://south-plus.net/thread.php?fid-18.html',
                  section: 'Fixture section / Missing parent'),
            ]),
      ]),
    ];

    final merged = mergeSearchBoardHierarchy(options, sections);

    expect(merged.map((board) => board.id),
        ['all', '10', '11', '12', '13', '19', '14', '15', '18', '', '88']);
    expect(
        merged.map((board) => board.depth), [0, 0, 1, 2, 2, 1, 1, 2, 1, 0, 1]);
    expect(merged[1].selectable, isTrue);
    expect(merged[3].name, '|- Shared child');
    expect(merged[7].name, '|- Shared child');
    expect(merged[4].selectable, isFalse);
    expect(merged[9].selectable, isFalse);
  });

  for (final origin in [
    'https://forum-fixture.invalid:8443/',
    'http://127.0.0.1:8765/',
  ]) {
    test(
        'configured origin $origin nests only authorized same-origin board URLs',
        () {
      final base = Uri.parse(origin);
      const options = [
        ForumSearchBoard(id: '10', name: '>> Fixture section'),
        ForumSearchBoard(id: '11', name: 'Parent', depth: 1),
        ForumSearchBoard(id: '19', name: 'Search-only', depth: 1),
        ForumSearchBoard(id: '12', name: 'Shared child', depth: 1),
        ForumSearchBoard(id: '13', name: 'Shared child', depth: 1),
        ForumSearchBoard(id: '14', name: 'Other port', depth: 1),
        ForumSearchBoard(id: '16', name: 'Untrusted parent', depth: 1),
      ];
      final sections = [
        ForumSection(title: 'Fixture section', items: [
          ForumBoard(
              name: 'Parent',
              url: base.resolve('thread.php?fid-11.html').toString(),
              section: 'Fixture section',
              children: [
                ForumBoard(
                    name: 'Shared child',
                    url: base.resolve('thread.php?fid-12.html').toString(),
                    section: 'Fixture section / Parent'),
                const ForumBoard(
                    name: 'Shared child',
                    url:
                        'https://foreign-fixture.invalid/thread.php?fid-13.html',
                    section: 'Fixture section / Parent'),
                ForumBoard(
                    name: 'Other port',
                    url: base
                        .replace(port: base.port + 1)
                        .resolve('thread.php?fid-14.html')
                        .toString(),
                    section: 'Fixture section / Parent'),
                ForumBoard(
                    name: 'Homepage-only',
                    url: base.resolve('thread.php?fid-99.html').toString(),
                    section: 'Fixture section / Parent'),
              ]),
          ForumBoard(
              name: 'Untrusted parent',
              url: 'https://foreign-fixture.invalid/thread.php?fid-20.html',
              section: 'Fixture section',
              children: [
                ForumBoard(
                    name: 'Untrusted parent',
                    url: base.resolve('thread.php?fid-16.html').toString(),
                    section: 'Fixture section / Untrusted parent'),
              ]),
        ])
      ];
      final merged =
          mergeSearchBoardHierarchy(options, sections, baseUri: base);
      expect(merged.map((board) => board.id),
          ['10', '11', '12', '19', '13', '14', '16']);
      expect(merged.map((board) => board.depth), [0, 1, 2, 1, 1, 1, 1]);
      expect(merged.map((board) => board.id).toSet(),
          options.map((board) => board.id).toSet(),
          reason: 'homepage hierarchy never grants an unoffered search FID');
    });
  }
}
