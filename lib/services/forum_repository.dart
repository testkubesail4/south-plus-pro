import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

import '../models/forum_models.dart';
import 'browsing_history_store.dart';
import 'forum_client.dart';
import 'forum_network_config.dart';
import 'forum_task_state_store.dart';
import 'forum_url_resolver.dart';
import 'user_profile_cache.dart';
import 'parsers/board_thread_page_parser.dart';
import 'parsers/forum_form_parser.dart';
import 'parsers/forum_response_parser.dart';
import 'parsers/forum_tasks_parser.dart';
import 'parsers/home_page_parser.dart';
import 'parsers/search_result_parser.dart';
import 'parsers/thread_content_parser.dart';
import 'parsers/thread_detail_parser.dart';
import 'parsers/user_profile_parser.dart';

class ForumRepository {
  ForumRepository({
    ForumClient? client,
    ForumNetworkConfig? config,
    UserProfileCache? profileCache,
    BrowsingHistoryStore? historyStore,
    ForumTaskStateStore? taskStateStore,
  })  : _client = client ??
            ForumClient(
              config: config ??
                  const ForumNetworkConfig(
                    site: ForumNetworkConfig.defaultSite,
                    dohEnabled: true,
                    dohProvider: ForumNetworkConfig.defaultProvider,
                  ),
            ),
        _config = config ??
            client?.config ??
            const ForumNetworkConfig(
              site: ForumNetworkConfig.defaultSite,
              dohEnabled: true,
              dohProvider: ForumNetworkConfig.defaultProvider,
            ),
        _urls = ForumUrlResolver(
          baseUri: (config ?? client?.config)?.baseUri ??
              ForumNetworkConfig.defaultSite.baseUri,
        ),
        _profileCache = profileCache ??
            UserProfileCache(
              urls: ForumUrlResolver(
                baseUri: (config ?? client?.config)?.baseUri ??
                    ForumNetworkConfig.defaultSite.baseUri,
              ),
            ),
        _historyStore = historyStore ?? BrowsingHistoryStore(),
        _taskStateStore = taskStateStore ?? const ForumTaskStateStore();

  ForumClient _client;
  ForumNetworkConfig _config;
  ForumUrlResolver _urls;
  late BoardThreadPageParser _boardThreadPageParser =
      BoardThreadPageParser(urls: _urls);
  final ForumFormParser _formParser = const ForumFormParser();
  final ForumResponseParser _responseParser = const ForumResponseParser();
  final ForumTasksParser _tasksParser = const ForumTasksParser();
  late HomePageParser _homePageParser = HomePageParser(urls: _urls);
  late SearchResultParser _searchResultParser = SearchResultParser(urls: _urls);
  late ThreadDetailParser _threadDetailParser = ThreadDetailParser(
    urls: _urls,
    contentParser: ThreadContentParser(urls: _urls),
  );
  late UserProfileParser _userProfileParser = UserProfileParser(urls: _urls);
  UserProfileCache _profileCache;
  final BrowsingHistoryStore _historyStore;
  final ForumTaskStateStore _taskStateStore;
  String? _currentUsername;

  bool get isLoggedIn => _client.isLoggedIn;

  String? get currentUsername => _currentUsername;

  ForumNetworkConfig get networkConfig => _config;

  Future<void> updateNetworkConfig(ForumNetworkConfig config) async {
    if (config == _config) return;
    _client.close(force: true);
    _config = config;
    _urls = ForumUrlResolver(baseUri: config.baseUri);
    _boardThreadPageParser = BoardThreadPageParser(urls: _urls);
    _homePageParser = HomePageParser(urls: _urls);
    _searchResultParser = SearchResultParser(urls: _urls);
    _threadDetailParser = ThreadDetailParser(
      urls: _urls,
      contentParser: ThreadContentParser(urls: _urls),
    );
    _userProfileParser = UserProfileParser(urls: _urls);
    _profileCache = UserProfileCache(urls: _urls);
    _client = ForumClient(config: config);
    _currentUsername = null;
    await ForumNetworkSettings.save(config);
  }

  Future<bool> restoreSession() async {
    await _client.restoreCookies();
    if (!_client.isLoggedIn) return false;

    _currentUsername = await _fetchLoggedInUsername();
    if (_currentUsername == null) {
      await clearSession();
      return false;
    }
    return true;
  }

  Future<void> clearSession() async {
    _currentUsername = null;
    await _client.clearSession();
  }

  Future<bool> login({
    required String username,
    required String password,
    String captcha = '',
    Map<String, String> fields = const {},
  }) async {
    if (username.trim().isEmpty || password.isEmpty) {
      return false;
    }

    final result = await submitLogin(
      username: username,
      password: password,
      captcha: captcha,
      fields: fields,
    );
    return result.success;
  }

  Future<LoginChallenge> fetchLoginChallenge() async {
    final html = await _client.get('login.php');
    final document = html_parser.parse(html);
    final form = document.querySelector('form[name="login"]') ??
        document.querySelector('form[action*="login.php"]') ??
        _loginFormFromFields(document);
    if (form == null) {
      throw ForumRepositoryException(
        _responseParser.pageMessage(html) == '登录失败'
            ? '没有找到登录表单'
            : _responseParser.pageMessage(html),
      );
    }

    final fields = _formParser.defaults(form)
      ..remove('pwuser')
      ..remove('pwpwd')
      ..remove('gdcode');

    final captchaSrc = form.querySelector('#ckcode')?.attributes['src'] ??
        form.querySelector('img[src*="ck.php"]')?.attributes['src'] ??
        form.querySelector('img[src*="gdcode"]')?.attributes['src'] ??
        form.querySelector('img[src*="captcha"]')?.attributes['src'];
    if (captchaSrc == null || captchaSrc.isEmpty) {
      throw const ForumRepositoryException('没有找到验证码图片');
    }

    return LoginChallenge(
      fields: fields,
      captchaBytes: await _client.getBytes(_urls.captchaPath(captchaSrc)),
    );
  }

