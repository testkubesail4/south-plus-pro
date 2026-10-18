import '../models/forum_models.dart';
import 'forum_client.dart';
import 'forum_request_exception.dart';
import 'parsers/forum_favorites_parser.dart';

class ForumFavoritesService {
  ForumFavoritesService(
      {required ForumClient Function() client,
      required int Function() sessionEpoch,
      required bool Function() isLoggedIn,
      required void Function() didWrite})
      : _client = client,
        _epoch = sessionEpoch,
        _loggedIn = isLoggedIn,
        _didWrite = didWrite;

  final ForumClient Function() _client;
  final int Function() _epoch;
  final bool Function() _loggedIn;
  final void Function() _didWrite;
  final _parser = const ForumFavoritesParser();
  final _loaded = Expando<_FavoritesContext>();
  int _revision = 0;
  bool _writing = false;

  Future<FavoriteCollections> fetchFavoriteCollections(
      {String? categoryId}) async {
    if (categoryId != null && !RegExp(r'^(?:0|[1-9]\d*)$').hasMatch(categoryId))
      _invalid('分类无效，请刷新');
    final client = _client();
    final epoch = _epoch();
    return _publish(
        await _read(client, epoch, categoryId: categoryId), client, epoch);
  }

  Future<FavoriteCollectionMutation> createFavoriteCategory(
          FavoriteCollections snapshot, String name) =>
      _change(snapshot, 'addtype', name: name);
  Future<FavoriteCollectionMutation> deleteFavoriteCategory(
          FavoriteCollections snapshot, String categoryId) =>
      _change(snapshot, 'deltype', categoryId: categoryId);
  Future<FavoriteCollectionMutation> moveFavorites(FavoriteCollections snapshot,
          List<FavoriteCollectionEntry> entries, String categoryId) =>
      _change(snapshot, 'change', categoryId: categoryId, entries: entries);
  Future<FavoriteCollectionMutation> removeFavorites(
          FavoriteCollections snapshot,
          List<FavoriteCollectionEntry> entries) =>
      _change(snapshot, 'clear', entries: entries);
  Future<FavoriteCollectionMutation> addFavoriteToCollection(
          FavoriteCollections snapshot,
          ThreadFavorite favorite,
          String categoryId) =>
      _change(snapshot, 'favorite', categoryId: categoryId, favorite: favorite);

  Future<FavoriteResult> removeFavorite(ThreadFavorite favorite) async {
    final snapshot = await fetchFavoriteCollections();
    final entries = snapshot.items
        .where((entry) => entry.thread.threadId == favorite.tid)
        .toList();
    if (entries.isEmpty) {
      final complete = snapshot.page == 1 && snapshot.pageCount == 1;
      return FavoriteResult(
          success: complete,
          message: complete ? '当前没有收藏该主题' : '结果未确认，请刷新核对',
          state: complete ? ThreadFavoriteState.notFavorite : favorite.state);
    }
    return _legacyResult(await removeFavorites(snapshot, entries),
        previousState: favorite.state);
  }

  FavoriteResult _legacyResult(FavoriteCollectionMutation result,
          {ThreadFavoriteState previousState = ThreadFavoriteState.favorite}) =>
      FavoriteResult(
          success: result.status == FavoriteMutationStatus.confirmed,
          message: result.message,
          state: result.status == FavoriteMutationStatus.confirmed
              ? ThreadFavoriteState.notFavorite
              : previousState);

