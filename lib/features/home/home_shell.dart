import 'package:flutter/material.dart';

import '../../models/forum_models.dart';
import '../../services/forum_repository.dart';
import '../../theme/app_theme.dart';
import '../auth/login_screen.dart';
import '../board/board_thread_list_screen.dart';
import '../profile/user_profile_screen.dart';
import '../search/search_screen.dart';
import '../thread/thread_detail_screen.dart';

part 'home_widgets.dart';

class HomeShell extends StatelessWidget {
  const HomeShell({super.key, ForumRepository? repository})
      : repository = repository;

  final ForumRepository? repository;

  @override
  Widget build(BuildContext context) {
    return ForumHomePage(repository: repository ?? ForumRepository());
  }
}

class ForumHomePage extends StatefulWidget {
  const ForumHomePage({super.key, required this.repository});

  final ForumRepository repository;

  @override
  State<ForumHomePage> createState() => _ForumHomePageState();
}

class _ForumHomePageState extends State<ForumHomePage> {
  late Future<ForumHomeSnapshot> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.repository.fetchHome();
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.repository.fetchHome());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<ForumHomeSnapshot>(
          future: _future,
          builder: (context, snapshot) {
            final data = snapshot.data;
            return RefreshIndicator(
              color: AppColors.brand,
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 20),
                children: [
                  _TopBar(repository: widget.repository),
                  if (snapshot.hasError)
                    _LoadError(
                      title: '主页加载失败',
                      message: '${snapshot.error}',
                      onRetry: _refresh,
                    )
                  else if (data == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 96),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else ...[
                    _ForumCrumbs(
                      items: const ['南+', 'South Plus', '茶馆'],
                      current: '移动端首页',
                    ),
                    _BoardOverview(
                      sections: data.sections.length,
                      hot: data.hot.length,
                      latest: data.latest.length,
                    ),
                    _LatestThreads(
                      threads: data.latest,
                      repository: widget.repository,
                    ),
                    const SizedBox(height: 14),
                    _ForumGroup(
                      title: '热门版块',
                      icon: Icons.local_fire_department_outlined,
                      children: data.hot
                          .map(
                            (category) => _ForumLink(
                              title: category.name,
                              subtitle: category.slug,
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => BoardThreadListScreen(
                                    category: category,
                                    repository: widget.repository,
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    ...data.sections.map(
                      (section) => _ForumGroup(
                        title: section.title,
                        initiallyExpanded: false,
                        children: section.items
                            .map(
                              (item) => _ForumLink(
                                title: item.title,
                                subtitle: item.section,
                              ),
                            )
                            .toList(),
                      ),
                    ),
                    const _DesktopLink(),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