  Future<LoginResult> submitLogin({
    required String username,
    required String password,
    required String captcha,
    required Map<String, String> fields,
  }) async {
    if (username.trim().isEmpty) {
      return const LoginResult(success: false, message: '用户名不能为空');
    }
    if (password.isEmpty) {
      return const LoginResult(success: false, message: '密码不能为空');
    }
    if (captcha.trim().isEmpty) {
      return const LoginResult(success: false, message: '验证码不能为空');
    }

    final response = await _client.post('login.php', {
      ...fields,
      'step': fields['step'] ?? '2',
      'lgt': fields['lgt'] ?? '0',
      'hideid': fields['hideid'] ?? '0',
      'cktime': fields['cktime'] ?? '31536000',
      'pwuser': username.trim(),
      'pwpwd': password,
      'gdcode': captcha.trim(),
      'submit': '登 录',
    });

    if (_client.isLoggedIn || response.contains('登录成功')) {
      _currentUsername = _responseParser.loggedInUsername(response) ??
          await _fetchLoggedInUsername() ??
          username.trim();
      return const LoginResult(success: true, message: '登录成功');
    }

    return LoginResult(
      success: false,
      message: _responseParser.pageMessage(response),
    );
  }

  Future<ForumHomeSnapshot> fetchHome() async {
    final html = await _client.get('simple/index.php');
    final document = html_parser.parse(html);
    var latest = _homePageParser.parseLatestThreads(document);
    final latestScriptUrl = _homePageParser.latestThreadsScriptUrl(document);
    if (latest.isEmpty && latestScriptUrl != null) {
      final script = await _client.get(_urls.relativePath(latestScriptUrl));
      latest = _homePageParser.parseLatestThreadsFromScript(script);
    }
    final hot = _homePageParser.parseHotCategories(document);
    var sections = _homePageParser.parseForumSections(document);
    try {
      final desktopDocument = html_parser.parse(await _client.get('index.php'));
      final desktopSections =
          _homePageParser.parseDesktopForumSections(desktopDocument);
      if (desktopSections.isNotEmpty) sections = desktopSections;
    } catch (_) {
      // Keep the mobile/simple directory if the desktop home is unavailable.
    }

    if (latest.isEmpty) {
      throw const ForumRepositoryException('没有解析到最新讨论');
    }
    if (hot.isEmpty && sections.isEmpty) {
      throw const ForumRepositoryException('没有解析到版块列表');
    }

    return ForumHomeSnapshot(latest: latest, hot: hot, sections: sections);
  }

  Future<List<ForumThread>> fetchLatestThreads() async {
    final home = await fetchHome();
    return home.latest;
  }

  Future<List<ForumTask>> fetchForumTasks(ForumTaskStatus status) async {
    final path = switch (status) {
      ForumTaskStatus.available => 'plugin.php?H_name-tasks.html',
      ForumTaskStatus.inProgress =>
        'plugin.php?H_name-tasks-actions-newtasks.html.html',
      ForumTaskStatus.completed =>
        'plugin.php?H_name-tasks-actions-endtasks.html.html',
      ForumTaskStatus.failed =>
        'plugin.php?H_name-tasks-actions-errotasks.html.html',
    };
    final html = await _client.get(path);
    final tasks = _tasksParser.parse(html_parser.parse(html), status);
    await _updateTaskSnapshot(tasks);
    return tasks;
  }

  Future<ForumTaskActionResult> runForumTask(ForumTask task) async {
    final id = task.id;
    if (id == null || id.isEmpty) {
      return const ForumTaskActionResult(
        success: false,
        message: '没有找到任务 ID',
      );
    }

    final response = await _client.get(
      'plugin.php?H_name=tasks&action=ajax&actions=job&cid=$id',
    );
    final parts = response.split('\t');
    final status = parts.first.trim().toLowerCase();
    final message = parts.length > 1
        ? _cleanText(parts.skip(1).join(' '))
        : _responseParser.ajaxMessage(response);
    final success = status == 'success';
    return ForumTaskActionResult(
      success: success,
      message: message.isEmpty
          ? success
              ? '任务奖励领取完成'
              : '任务操作失败'
          : message,
    );
  }