  Future<FavoriteCollectionMutation> _change(
      FavoriteCollections snapshot, String job,
      {String? name,
      String? categoryId,
      List<FavoriteCollectionEntry> entries = const [],
      ThreadFavorite? favorite}) async {
    final context = _loaded[snapshot];
    if (context == null || context.revision != _revision)
      _invalid('收藏列表已更新，请刷新后重试');
    _check(context.client, context.epoch);
    if (_writing) _invalid('正在处理收藏，请稍候');
    final selected = List<FavoriteCollectionEntry>.of(entries);
    if ((job == 'change' || job == 'clear') &&
        (selected.isEmpty ||
            selected.map((entry) => entry.id).toSet().length !=
                selected.length ||
            selected.any((entry) =>
                !snapshot.items.any((item) => identical(item, entry))))) {
      _invalid('请选择当前列表中的主题');
    }
    if (job == 'favorite' &&
        (favorite == null ||
            !RegExp(r'^[1-9]\d*$').hasMatch(favorite.tid) ||
            favorite.verify.isEmpty ||
            RegExp(r'[\x00-\x20\x7f]').hasMatch(favorite.verify)))
      _invalid('收藏信息无效，请刷新主题');
    final trimmed = name?.trim();
    if (job == 'addtype' &&
        (!snapshot.canCreate ||
            trimmed == null ||
            trimmed.isEmpty ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(trimmed)))
      _invalid('请输入有效的分类名称');
    final intended =
        categoryId == null ? null : _category(snapshot, categoryId);
    if (job == 'deltype' && (intended!.isDefault || !intended.canDelete))
      _invalid('不能删除这个分类');
    _writing = true;
    try {
      final fresh = await _read(context.client, context.epoch);
      final target =
          intended == null ? null : _resolve(intended, fresh.collections);
      if (job == 'addtype') {
        if (!fresh.collections.canCreate || fresh.createVerify == null)
          _invalid('论坛未提供新建分类');
        if (fresh.collections.nameMaxLength != null &&
            trimmed!.length > fresh.collections.nameMaxLength!)
          _invalid('分类名称超过论坛限制');
        if (fresh.collections.categories
            .any((category) => category.label == trimmed))
          _invalid('已有同名分类，请使用不同名称');
      }
      if (job == 'deltype' && !target!.canDelete) _invalid('分类已变更，请刷新后重试');
      if ((job == 'change' || job == 'clear') &&
          (!fresh.jobs.contains(job) ||
              !fresh.destinations.contains(target?.id ?? '0'))) {
        _invalid('论坛未提供这个收藏操作，请刷新后重试');
      }
      for (final entry in selected) {
        if (entry.categoryId == null) _invalid('分类名称不明确，请在原站整理后重试');
        final source = _category(snapshot, entry.categoryId!);
        final resolved = _resolve(source, fresh.collections);
        var current = fresh.collections.items
            .where((item) => item.id == entry.id)
            .toList();
        if (current.isEmpty && !fresh.complete) {
          current = (await _read(context.client, context.epoch,
                  categoryId: resolved.id))
              .collections
              .items
              .where((item) => item.id == entry.id)
              .toList();
        }
        if (current.length != 1 ||
            current.single.thread.threadId != entry.thread.threadId ||
            current.single.categoryId != resolved.id)
          _invalid('所选主题已变更，请刷新后重试');
      }
      _check(context.client, context.epoch);
      // Native category ids are positional. Retire every snapshot before the one write.
      _revision++;
      _loaded[snapshot] = null;
      _didWrite();
      String? response;
      var uncertainTransport = false;
      try {
        if (job == 'favorite') {
          final path = Uri(path: 'pw_ajax.php', queryParameters: {
            'action': 'favor',
            'tid': favorite!.tid,
            'type': target!.id,
            'nowtime': '${DateTime.now().millisecondsSinceEpoch}',
            'verify': fresh.verify,
          }).toString();
          response = await context.client.getForm(path,
              requireCurrentSession: () =>
                  _check(context.client, context.epoch),
              followRedirects: false);
        } else {
          response = await context.client.postForm(
              'u.php?action=favor&',
              [
                MapEntry('verify',
                    job == 'addtype' ? fresh.createVerify! : fresh.verify),
                MapEntry('job', job),
                MapEntry(
                    'type', job == 'addtype' ? trimmed! : target?.id ?? '0'),
                ...selected.map((entry) => MapEntry('selid[]', entry.id)),
              ],
              requireCurrentSession: () =>
                  _check(context.client, context.epoch));
        }
      } catch (_) {
        _check(context.client, context.epoch);
        uncertainTransport = true;
      }
      _check(context.client, context.epoch);
      ForumFavoritesPage after;
      try {
        after = await _read(context.client, context.epoch);
      } catch (_) {
        _check(context.client, context.epoch);
        return _unknown(selected);
      }
      final rejected = response == null ? null : _parser.rejection(response);
      FavoriteCategory? created;
      var status = FavoriteMutationStatus.unknown;
      final outcomes = <FavoriteItemMutation>[];
      if (job == 'addtype') {
        final matches = after.collections.categories
            .where((category) => category.label == trimmed)
            .toList();
        if (matches.length == 1) {
          status = FavoriteMutationStatus.confirmed;
          created = matches.single;
        } else if (rejected != null) {
          status = FavoriteMutationStatus.rejected;
        }
      } else if (job == 'deltype') {
        if (!after.collections.categories
            .any((category) => category.label == intended!.label)) {
          status = FavoriteMutationStatus.confirmed;
        } else if (rejected != null || !uncertainTransport) {
          status = FavoriteMutationStatus.rejected;
        }
      } else {
        ForumFavoritesPage? destination;
        if (target != null) {
          try {
            final resolved = _resolve(intended!, after.collections);
            destination = await _read(context.client, context.epoch,
                categoryId: resolved.id);
            if (_resolve(intended, destination.collections).id !=
                destination.collections.categoryId) {
              destination = null;
            }
          } catch (_) {
            _check(context.client, context.epoch);
          }
        }
        final requested = job == 'favorite'
            ? [
                FavoriteCollectionEntry(
                    id: favorite!.tid,
                    thread: UserListItem(
                        title: '', url: '', threadId: favorite.tid))
              ]
            : selected;
        for (final entry in requested) {
          final allRows = after.collections.items
              .where((row) => job == 'favorite'
                  ? row.thread.threadId == favorite!.tid
                  : job == 'clear'
                      ? row.thread.threadId == entry.thread.threadId
                      : row.id == entry.id &&
                          row.thread.threadId == entry.thread.threadId)
              .toList();
          final there = destination?.collections.items
              .where((row) => job == 'favorite'
                  ? row.thread.threadId == favorite!.tid
                  : row.id == entry.id &&
                      row.thread.threadId == entry.thread.threadId)
              .toList();
          var itemStatus = FavoriteMutationStatus.unknown;
          if (job == 'clear') {
            if (allRows.isEmpty && after.complete)
              itemStatus = FavoriteMutationStatus.confirmed;
            else if (allRows.isNotEmpty && !uncertainTransport)
              itemStatus = FavoriteMutationStatus.rejected;
          } else if (there?.length == 1) {
            itemStatus = FavoriteMutationStatus.confirmed;
          } else if (allRows.length == 1 &&
              allRows.single.categoryId != null &&
              _category(after.collections, allRows.single.categoryId!).label !=
                  intended!.label &&
              !uncertainTransport) {
            itemStatus = FavoriteMutationStatus.rejected;
          } else if (rejected != null) {
            itemStatus = FavoriteMutationStatus.rejected;
          }
          outcomes.add(FavoriteItemMutation(
              id: entry.id,
              status: itemStatus,
              message: itemStatus == FavoriteMutationStatus.rejected
                  ? '主题未完成变更，请刷新核对'
                  : ''));
        }
        status = outcomes
                .any((item) => item.status == FavoriteMutationStatus.unknown)
            ? FavoriteMutationStatus.unknown
            : outcomes.any(
                    (item) => item.status == FavoriteMutationStatus.rejected)
                ? FavoriteMutationStatus.rejected
                : FavoriteMutationStatus.confirmed;
      }
      final view = _publish(after, context.client, context.epoch);
      if (status == FavoriteMutationStatus.unknown) _loaded[view] = null;
      return FavoriteCollectionMutation(
          status: status,
          message: status == FavoriteMutationStatus.unknown
              ? '结果未确认，请刷新核对'
              : status == FavoriteMutationStatus.rejected
                  ? rejected ?? '部分变更未完成，请刷新核对'
                  : job == 'addtype'
                      ? '已新建分类'
                      : job == 'deltype'
                          ? '已删除分类，其中的主题已移到默认分类'
                          : job == 'clear'
                              ? '已取消收藏'
                              : job == 'favorite'
                                  ? '已收藏到所选分类'
                                  : '已移动到所选分类',
          collections: view,
          createdCategory: created,
          items: outcomes);
    } finally {
      _writing = false;
    }
  }

