import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable, ValueNotifier;
import 'package:south_plus_rewrite/models/forum_models.dart';
import 'package:south_plus_rewrite/models/user_content_query.dart';
import 'package:south_plus_rewrite/services/forum_client.dart';
import 'package:south_plus_rewrite/services/forum_network_config.dart';
import 'package:south_plus_rewrite/services/forum_repository.dart';

const profileFixture = UserProfile(
  uid: '123',
  name: 'Alice',
  url: 'u.php?action-show-uid-123.html',
);

UserListItem listItem(String title, {String? tid, String? pid, String? fid}) =>
    UserListItem(
      title: title,
      url: 'read.php?tid-${tid ?? title.hashCode.abs()}.html',
      threadId: tid,
      postId: pid,
      boardId: fid,
      section: fid == null ? null : '版块$fid',
    );

UserContentResult contentResult({
  List<UserListItem> items = const [],
  List<UserListItem> unresolved = const [],
  int scanned = 1,
  int total = 3,
  int checked = 0,
  int pending = 0,
  bool hasMore = true,
}) =>
    UserContentResult(
      items: items,
      unresolvedItems: unresolved,
      boards: const [],
      scannedPages: scanned,
      totalPages: total,
      checkedThreads: checked,
      pendingMetadataCount: pending,
      hasMore: hasMore,
    );

/// Serves a fixed profile and scripted user-content answers; no network.
class FakeProfileRepository extends ForumRepository {
  FakeProfileRepository({
    this.topics = const [],
    this.posts = const [],
    this.onContent,
  }) : super(client: ForumClient());

  final List<UserListItem> topics;
  final List<UserListItem> posts;
  Future<UserContentResult> Function(UserContentQuery query)? onContent;
  List<ForumSearchBoard> boards = const [
    ForumSearchBoard(id: 'all', name: '全部版块'),
    ForumSearchBoard(id: '0', name: '>> 综合区', selectable: false),
    ForumSearchBoard(id: '7', name: '|- 影视区', depth: 1),
  ];
  List<UserContentClassification> classifications = const [
    UserContentClassification(id: '3', label: '求助'),
  ];
  final queries = <UserContentQuery>[];
  final refreshes = <bool>[];
  // While set, profile details stay pending (a slow refresh).
  Completer<void>? holdDetails;
  int boardLoads = 0;

  @override
  Future<UserProfile?> cachedUserProfileOverview(String url) async =>
      profileFixture;

  @override
  Future<UserProfile> fetchUserProfileOverview(String url) async =>
      profileFixture;

  @override
  Future<UserProfile> fetchUserProfileDetails(
    UserProfile overview, {
    bool forceReload = false,
  }) async {
    await holdDetails?.future;
    return overview.copyWith(topics: topics, posts: posts);
  }

  @override
  Future<List<ForumSearchBoard>> fetchSearchBoards() async {
    boardLoads++;
    return boards;
  }

  // Bumped by a test to change the session under an open screen.
  final epoch = ValueNotifier<int>(0);

  @override
  ValueListenable<int> get sessionEpoch => epoch;

  // A forum on another origin than the default one.
  ForumNetworkConfig? config;

  @override
  ForumNetworkConfig get networkConfig => config ?? super.networkConfig;

  // The homepage only says which board sits under which.
  List<ForumSection> sections = const [];
  bool sectionsFail = false;

  // While set, the homepage stays pending.
  Completer<void>? holdSections;

  @override
  Future<List<ForumSection>> fetchForumSections() async {
    await holdSections?.future;
    if (sectionsFail) throw StateError('homepage unavailable');
    return sections;
  }

  @override
  Future<List<UserContentClassification>> fetchUserContentBoardFilters(
          String boardId) async =>
      classifications;

  @override
  Future<UserContentResult> fetchUserContent(
    UserContentQuery query, {
    bool refresh = false,
  }) {
    queries.add(query);
    refreshes.add(refresh);
    return onContent!(query);
  }
}