  Future<ForumTaskQuickClaimResult> claimForumTaskRewards() async {
    final now = _nowUtc();
    final failures = <String>[];
    final skipped = <String>[];
    final inProgressNames = <String>{};
    final actionHandledNames = <String>{};
    var appliedCount = 0;
    final claimedRewards = <ForumTaskClaimItem>[];

    final completedTasks = await fetchForumTasks(ForumTaskStatus.completed);
    final availableTasks = await fetchForumTasks(ForumTaskStatus.available);
    final currentCycleCompletedNames =
        _currentCycleCompletedNames(completedTasks, now: now);
    final initialTargetNames = _targetTaskNames([
      ...completedTasks,
      ...availableTasks,
    ]);
    final pendingNames = initialTargetNames.where((name) {
      final availableForName =
          availableTasks.where((task) => task.name == name).toList();
      final hasFreshStartAction = availableForName.any(_isStartableForumTask);
      return hasFreshStartAction || !currentCycleCompletedNames.contains(name);
    }).toSet();
    final runnableAvailableTasks = availableTasks.where((task) {
      return pendingNames.contains(task.name) && _isStartableForumTask(task);
    }).toList();
    var actionChangedState = false;

    for (final task in runnableAvailableTasks) {
      final result = await runForumTask(task);
      final decision = _classifyTaskAction(
        result,
        expectation: _ForumTaskActionExpectation.start,
      );
      switch (decision.kind) {
        case _ForumTaskActionKind.started:
          appliedCount += 1;
          actionChangedState = true;
          break;
        case _ForumTaskActionKind.rewardClaimed:
          actionHandledNames.add(task.name);
          claimedRewards.add(_claimItemFromTask(task, result.message));
          actionChangedState = true;
          break;
        case _ForumTaskActionKind.alreadyStarted:
          appliedCount += 1;
          actionChangedState = true;
          break;
        case _ForumTaskActionKind.alreadyCompleted:
        case _ForumTaskActionKind.coolingDown:
          actionHandledNames.add(task.name);
          actionChangedState = true;
          break;
        case _ForumTaskActionKind.loginRequired:
        case _ForumTaskActionKind.failure:
          failures.add('${task.name}：${decision.message}');
          break;
      }
    }

    final shouldCheckInProgress = runnableAvailableTasks.isNotEmpty ||
        pendingNames.any((name) {
          final task = availableTasks.where((task) => task.name == name);
          return task.isEmpty ||
              task.any((task) =>
                  !_isStartableForumTask(task) ||
                  task.cooldownRemaining != null);
        });
    final latestInProgressTasks = shouldCheckInProgress
        ? await fetchForumTasks(ForumTaskStatus.inProgress)
        : const <ForumTask>[];
    final targetNames = _targetTaskNames([
      ...completedTasks,
      ...availableTasks,
      ...latestInProgressTasks,
    ]);
    final rewardsChangedState = await _claimRewardsFromTasks(
      latestInProgressTasks,
      targetNames: targetNames,
      claimedRewards: claimedRewards,
      failures: failures,
      skipped: skipped,
      handledNames: actionHandledNames,
    );
    inProgressNames.addAll(
      latestInProgressTasks
          .where((task) =>
              targetNames.contains(task.name) && !_isClaimableForumTask(task))
          .map((task) => task.name),
    );

    final shouldRefreshAfterActions =
        actionChangedState || rewardsChangedState || claimedRewards.isNotEmpty;
    final refreshedCompletedTasks = shouldRefreshAfterActions
        ? await fetchForumTasks(ForumTaskStatus.completed)
        : completedTasks;
    final refreshedAvailableTasks = shouldRefreshAfterActions
        ? await fetchForumTasks(ForumTaskStatus.available)
        : availableTasks;
    final snapshot = await _saveTaskSnapshotFromPages(
      inProgress: latestInProgressTasks,
      available: refreshedAvailableTasks,
      completed: refreshedCompletedTasks,
    );
    final handledNames = snapshot.tasks
        .where((task) =>
            task.availability == ForumTaskAvailability.completed ||
            task.availability == ForumTaskAvailability.coolingDown)
        .map((task) => task.name)
        .toSet()
      ..addAll(actionHandledNames);
    final alreadyHandled = claimedRewards.isEmpty &&
        appliedCount == 0 &&
        failures.isEmpty &&
        inProgressNames.isEmpty &&
        targetNames.isNotEmpty &&
        targetNames.every(handledNames.contains);

    return ForumTaskQuickClaimResult(
      appliedCount: appliedCount,
      claimedRewards: claimedRewards,
      failures: failures,
      skipped: skipped,
      inProgress: inProgressNames.toList(),
      alreadyHandled: alreadyHandled,
    );
  }

  Future<ForumTaskQuickClaimResult?> autoClaimForumTaskRewardsIfDue() async {
    if (!isLoggedIn) return null;

    final cached = await loadCachedForumTaskSnapshot();
    if (cached != null && !cached.shouldAutoClaimAt(_nowUtc())) {
      return null;
    }

    return claimForumTaskRewards();
  }

  Future<bool> _claimRewardsFromTasks(
    List<ForumTask> tasks, {
    required Set<String> targetNames,
    required List<ForumTaskClaimItem> claimedRewards,
    required List<String> failures,
    required List<String> skipped,
    required Set<String> handledNames,
  }) async {
    var changedState = false;
    final claimedNames = claimedRewards.map((item) => item.name).toSet();
    final claimableTasks = tasks.where((task) {
      return targetNames.contains(task.name) && _isClaimableForumTask(task);
    });

    for (final task in claimableTasks) {
      if (claimedNames.contains(task.name)) continue;
      final result = await runForumTask(task);
      final decision = _classifyTaskAction(
        result,
        expectation: _ForumTaskActionExpectation.claimReward,
      );
      if (decision.kind == _ForumTaskActionKind.rewardClaimed) {
        claimedNames.add(task.name);
        handledNames.add(task.name);
        claimedRewards.add(_claimItemFromTask(task, result.message));
        changedState = true;
        await _updateTaskSnapshot([
          ForumTask(
            id: task.id,
            name: task.name,
            status: ForumTaskStatus.completed,
            reward: task.reward,
            progressPercent: 100,
          ),
        ]);
      } else {
        switch (decision.kind) {
          case _ForumTaskActionKind.alreadyCompleted:
          case _ForumTaskActionKind.coolingDown:
            handledNames.add(task.name);
            changedState = true;
            break;
          case _ForumTaskActionKind.started:
          case _ForumTaskActionKind.alreadyStarted:
            changedState = true;
            break;
          case _ForumTaskActionKind.loginRequired:
          case _ForumTaskActionKind.failure:
            failures.add('${task.name}：${decision.message}');
            break;
          case _ForumTaskActionKind.rewardClaimed:
            break;
        }
      }
    }
    return changedState;
  }

