import 'package:flutter/material.dart';

import '../common/cached_forum_image.dart';
import '../common/forum_emoji_assets.dart';
import '../../theme/app_theme.dart';

class SouthPlusEmojiPicker extends StatelessWidget {
  const SouthPlusEmojiPicker({
    super.key,
    required this.onSelected,
    this.baseUri,
  });

  final ValueChanged<SouthPlusEmoji> onSelected;
  final Uri? baseUri;

  String get _emojiBaseUrl =>
      (baseUri ?? Uri.https('south-plus.net', '/')).toString();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _emojiCategories.length,
      child: SafeArea(
        child: SizedBox(
          height: 430,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  '表情',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: '小圆脸'),
                  Tab(text: '´･ω･`'),
                  Tab(text: '顔アニ'),
                  Tab(text: '顔文字'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: _emojiCategories
                      .map(
                        (category) => GridView.builder(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 18),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 48,
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                          itemCount: category.items.length,
                          itemBuilder: (context, index) {
                            final emoji = category.items[index];
                            return Tooltip(
                              message: '[s:${emoji.id}]',
                              child: InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () => onSelected(emoji),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: AppColors.border,
                                    ),
                                    color: AppColors.surface,
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(5),
                                    child: CachedForumImage(
                                      url: emoji.urlFromBase(_emojiBaseUrl),
                                      assetName: forumEmojiAssetNameFromPath(
                                        emoji.path,
                                      ),
                                      fit: BoxFit.contain,
                                      bypassLoadPolicy: true,
                                      errorWidget: (context) {
                                        return Center(
                                          child: Text(
                                            emoji.id,
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: AppColors.textMuted,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SouthPlusEmoji {
  const SouthPlusEmoji(this.id, this.path);

  final String id;
  final String path;

  String get code => ' [s:$id] ';
  String urlFromBase(String baseUrl) => '$baseUrl$path';
}

class _EmojiCategory {
  const _EmojiCategory(this.items);

  final List<SouthPlusEmoji> items;
}

const _emojiCategories = [
  _EmojiCategory([
    SouthPlusEmoji('718', 'images/post/smile/smallface/face077.gif'),
    SouthPlusEmoji('703', 'images/post/smile/smallface/face040.jpg'),
    SouthPlusEmoji('702', 'images/post/smile/smallface/face047.jpg'),
    SouthPlusEmoji('701', 'images/post/smile/smallface/face106.gif'),
    SouthPlusEmoji('700', 'images/post/smile/smallface/face002.jpg'),
    SouthPlusEmoji('699', 'images/post/smile/smallface/face111.jpg'),
    SouthPlusEmoji('698', 'images/post/smile/smallface/face030.jpg'),
    SouthPlusEmoji('697', 'images/post/smile/smallface/face064.jpg'),
    SouthPlusEmoji('696', 'images/post/smile/smallface/face059.jpg'),
    SouthPlusEmoji('695', 'images/post/smile/smallface/face075.jpg'),
    SouthPlusEmoji('694', 'images/post/smile/smallface/face084.jpg'),
    SouthPlusEmoji('693', 'images/post/smile/smallface/face056.jpg'),
    SouthPlusEmoji('692', 'images/post/smile/smallface/face068.gif'),
    SouthPlusEmoji('704', 'images/post/smile/smallface/face076.jpg'),
    SouthPlusEmoji('705', 'images/post/smile/smallface/face027.jpg'),
    SouthPlusEmoji('717', 'images/post/smile/smallface/face108.jpg'),
    SouthPlusEmoji('716', 'images/post/smile/smallface/face113.jpg'),
    SouthPlusEmoji('715', 'images/post/smile/smallface/face020.jpg'),
    SouthPlusEmoji('714', 'images/post/smile/smallface/face091.gif'),
    SouthPlusEmoji('713', 'images/post/smile/smallface/face026.jpg'),
    SouthPlusEmoji('712', 'images/post/smile/smallface/face096.jpg'),
    SouthPlusEmoji('711', 'images/post/smile/smallface/face009.jpg'),
    SouthPlusEmoji('710', 'images/post/smile/smallface/face073.jpg'),
    SouthPlusEmoji('709', 'images/post/smile/smallface/face034.jpg'),
    SouthPlusEmoji('708', 'images/post/smile/smallface/face032.jpg'),
    SouthPlusEmoji('707', 'images/post/smile/smallface/face003.jpg'),
    SouthPlusEmoji('706', 'images/post/smile/smallface/face095.gif'),
    SouthPlusEmoji('691', 'images/post/smile/smallface/face070.gif'),
    SouthPlusEmoji('690', 'images/post/smile/smallface/face093.jpg'),
    SouthPlusEmoji('689', 'images/post/smile/smallface/face043.jpg'),
    SouthPlusEmoji('739', 'images/post/smile/smallface/face101.jpg'),
    SouthPlusEmoji('740', 'images/post/smile/smallface/face017.jpg'),
    SouthPlusEmoji('741', 'images/post/smile/smallface/face029.jpg'),
    SouthPlusEmoji('742', 'images/post/smile/smallface/face008.jpg'),
  ]),
  _EmojiCategory([
    SouthPlusEmoji('752', 'images/post/smile/miao/030.png'),
    SouthPlusEmoji('770', 'images/post/smile/miao/029.png'),
    SouthPlusEmoji('771', 'images/post/smile/miao/05.png'),
    SouthPlusEmoji('772', 'images/post/smile/miao/06.png'),
    SouthPlusEmoji('773', 'images/post/smile/miao/032.png'),
    SouthPlusEmoji('774', 'images/post/smile/miao/09.png'),
    SouthPlusEmoji('775', 'images/post/smile/miao/022.png'),
    SouthPlusEmoji('776', 'images/post/smile/miao/031.png'),
    SouthPlusEmoji('777', 'images/post/smile/miao/034.png'),
    SouthPlusEmoji('778', 'images/post/smile/miao/027.png'),
    SouthPlusEmoji('779', 'images/post/smile/miao/023.jpg'),
    SouthPlusEmoji('780', 'images/post/smile/miao/03.png'),
    SouthPlusEmoji('781', 'images/post/smile/miao/021.png'),
    SouthPlusEmoji('782', 'images/post/smile/miao/033.png'),
    SouthPlusEmoji('783', 'images/post/smile/miao/016.png'),
    SouthPlusEmoji('784', 'images/post/smile/miao/020.png'),
    SouthPlusEmoji('769', 'images/post/smile/miao/012.png'),
    SouthPlusEmoji('768', 'images/post/smile/miao/02.png'),
    SouthPlusEmoji('753', 'images/post/smile/miao/011.png'),
    SouthPlusEmoji('754', 'images/post/smile/miao/015.png'),
    SouthPlusEmoji('755', 'images/post/smile/miao/010.png'),
    SouthPlusEmoji('756', 'images/post/smile/miao/014.png'),
    SouthPlusEmoji('757', 'images/post/smile/miao/018.png'),
    SouthPlusEmoji('758', 'images/post/smile/miao/01.png'),
    SouthPlusEmoji('759', 'images/post/smile/miao/025.png'),
    SouthPlusEmoji('760', 'images/post/smile/miao/04.png'),
    SouthPlusEmoji('761', 'images/post/smile/miao/026.png'),
    SouthPlusEmoji('762', 'images/post/smile/miao/013.png'),
    SouthPlusEmoji('763', 'images/post/smile/miao/028.png'),
    SouthPlusEmoji('764', 'images/post/smile/miao/024.gif'),
    SouthPlusEmoji('765', 'images/post/smile/miao/07.png'),
    SouthPlusEmoji('766', 'images/post/smile/miao/08.png'),
    SouthPlusEmoji('767', 'images/post/smile/miao/019.png'),
    SouthPlusEmoji('785', 'images/post/smile/miao/017.png'),
  ]),
  _EmojiCategory([
    SouthPlusEmoji('260', 'images/post/smile/kaoani/fly_03.gif'),
    SouthPlusEmoji('243', 'images/post/smile/kaoani/fly_55.gif'),
    SouthPlusEmoji('242', 'images/post/smile/kaoani/fly_05.gif'),
    SouthPlusEmoji('241', 'images/post/smile/kaoani/fly_14.gif'),
    SouthPlusEmoji('239', 'images/post/smile/kaoani/fly_07.gif'),
    SouthPlusEmoji('238', 'images/post/smile/kaoani/fly_01.gif'),
    SouthPlusEmoji('237', 'images/post/smile/kaoani/fly_24.gif'),
    SouthPlusEmoji('236', 'images/post/smile/kaoani/fly_20.gif'),
    SouthPlusEmoji('235', 'images/post/smile/kaoani/fly_31.gif'),
    SouthPlusEmoji('234', 'images/post/smile/kaoani/fly_06.gif'),
    SouthPlusEmoji('232', 'images/post/smile/kaoani/fly_08.gif'),
    SouthPlusEmoji('231', 'images/post/smile/kaoani/fly_56.gif'),
    SouthPlusEmoji('230', 'images/post/smile/kaoani/fly_41.gif'),
    SouthPlusEmoji('244', 'images/post/smile/kaoani/fly_38.gif'),
    SouthPlusEmoji('246', 'images/post/smile/kaoani/fly_02.gif'),
    SouthPlusEmoji('259', 'images/post/smile/kaoani/fly_33.gif'),
    SouthPlusEmoji('258', 'images/post/smile/kaoani/fly_34.gif'),
    SouthPlusEmoji('257', 'images/post/smile/kaoani/fly_43.gif'),
    SouthPlusEmoji('256', 'images/post/smile/kaoani/fly_99.gif'),
    SouthPlusEmoji('255', 'images/post/smile/kaoani/fly_51.gif'),
    SouthPlusEmoji('254', 'images/post/smile/kaoani/fly_44.gif'),
    SouthPlusEmoji('253', 'images/post/smile/kaoani/fly_21.gif'),
    SouthPlusEmoji('252', 'images/post/smile/kaoani/fly_15.gif'),
    SouthPlusEmoji('251', 'images/post/smile/kaoani/fly_45.gif'),
    SouthPlusEmoji('250', 'images/post/smile/kaoani/fly_29.gif'),
    SouthPlusEmoji('249', 'images/post/smile/kaoani/fly_22.gif'),
    SouthPlusEmoji('247', 'images/post/smile/kaoani/fly_10.gif'),
    SouthPlusEmoji('229', 'images/post/smile/kaoani/fly_49.gif'),
    SouthPlusEmoji('228', 'images/post/smile/kaoani/fly_09.gif'),
    SouthPlusEmoji('211', 'images/post/smile/kaoani/fly_54.gif'),
    SouthPlusEmoji('210', 'images/post/smile/kaoani/fly_26.gif'),
    SouthPlusEmoji('209', 'images/post/smile/kaoani/fly_47.gif'),
    SouthPlusEmoji('208', 'images/post/smile/kaoani/fly_11.gif'),
    SouthPlusEmoji('207', 'images/post/smile/kaoani/fly_46.gif'),
    SouthPlusEmoji('206', 'images/post/smile/kaoani/fly_57.gif'),
    SouthPlusEmoji('204', 'images/post/smile/kaoani/fly_12.gif'),
    SouthPlusEmoji('203', 'images/post/smile/kaoani/fly_37.gif'),
    SouthPlusEmoji('202', 'images/post/smile/kaoani/fly_35.gif'),
    SouthPlusEmoji('201', 'images/post/smile/kaoani/fly_40.gif'),
    SouthPlusEmoji('200', 'images/post/smile/kaoani/fly_18.gif'),
    SouthPlusEmoji('199', 'images/post/smile/kaoani/fly_53.gif'),
    SouthPlusEmoji('212', 'images/post/smile/kaoani/fly_19.gif'),
    SouthPlusEmoji('213', 'images/post/smile/kaoani/fly_28.gif'),
    SouthPlusEmoji('226', 'images/post/smile/kaoani/fly_16.gif'),
    SouthPlusEmoji('225', 'images/post/smile/kaoani/fly_27.gif'),
    SouthPlusEmoji('224', 'images/post/smile/kaoani/fly_59.gif'),
    SouthPlusEmoji('223', 'images/post/smile/kaoani/fly_36.gif'),
    SouthPlusEmoji('221', 'images/post/smile/kaoani/fly_48.gif'),
    SouthPlusEmoji('220', 'images/post/smile/kaoani/fly_32.gif'),
    SouthPlusEmoji('219', 'images/post/smile/kaoani/fly_39.gif'),
    SouthPlusEmoji('218', 'images/post/smile/kaoani/fly_17.gif'),
    SouthPlusEmoji('217', 'images/post/smile/kaoani/fly_42.gif'),
    SouthPlusEmoji('216', 'images/post/smile/kaoani/fly_50.gif'),
    SouthPlusEmoji('215', 'images/post/smile/kaoani/fly_52.gif'),
    SouthPlusEmoji('214', 'images/post/smile/kaoani/fly_23.gif'),
    SouthPlusEmoji('198', 'images/post/smile/kaoani/fly_58.gif'),
  ]),
  _EmojiCategory([
    SouthPlusEmoji('497', 'images/post/smile/kaomoji/43.gif'),
    SouthPlusEmoji('483', 'images/post/smile/kaomoji/10.gif'),
    SouthPlusEmoji('482', 'images/post/smile/kaomoji/29.gif'),
    SouthPlusEmoji('481', 'images/post/smile/kaomoji/30.gif'),
    SouthPlusEmoji('480', 'images/post/smile/kaomoji/4.gif'),
    SouthPlusEmoji('479', 'images/post/smile/kaomoji/34.gif'),
    SouthPlusEmoji('478', 'images/post/smile/kaomoji/35.gif'),
    SouthPlusEmoji('477', 'images/post/smile/kaomoji/48.gif'),
    SouthPlusEmoji('476', 'images/post/smile/kaomoji/16.gif'),
    SouthPlusEmoji('475', 'images/post/smile/kaomoji/31.gif'),
    SouthPlusEmoji('474', 'images/post/smile/kaomoji/40.gif'),
    SouthPlusEmoji('484', 'images/post/smile/kaomoji/6.gif'),
    SouthPlusEmoji('485', 'images/post/smile/kaomoji/8.gif'),
    SouthPlusEmoji('486', 'images/post/smile/kaomoji/15.gif'),
    SouthPlusEmoji('496', 'images/post/smile/kaomoji/41.gif'),
    SouthPlusEmoji('495', 'images/post/smile/kaomoji/13.gif'),
    SouthPlusEmoji('494', 'images/post/smile/kaomoji/44.gif'),
    SouthPlusEmoji('493', 'images/post/smile/kaomoji/36.gif'),
    SouthPlusEmoji('492', 'images/post/smile/kaomoji/23.gif'),
    SouthPlusEmoji('491', 'images/post/smile/kaomoji/5.gif'),
    SouthPlusEmoji('490', 'images/post/smile/kaomoji/17.gif'),
    SouthPlusEmoji('489', 'images/post/smile/kaomoji/1.gif'),
    SouthPlusEmoji('488', 'images/post/smile/kaomoji/38.gif'),
    SouthPlusEmoji('487', 'images/post/smile/kaomoji/49.gif'),
    SouthPlusEmoji('473', 'images/post/smile/kaomoji/37.gif'),
    SouthPlusEmoji('472', 'images/post/smile/kaomoji/46.gif'),
    SouthPlusEmoji('458', 'images/post/smile/kaomoji/26.gif'),
    SouthPlusEmoji('457', 'images/post/smile/kaomoji/21.gif'),
    SouthPlusEmoji('456', 'images/post/smile/kaomoji/3.gif'),
    SouthPlusEmoji('455', 'images/post/smile/kaomoji/9.gif'),
    SouthPlusEmoji('454', 'images/post/smile/kaomoji/25.gif'),
    SouthPlusEmoji('453', 'images/post/smile/kaomoji/42.gif'),
    SouthPlusEmoji('452', 'images/post/smile/kaomoji/12.gif'),
    SouthPlusEmoji('451', 'images/post/smile/kaomoji/28.gif'),
    SouthPlusEmoji('450', 'images/post/smile/kaomoji/22.gif'),
    SouthPlusEmoji('449', 'images/post/smile/kaomoji/27.gif'),
    SouthPlusEmoji('459', 'images/post/smile/kaomoji/7.gif'),
    SouthPlusEmoji('460', 'images/post/smile/kaomoji/39.gif'),
    SouthPlusEmoji('461', 'images/post/smile/kaomoji/47.gif'),
    SouthPlusEmoji('471', 'images/post/smile/kaomoji/50.gif'),
    SouthPlusEmoji('470', 'images/post/smile/kaomoji/11.gif'),
    SouthPlusEmoji('469', 'images/post/smile/kaomoji/19.gif'),
    SouthPlusEmoji('468', 'images/post/smile/kaomoji/32.gif'),
    SouthPlusEmoji('467', 'images/post/smile/kaomoji/2.gif'),
    SouthPlusEmoji('466', 'images/post/smile/kaomoji/45.gif'),
    SouthPlusEmoji('465', 'images/post/smile/kaomoji/18.gif'),
    SouthPlusEmoji('464', 'images/post/smile/kaomoji/20.gif'),
    SouthPlusEmoji('463', 'images/post/smile/kaomoji/24.gif'),
    SouthPlusEmoji('462', 'images/post/smile/kaomoji/33.gif'),
    SouthPlusEmoji('448', 'images/post/smile/kaomoji/14.gif'),
  ]),
];