  FavoriteCollectionMutation _unknown(List<FavoriteCollectionEntry> entries) =>
      FavoriteCollectionMutation(
          status: FavoriteMutationStatus.unknown,
          message: '结果未确认，请刷新核对',
          items: entries
              .map((entry) => FavoriteItemMutation(
                  id: entry.id, status: FavoriteMutationStatus.unknown))
              .toList());

  FavoriteCategory _category(FavoriteCollections snapshot, String id) {
    final matches =
        snapshot.categories.where((category) => category.id == id).toList();
    if (matches.length != 1) _invalid('请选择当前列表中的分类');
    final category = matches.single;
    if (!category.isDefault &&
        snapshot.categories
                .where(
                    (item) => !item.isDefault && item.label == category.label)
                .length !=
            1) {
      _invalid('分类名称重复，请在原站整理后重试');
    }
    return category;
  }

  FavoriteCategory _resolve(
      FavoriteCategory intended, FavoriteCollections fresh) {
    final matches = fresh.categories
        .where((category) => intended.isDefault
            ? category.isDefault
            : !category.isDefault && category.label == intended.label)
        .toList();
    if (matches.length != 1) _invalid('分类名称不明确或已变更，请刷新后重试');
    return matches.single;
  }

  Future<ForumFavoritesPage> _read(ForumClient client, int epoch,
      {String? categoryId}) async {
    _check(client, epoch);
    final response = await client.getForm(
        'u.php?action=favor${categoryId == null ? '' : '&type=$categoryId'}',
        requireCurrentSession: () => _check(client, epoch),
        followRedirects: false);
    _check(client, epoch);
    return _parser.parse(response, client.baseUri, categoryId: categoryId);
  }

  FavoriteCollections _publish(
      ForumFavoritesPage page, ForumClient client, int epoch) {
    _check(client, epoch);
    _loaded[page.collections] = _FavoritesContext(client, epoch, _revision);
    return page.collections;
  }

  void _check(ForumClient client, int epoch) {
    if (!_loggedIn() || !identical(client, _client()) || epoch != _epoch()) {
      throw const ForumRequestException(
          ForumRequestKind.loginRequired, '登录状态已变更，请重新打开收藏');
    }
  }

  Never _invalid(String message) =>
      throw ForumRequestException(ForumRequestKind.invalidInput, message);
}

class _FavoritesContext {
  const _FavoritesContext(this.client, this.epoch, this.revision);
  final ForumClient client;
  final int epoch;
  final int revision;
}