  ForumTaskClaimItem _claimItemFromTask(ForumTask task, String message) {
    return ForumTaskClaimItem(
      name: task.name,
      reward: task.reward,
      spAmount: _spAmount(task.reward),
      message: message,
    );
  }

  bool _isClaimableForumTask(ForumTask task) {
    if (!task.canRun) return false;
    final label = task.actionLabel ?? '';
    if (label.contains('领取')) return true;
    return task.progressPercent != null && task.progressPercent! >= 100;
  }

  bool _isStartableForumTask(ForumTask task) {
    if (!task.canRun) return false;
    final label = task.actionLabel ?? '';
    return label.contains('申请');
  }

  _ForumTaskActionDecision _classifyTaskAction(
    ForumTaskActionResult result, {
    required _ForumTaskActionExpectation expectation,
  }) {
    final message = _cleanText(result.message);
    final text = message.replaceAll(RegExp(r'\s+'), '');
    if (_looksLikeLoginRequired(message)) {
      return _ForumTaskActionDecision(
        _ForumTaskActionKind.loginRequired,
        message.isEmpty ? '登录状态已失效' : message,
      );
    }
    if (_alreadyCompletedTask(message)) {
      return _ForumTaskActionDecision(
        _ForumTaskActionKind.alreadyCompleted,
        message.isEmpty ? '奖励已领取' : message,
      );
    }
    if (_taskCooldownMessage(message)) {
      return _ForumTaskActionDecision(
        _ForumTaskActionKind.coolingDown,
        message.isEmpty ? '任务处于冷却中' : message,
      );
    }
    if (_alreadyStartedTask(message)) {
      return _ForumTaskActionDecision(
        _ForumTaskActionKind.alreadyStarted,
        message.isEmpty ? '任务已领取，等待完成' : message,
      );
    }
    if (result.success) {
      if (text.contains('奖励')) {
        return _ForumTaskActionDecision(
          _ForumTaskActionKind.rewardClaimed,
          message.isEmpty ? '任务奖励领取完成' : message,
        );
      }
      if (text.contains('任务') && text.contains('领取')) {
        return _ForumTaskActionDecision(
          _ForumTaskActionKind.started,
          message.isEmpty ? '任务领取完成' : message,
        );
      }
      return _ForumTaskActionDecision(
        expectation == _ForumTaskActionExpectation.claimReward
            ? _ForumTaskActionKind.rewardClaimed
            : _ForumTaskActionKind.started,
        message.isEmpty ? '任务操作完成' : message,
      );
    }
    return _ForumTaskActionDecision(
      _ForumTaskActionKind.failure,
      message.isEmpty ? '任务操作失败' : message,
    );
  }

  int? _spAmount(String? reward) {
    final text = reward ?? '';
    final match =
        RegExp(r'SP\s*币?\s*(\d+)', caseSensitive: false).firstMatch(text);
    return int.tryParse(match?.group(1) ?? '');
  }

  bool _alreadyStartedTask(String message) {
    final text = message.replaceAll(RegExp(r'\s+'), '');
    return text.contains('任务已领取') ||
        text.contains('已经领取任务') ||
        text.contains('已申领') ||
        text.contains('已经申领');
  }

  bool _alreadyCompletedTask(String message) {
    final text = message.replaceAll(RegExp(r'\s+'), '');
    return text.contains('奖励已领取') ||
        text.contains('已经领取奖励') ||
        text.contains('已经完成') ||
        text.contains('已完成任务');
  }

  bool _taskCooldownMessage(String message) {
    final text = message.replaceAll(RegExp(r'\s+'), '');
    return text.contains('距离上次') ||
        text.contains('上次领取未超过') ||
        text.contains('没超过') ||
        text.contains('冷却');
  }

  bool _looksLikeLoginRequired(String message) {
    final text = message.replaceAll(RegExp(r'\s+'), '');
    return text.contains('登录') ||
        text.contains('登陆') ||
        text.contains('请先登录') ||
        text.contains('login.php');
  }

  Future<ForumTaskSnapshot?> loadCachedForumTaskSnapshot() {
    return _taskStateStore.load();
  }

  Future<ForumTaskSnapshot> refreshForumTaskSnapshot() async {
    final inProgress = await fetchForumTasks(ForumTaskStatus.inProgress);
    final completed = await fetchForumTasks(ForumTaskStatus.completed);
    final available = await fetchForumTasks(ForumTaskStatus.available);
    return _saveTaskSnapshotFromPages(
      inProgress: inProgress,
      completed: completed,
      available: available,
    );
  }

  Future<ForumTaskSnapshot> _saveTaskSnapshotFromPages({
    required List<ForumTask> inProgress,
    required List<ForumTask> completed,
    required List<ForumTask> available,
  }) async {
    final now = _nowUtc();
    final cooldownsByName = {
      for (final task in available)
        if (task.cooldownRemaining != null) task.name: task.cooldownRemaining!,
    };
    final snapshot = ForumTaskSnapshot(tasks: const [], updatedAt: now).merge([
      ...inProgress.map((task) => _taskStateFromTask(task, now: now)),
      ...completed.map(
        (task) => _taskStateFromTask(
          task,
          now: now,
          cooldownRemaining: cooldownsByName[task.name],
        ),
      ),
      ...available.map((task) => _taskStateFromTask(task, now: now)),
    ]);
    await _taskStateStore.save(snapshot);
    return snapshot;
  }

  Future<void> _updateTaskSnapshot(List<ForumTask> tasks) async {
    if (tasks.isEmpty) return;
    final current = await _taskStateStore.load();
    final base = current ??
        ForumTaskSnapshot(
          tasks: const [],
          updatedAt: _nowUtc(),
        );
    final now = _nowUtc();
    await _taskStateStore.save(
        base.merge(tasks.map((task) => _taskStateFromTask(task, now: now))));
  }

  ForumTaskState _taskStateFromTask(
    ForumTask task, {
    required DateTime now,
    Duration? cooldownRemaining,
  }) {
    final cooldown = cooldownRemaining ?? task.cooldownRemaining;
    return ForumTaskState(
      id: task.id,
      name: task.name,
      availability: _availabilityFromTask(task),
      reward: task.reward,
      spAmount: _spAmount(task.reward),
      progressPercent: task.progressPercent,
      completedAt: task.completedAt,
      cooldownRemaining: cooldown,
      nextAvailableAt:
          cooldown == null ? null : now.toUtc().add(cooldown).toUtc(),
    );
  }

  ForumTaskAvailability _availabilityFromTask(ForumTask task) {
    if (task.status == ForumTaskStatus.completed) {
      return ForumTaskAvailability.completed;
    }
    if (task.status == ForumTaskStatus.inProgress) {
      return _isClaimableForumTask(task)
          ? ForumTaskAvailability.claimable
          : ForumTaskAvailability.inProgress;
    }
    if (task.cooldownRemaining != null) {
      return ForumTaskAvailability.coolingDown;
    }
    if (task.canRun) return ForumTaskAvailability.available;
    return ForumTaskAvailability.unknown;
  }

  DateTime _nowUtc() => DateTime.now().toUtc();

  Set<String> _currentCycleCompletedNames(
    Iterable<ForumTask> tasks, {
    required DateTime now,
  }) {
    final names = <String>{};
    for (final task in tasks) {
      if (_isCurrentCycleCompletion(task, now: now)) names.add(task.name);
    }
    return names;
  }

  bool _isCurrentCycleCompletion(
    ForumTask task, {
    required DateTime now,
  }) {
    final cycle = _taskCycle(task.name);
    final completedAt = _parseForumTaskCompletedAt(task.completedAt);
    if (cycle == null || completedAt == null) return true;
    return completedAt.add(cycle).isAfter(now.toUtc());
  }

  Set<String> _targetTaskNames(Iterable<ForumTask> tasks) {
    final names = <String>{'日常', '周常'};
    for (final task in tasks) {
      if (task.name.contains('日常') || task.name.contains('周常')) {
        names.add(task.name);
      }
    }
    return names;
  }

  Future<List<BrowsingHistoryEntry>> browsingHistory({int limit = 100}) {
    return _historyStore.recent(limit: limit);
  }

  Future<void> clearBrowsingHistory() {
    return _historyStore.clear();
  }

  Future<List<ForumCategory>> fetchHotCategories() async {
    final home = await fetchHome();
    return home.hot;
  }

  Future<List<ForumSection>> fetchForumSections() async {
    final home = await fetchHome();
    return home.sections;
  }

  Future<List<ForumThread>> searchThreads(String keyword) async {
    final query = keyword.trim();
    if (query.isEmpty) return const [];

    final searchPage = html_parser.parse(await _client.get('search.php'));
    final form = searchPage.querySelector('form[action*="search.php"]') ??
        searchPage.querySelector('form');
    if (form == null) {
      throw const ForumRepositoryException('没有找到搜索表单');
    }

    final fields = _formParser.defaults(form)
      ..['step'] = '2'
      ..['keyword'] = query
      ..putIfAbsent('method', () => 'OR')
      ..putIfAbsent('sch_area', () => '0')
      ..putIfAbsent('f_fid', () => 'all')
      ..putIfAbsent('sch_time', () => '31536000')
      ..putIfAbsent('orderway', () => 'postdate')
      ..putIfAbsent('asc', () => 'DESC')
      ..['submit'] = '提 交';

    final action = form.attributes['action'] ?? 'search.php?';
    final response = await _client.post(
        _urls.relativePath(_urls.absoluteUrl(action)), fields);
    return _searchResultParser.parse(html_parser.parse(response));
  }

  Future<List<ForumThread>> fetchBoardThreads(ForumCategory category) async {
    return (await fetchBoardThreadPage(category)).threads;
  }

  Future<ForumThreadPage> fetchBoardThreadPage(
    ForumCategory category, {
    int page = 1,
  }) async {
    final normalizedPage = page < 1 ? 1 : page;
    final desktopPath = _urls.boardDesktopPath(category, page: normalizedPage);
    if (desktopPath == null) {
      throw ForumRepositoryException('没有解析到${category.name}帖子列表');
    }
    final desktopHtml = await _client.get(desktopPath);
    final desktopDocument = html_parser.parse(desktopHtml);
    final subBoards = _boardThreadPageParser.parseDesktopSubBoards(
      desktopDocument,
      category,
    );
    // thread_new.php uses the wall stream for ordinary topics, while the table
    // above it still carries board-level sticky topics and ads. Do not parse the
    // whole table as threads, because it also contains broader sticky levels
    // that simple mode intentionally hides.
    final threads = _mergeThreadNewThreads(
      _boardThreadPageParser.parseDesktopStickyThreads(
        desktopDocument,
        category,
      ),
      _boardThreadPageParser.parseWallThreads(desktopDocument, category),
    );
    if (threads.isNotEmpty) {
      final pages = _boardThreadPageParser.wallPages(desktopDocument) ??
          (current: normalizedPage, total: normalizedPage);
      return ForumThreadPage(
        threads: threads,
        currentPage: pages.current,
        totalPages: pages.total,
        ads: _boardThreadPageParser.parseDesktopAds(desktopDocument),
        subBoards: subBoards,
      );
    }

    if (subBoards.isNotEmpty) {
      return ForumThreadPage(
        threads: const [],
        currentPage: normalizedPage,
        totalPages: normalizedPage,
        ads: _boardThreadPageParser.parseDesktopAds(desktopDocument),
        subBoards: subBoards,
      );
    }

    throw ForumRepositoryException('没有解析到${category.name}帖子列表');
  }

  List<ForumThread> _mergeThreadNewThreads(
    List<ForumThread> stickyThreads,
    List<ForumThread> wallThreads,
  ) {
    final seen = <String>{};
    return [
      for (final thread in [...stickyThreads, ...wallThreads])
        if (seen.add(thread.url)) thread,
    ];
  }

  Future<ReplyResult> submitThread({
    required ForumCategory category,
    required String title,
    required String content,
  }) async {
    final trimmedTitle = title.trim();
    final trimmedContent = content.trim();
    if (trimmedTitle.isEmpty) {
      return const ReplyResult(success: false, message: '标题不能为空');
    }
    if (trimmedContent.isEmpty) {
      return const ReplyResult(success: false, message: '正文不能为空');
    }

    final fid = _urls.fidFromCategory(category);
    if (fid == null) {
      return const ReplyResult(success: false, message: '没有找到版块 ID');
    }

    final html = await _client.get('post.php?fid=$fid');
    final document = html_parser.parse(html);
    final form = document.querySelector('form[name="FORM"]');
    if (form == null) {
      return ReplyResult(
          success: false, message: _responseParser.pageMessage(html));
    }

    final fields = _formParser.defaults(form)
      ..['atc_title'] = trimmedTitle
      ..['atc_content'] = trimmedContent
      ..['Submit'] = '提 交';

    final action = form.attributes['action'] ?? 'post.php?';
    final response = await _client.post(
        _urls.relativePath(_urls.absoluteUrl(action)), fields);
    final message = _responseParser.pageMessage(response);
    final success = _responseParser.isReplySuccess(response, message);
    return ReplyResult(
      success: success,
      message: success ? '主题已发布' : message,
    );
  }

  Future<UserProfile> fetchUserProfile(String url) async {
    final overview = await fetchUserProfileOverview(url);
    return fetchUserProfileDetails(overview);
  }

  Future<UserProfile> fetchUserProfileOverview(String url) async {
    final profileUrl = _urls.absoluteUrl(url);
    final uid = await _uidFromProfileUrl(profileUrl);
    final profileDocument = html_parser.parse(
      await _client.get(
        _urls.relativePath(_urls.userTabUrl(uid, UserProfileTab.profile)),
      ),
    );
    final profile = _userProfileParser.parseOverview(
      uid: uid,
      profileUrl: profileUrl,
      profileDocument: profileDocument,
    );
    await _profileCache.saveOverview(url, profile);
    return profile;
  }

  Future<UserProfile?> cachedUserProfileOverview(String url) async {
    return _profileCache.loadOverview(url);
  }

  Future<UserProfile> fetchUserProfileDetails(UserProfile overview) async {
    final uid = overview.uid;
    final documents = await Future.wait([
      _client
          .get(_urls.relativePath(_urls.userTabUrl(uid, UserProfileTab.home))),
      _client.get(
          _urls.relativePath(_urls.userTabUrl(uid, UserProfileTab.topics))),
      _client
          .get(_urls.relativePath(_urls.userTabUrl(uid, UserProfileTab.posts))),
      _client.get(
          _urls.relativePath(_urls.userTabUrl(uid, UserProfileTab.favorites))),
    ]);
    return _userProfileParser.appendDetails(
      overview: overview,
      homeDocument: html_parser.parse(documents[0]),
      topicsDocument: html_parser.parse(documents[1]),
      postsDocument: html_parser.parse(documents[2]),
      favoritesDocument: html_parser.parse(documents[3]),
    );
  }

  Future<String> _uidFromProfileUrl(String profileUrl) async {
    var uid = _urls.uidFromUrl(profileUrl);
    if (uid == null) {
      final html = await _client.get(_urls.relativePath(profileUrl));
      uid = _userProfileParser.uidFromDocument(html_parser.parse(html));
    }
    if (uid == null) {
      throw const ForumRepositoryException('没有找到用户 UID');
    }
    return uid;
  }

  Future<ThreadDetail> fetchThreadDetail(
    ForumThread thread, {
    int page = 1,
  }) async {
    final normalizedPage = page < 1 ? 1 : page;
    final detailPath = _urls.threadDetailPath(thread.url, page: normalizedPage);
    final html = await _client.get(detailPath);
    final document = html_parser.parse(html);
    final favorite = await _extractThreadFavorite(thread, html);
    final posts = _threadDetailParser.desktopThreadCards(document);
    final pagination = _threadDetailParser.desktopPagination(
      document,
      requestedPage: normalizedPage,
    );
    final section = _threadDetailParser.sectionTitle(document);

    if (posts.isEmpty) {
      throw ForumRepositoryException(_responseParser.pageMessage(html));
    }

    final isOpeningPage = pagination.currentPage == 1;
    final first = isOpeningPage ? posts.first : null;
    final detailThread = thread.copyWith(
      title: _threadDetailParser.threadTitle(document) ?? thread.title,
      url: _canonicalThreadUrl(
        parserUrl: _threadDetailParser.threadUrl(document),
        sourceUrl: thread.url,
        detailPath: detailPath,
      ),
      section: section ?? thread.section,
      author: first?.author,
      authorUrl: first?.authorUrl,
      authorAvatarUrl: first?.authorAvatarUrl,
      authorPostsUrl: first?.authorPostsUrl,
      lastPost: first?.postedAt ?? thread.lastPost,
    );

    final detail = ThreadDetail(
      thread: detailThread,
      body: first?.content ?? '',
      bodyImages: first?.images ?? const [],
      bodyLinks: first?.links ?? const [],
      bodySegments: first?.segments ?? const [],
      bodySaleBoxes: first?.saleBoxes ?? const [],
      bodySaleBoxesFirst: first?.saleBoxesFirst ?? false,
      replies: isOpeningPage ? posts.skip(1).toList() : posts,
      pagination: pagination,
      favorite: favorite,
      previousThread: _threadDetailParser.previousThread(document),
      nextThread: _threadDetailParser.nextThread(document),
      rssFeed: _threadDetailParser.rssFeed(document),
    );
    await _recordThreadView(detail.thread);
    return detail;
  }

  Future<String?> fetchQuoteDraft(ThreadReply reply) async {
    final quoteUrl = reply.quoteUrl;
    if (quoteUrl == null || quoteUrl.isEmpty) return null;

    final html = await _client.get(
      _urls.relativePath(_urls.absoluteUrl(quoteUrl)),
    );
    final document = html_parser.parse(html);
    final form = document.querySelector('form[name="FORM"]') ??
        document.querySelector('form[action*="post.php"]');
    final textarea = form?.querySelector('textarea[name="atc_content"]') ??
        document.querySelector('textarea[name="atc_content"]');
    final content = textarea?.text.trim();
    if (content != null && content.isNotEmpty) return content;

    final input = form?.querySelector('input[name="atc_content"]') ??
        document.querySelector('input[name="atc_content"]');
    final value = input?.attributes['value']?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  Future<ReplyResult> submitReply({
    required ForumThread thread,
    required String title,
    required String content,
  }) async {
    if (content.trim().isEmpty) {
      return const ReplyResult(success: false, message: '回复内容不能为空');
    }

    final html = await _client.get(_urls.relativePath(thread.url));
    final document = html_parser.parse(html);
    final form = document.querySelector('form[name="FORM"]');
    if (form == null) {
      return ReplyResult(
          success: false, message: _responseParser.pageMessage(html));
    }

    final fields = _formParser.defaults(form)
      ..['atc_title'] =
          title.trim().isEmpty ? 'Re:${thread.title}' : title.trim()
      ..['atc_content'] = content.trim()
      ..['Submit'] = ' 提 交 ';

    final action = form.attributes['action'] ?? 'post.php?';
    final response = await _client.post(
        _urls.relativePath(_urls.absoluteUrl(action)), fields);
    final message = _responseParser.pageMessage(response);
    final success = _responseParser.isReplySuccess(response, message);
    return ReplyResult(
      success: success,
      message: success ? '回复已提交' : message,
    );
  }

  Future<ReplyResult> buySaleBox(ThreadSaleBox saleBox) async {
    if (saleBox.buyPath.trim().isEmpty) {
      return const ReplyResult(success: false, message: '没有找到购买链接');
    }

    final response = await _client
        .get(_urls.relativePath(_urls.absoluteUrl(saleBox.buyPath)));
    final message = _responseParser.pageMessage(response);
    final success = _responseParser.isPurchaseSuccess(response, message);
    return ReplyResult(
      success: success,
      message: success ? '购买完成' : message,
    );
  }

  Future<FavoriteResult> addFavorite(ThreadFavorite favorite) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final response = await _client.get(
      'pw_ajax.php?action=favor&tid=${favorite.tid}&nowtime=$now&verify=${favorite.verify}',
    );
    final message = _responseParser.ajaxMessage(response);
    final success = _responseParser.isFavoriteAddSuccess(message);
    return FavoriteResult(
      success: success,
      message: success ? '已收藏该主题' : message,
      state: success ? ThreadFavoriteState.favorite : favorite.state,
    );
  }

  Future<FavoriteResult> removeFavorite(ThreadFavorite favorite) async {
    final currentState = await _fetchFavoriteState(favorite.tid);
    if (currentState == ThreadFavoriteState.notFavorite) {
      return const FavoriteResult(
        success: true,
        message: '当前没有收藏该主题',
        state: ThreadFavoriteState.notFavorite,
      );
    }

    final response = await _client.post('u.php?action=favor&', {
      'verify': favorite.verify,
      'selid[]': favorite.tid,
      'job': 'clear',
      'type': '0',
    });
    final message = _responseParser.pageMessage(response);
    final success = _responseParser.isFavoriteRemoveSuccess(response, message);
    return FavoriteResult(
      success: success,
      message: success ? '已取消收藏' : message,
      state: success ? ThreadFavoriteState.notFavorite : favorite.state,
    );
  }

  Future<String?> _fetchLoggedInUsername() async {
    try {
      return _responseParser.loggedInUsername(await _client.get('index.php')) ??
          _responseParser
              .loggedInUsername(await _client.get('simple/index.php'));
    } catch (_) {
      return null;
    }
  }

  Future<ThreadFavorite?> _extractThreadFavorite(
    ForumThread thread,
    String html,
  ) async {
    var favorite = _threadFavoriteFromHtml(thread, html);
    if (favorite != null) {
      if (favorite.state == ThreadFavoriteState.unknown) {
        return favorite.copyWith(
          state: await _fetchFavoriteState(favorite.tid),
        );
      }
      return favorite;
    }
    return null;
  }

  ThreadFavorite? _threadFavoriteFromHtml(ForumThread thread, String html) {
    final tid = _urls.tidFromUrl(thread.url);
    if (tid == null) return null;

    final verify =
        RegExp(r"verifyhash\s*=\s*'([^']+)'").firstMatch(html)?.group(1);
    if (verify == null || verify.isEmpty) return null;

    final document = html_parser.parse(html);
    final favoriteButton = document.querySelector('#favor');
    final text = _cleanText(favoriteButton?.text ?? '');
    final state = text.contains('取消收藏')
        ? ThreadFavoriteState.favorite
        : ThreadFavoriteState.unknown;
    return ThreadFavorite(
      tid: tid,
      verify: verify,
      state: state,
    );
  }

  Future<ThreadFavoriteState> _fetchFavoriteState(String tid) async {
    try {
      final html = await _client.get('u.php?action-favor.html');
      final document = html_parser.parse(html);
      final favoriteForm =
          document.querySelector('form[action*="action=favor"]');
      if (favoriteForm == null) return ThreadFavoriteState.unknown;

      final escapedTid = RegExp.escape(tid);
      final item = favoriteForm.querySelector(
        'input[type="checkbox"][name="selid[]"][value="$escapedTid"]',
      );
      if (item != null) return ThreadFavoriteState.favorite;

      return ThreadFavoriteState.unknown;
    } catch (_) {
      return ThreadFavoriteState.unknown;
    }
  }

  String _cleanText(String input) {
    return input.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  Duration? _taskCycle(String name) {
    if (name.contains('日常')) return const Duration(hours: 24);
    if (name.contains('周常')) return const Duration(hours: 168);
    return null;
  }

  DateTime? _parseForumTaskCompletedAt(String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty) return null;
    final match = RegExp(
      r'(\d{4})-(\d{2})-(\d{2})\s+(AM|PM):(\d{1,2}):(\d{2}):(\d{2})',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return DateTime.tryParse(text)?.toUtc();
    final year = int.tryParse(match.group(1) ?? '');
    final month = int.tryParse(match.group(2) ?? '');
    final day = int.tryParse(match.group(3) ?? '');
    var hour = int.tryParse(match.group(5) ?? '');
    final minute = int.tryParse(match.group(6) ?? '');
    final second = int.tryParse(match.group(7) ?? '');
    if (year == null ||
        month == null ||
        day == null ||
        hour == null ||
        minute == null ||
        second == null) {
      return null;
    }
    final marker = (match.group(4) ?? '').toUpperCase();
    if (marker == 'PM' && hour < 12) hour += 12;
    if (marker == 'AM' && hour == 12) hour = 0;
    return DateTime(year, month, day, hour, minute, second).toUtc();
  }

  String _canonicalThreadUrl({
    required String? parserUrl,
    required String sourceUrl,
    required String detailPath,
  }) {
    final parsed = parserUrl;
    if (parsed != null && parsed.isNotEmpty) return parsed;

    final tid = _urls.tidFromUrl(sourceUrl);
    if (tid != null) {
      return _urls.absoluteUrl('read.php?tid-$tid.html');
    }
    return _urls.absoluteUrl(detailPath);
  }

  Future<void> _recordThreadView(ForumThread thread) async {
    try {
      await _historyStore.recordThread(thread);
    } catch (_) {
      // Browsing must keep working even if local history persistence fails.
    }
  }

  dom.Element? _loginFormFromFields(dom.Document document) {
    for (final form in document.querySelectorAll('form')) {
      if (form.querySelector('input[name="pwuser"]') != null &&
          form.querySelector('input[name="pwpwd"]') != null) {
        return form;
      }
    }
    return null;
  }
}

class ForumRepositoryException implements Exception {
  const ForumRepositoryException(this.message);

  final String message;

  @override
  String toString() => message;
}

enum _ForumTaskActionExpectation {
  start,
  claimReward,
}

enum _ForumTaskActionKind {
  started,
  rewardClaimed,
  alreadyStarted,
  alreadyCompleted,
  coolingDown,
  loginRequired,
  failure,
}

class _ForumTaskActionDecision {
  const _ForumTaskActionDecision(this.kind, this.message);

  final _ForumTaskActionKind kind;
  final String message;
}
