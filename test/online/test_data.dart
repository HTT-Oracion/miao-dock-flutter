import 'package:miao_dock_flutter/features/manga/online/domain/online_download.dart';
import 'package:miao_dock_flutter/features/manga/online/domain/online_models.dart';
import 'package:miao_dock_flutter/features/manga/online/domain/online_source.dart';
import 'package:miao_dock_flutter/features/manga/online/domain/source_manifest.dart';

/// 在线漫画的离线演示数据。
///
/// 设计稿的封面是语义化渐变 + 书名占位，数据来自 manhuagui 的合成样本；
/// 这里用同构数据把「多源 / 首页 / 分类 / 搜索 / 详情 / 阅读 / 下载 / 翻译」
/// 全链路点亮，**不请求真实网络**。接入 QuickJS 引擎后由源返回真实数据。
abstract final class OnlineTestData {
  static const longStripComics = <OnlineComic>[
    OnlineComic(
      id: 'kimetsu',
      title: '鬼灭之刃',
      coverTone: CoverTone.red,
      author: '吾峠呼世晴',
      tags: ['热血', '冒险', '奇幻'],
      description: '时值日本大正时期。卖炭少年炭治郎，某天家人惨遭鬼杀害，而唯一幸存下来的妹妹祢豆子亦变成鬼。为了让妹妹变回人类、并为家人报仇，他踏上了「鬼杀队」的修行之路。',
      status: ComicStatus.ongoing,
      chapterCount: 235,
      latestChapter: '第206话',
      badge: '更新',
    ),
    OnlineComic(
      id: 'inou',
      title: '日常系的异能战斗',
      coverTone: CoverTone.blue,
      author: '望公太',
      tags: ['校园', '奇幻', '日常'],
      description: '安藤寿来突然觉醒了「黑焰」——但社团里的其他人也各有异能。日常与非日常交错的异能战斗喜剧，从一场中二病式的觉醒开始。',
      status: ComicStatus.ongoing,
      chapterCount: 19,
      latestChapter: '第19话',
      badge: '更新',
    ),
    OnlineComic(
      id: 'onepiece',
      title: '海贼王',
      coverTone: CoverTone.orange,
      author: '尾田荣一郎',
      tags: ['热血', '冒险', '格斗'],
      description: '财富、名声、权力，得到这一切的男人——海贼王哥尔·D·罗杰。他在临刑前留下的一句话，让全世界的人都奔向大海：「想要我的财宝吗？想要的话可以全部给你，去找吧！」',
      status: ComicStatus.ongoing,
      chapterCount: 1124,
      latestChapter: '第1124话',
    ),
    OnlineComic(
      id: 'aot',
      title: '进击的巨人',
      coverTone: CoverTone.olive,
      author: '谏山创',
      tags: ['热血', '悬疑', '奇幻'],
      description: '人类曾一度因巨人的出现而濒临灭绝。残存的人类筑起三重巨大的城墙，在墙内过了一百年的和平生活。直到那一天，超大型巨人踏破了城墙。',
      status: ComicStatus.completed,
      chapterCount: 139,
      latestChapter: '第139话',
    ),
    OnlineComic(
      id: 'opm',
      title: '一拳超人',
      coverTone: CoverTone.gold,
      author: 'ONE / 村田雄介',
      tags: ['热血', '格斗', '搞笑'],
      description: '因兴趣而成为英雄的埼玉，经过三年特训后变得过于强大——无论多么强大的敌人，都能一拳解决。英雄协会的日常，从此变得有点无聊。',
      status: ComicStatus.ongoing,
      chapterCount: 251,
      latestChapter: '第251话',
    ),
    OnlineComic(
      id: 'jjk',
      title: '咒术回战',
      coverTone: CoverTone.purple,
      author: '芥见下下',
      tags: ['热血', '奇幻', '悬疑'],
      description: '虎杖悠仁吞下了特级咒物「两面宿傩的手指」，从此与诅咒之王共用一具身体。为了祓除诅咒，他进入东京都立咒术高等专门学校。',
      status: ComicStatus.completed,
      chapterCount: 271,
      latestChapter: '第271话',
    ),
    OnlineComic(
      id: 'spy',
      title: '间谍过家家',
      coverTone: CoverTone.teal,
      author: '远藤达哉',
      tags: ['搞笑', '日常', '悬疑'],
      description: '身手矫健的间谍「黄昏」，为了执行任务必须组建一个家庭。他领养了会读心的女儿，并与杀手身份的妻子契约结婚。三个人各怀秘密的伪装家庭生活开始了。',
      status: ComicStatus.ongoing,
      chapterCount: 109,
      latestChapter: '第109话',
    ),
    OnlineComic(
      id: 'frieren',
      title: '葬送的芙莉莲',
      coverTone: CoverTone.steel,
      author: '山田钟人 / 阿部司',
      tags: ['奇幻', '冒险', '日常'],
      description: '勇者一行打倒了魔王，世界恢复了和平。作为精灵魔法使的芙莉莲，寿命远比同伴漫长。五十年后，她踏上重走勇者之旅的旅程，去寻找「了解人类」的答案。',
      status: ComicStatus.ongoing,
      chapterCount: 139,
      latestChapter: '第139话',
    ),
    OnlineComic(
      id: 'kusuriya',
      title: '药屋少女的呢喃',
      coverTone: CoverTone.red,
      author: '日向夏 / 猫海月',
      tags: ['悬疑', '历史', '日常'],
      description: '药师猫猫被卖入后宫，本来只想安静地做一名下女。凭着对药理的狂热与敏锐的观察，她一次次解开宫中的谜团。',
      status: ComicStatus.ongoing,
      chapterCount: 84,
      latestChapter: '第84话',
    ),
    OnlineComic(
      id: 'blue_lock',
      title: '蓝色监狱',
      coverTone: CoverTone.blue,
      author: '金城宗幸 / 野村优介',
      tags: ['热血', '格斗', '校园'],
      description: '为了打造世界第一的前锋，三百名高中生被集中到一座名为「蓝色监狱」的设施中。只有最 selfish 的人才能活下来。',
      status: ComicStatus.ongoing,
      chapterCount: 291,
      latestChapter: '第291话',
    ),
  ];

  static const categoryNames = <String, String>{
    'hotblood': '热血',
    'adventure': '冒险',
    'magic': '魔法',
    'school': '校园',
    'romance': '恋爱',
    'scifi': '科幻',
    'mystery': '悬疑',
    'daily': '日常',
    'fight': '格斗',
    'comedy': '搞笑',
    'fantasy': '奇幻',
    'history': '历史',
  };

  static const categoryGroups = <CategoryGroup>[
    CategoryGroup(
      id: 'genres',
      name: '题材',
      items: [
        CategoryItem(id: 'hotblood', name: '热血'),
        CategoryItem(id: 'adventure', name: '冒险'),
        CategoryItem(id: 'magic', name: '魔法'),
        CategoryItem(id: 'school', name: '校园'),
        CategoryItem(id: 'romance', name: '恋爱'),
        CategoryItem(id: 'scifi', name: '科幻'),
        CategoryItem(id: 'mystery', name: '悬疑'),
        CategoryItem(id: 'daily', name: '日常'),
        CategoryItem(id: 'fight', name: '格斗'),
        CategoryItem(id: 'comedy', name: '搞笑'),
        CategoryItem(id: 'fantasy', name: '奇幻'),
        CategoryItem(id: 'history', name: '历史'),
      ],
    ),
  ];

  static final chapters = <String, List<OnlineChapter>>{
    'kimetsu': [
      OnlineChapter(id: 'ep-206', title: '第206话 决战之后', group: ChapterGroup.serial, no: 206),
      OnlineChapter(id: 'ep-205', title: '第205话 最后的呼吸', group: ChapterGroup.serial, no: 205),
      OnlineChapter(id: 'ep-204', title: '第204话 破晓', group: ChapterGroup.serial, no: 204),
      OnlineChapter(id: 'ep-203', title: '第203话 继承', group: ChapterGroup.serial, no: 203),
      OnlineChapter(id: 'ep-202', title: '第202话 羁绊', group: ChapterGroup.serial, no: 202),
      OnlineChapter(id: 'ep-201', title: '第201话 回廊', group: ChapterGroup.serial, no: 201),
      OnlineChapter(id: 'extra-06', title: '番外06 炭治郎的日记', group: ChapterGroup.extra, no: 6),
      OnlineChapter(id: 'extra-05', title: '番外05 蝶屋的日常', group: ChapterGroup.extra, no: 5),
      OnlineChapter(id: 'extra-04', title: '番外04 柱合会议', group: ChapterGroup.extra, no: 4),
      OnlineChapter(id: 'vol-23', title: '第23卷', group: ChapterGroup.volume, no: 23),
      OnlineChapter(id: 'vol-22', title: '第22卷', group: ChapterGroup.volume, no: 22),
      OnlineChapter(id: 'vol-21', title: '第21卷', group: ChapterGroup.volume, no: 21),
      OnlineChapter(id: 'vol-20', title: '第20卷', group: ChapterGroup.volume, no: 20),
    ],
    'inou': [
      OnlineChapter(id: 'inou-206', title: '第206话 决战之后', group: ChapterGroup.serial, no: 206),
      OnlineChapter(id: 'inou-205', title: '第205话 最后的呼吸', group: ChapterGroup.serial, no: 205),
      OnlineChapter(id: 'inou-204', title: '第204话 破晓', group: ChapterGroup.serial, no: 204),
      OnlineChapter(id: 'inou-203', title: '第203话 继承', group: ChapterGroup.serial, no: 203),
      OnlineChapter(id: 'inou-202', title: '第202话 羁绊', group: ChapterGroup.serial, no: 202),
      OnlineChapter(id: 'inou-201', title: '第201话 回廊', group: ChapterGroup.serial, no: 201),
      OnlineChapter(id: 'inou-200', title: '第200话 日常', group: ChapterGroup.serial, no: 200),
      OnlineChapter(id: 'inou-199', title: '第199话 放课后', group: ChapterGroup.serial, no: 199),
    ],
    'onepiece': [
      OnlineChapter(id: 'op-1124', title: '第1124话 黎明', group: ChapterGroup.serial, no: 1124),
      OnlineChapter(id: 'op-1123', title: '第1123话 海流', group: ChapterGroup.serial, no: 1123),
      OnlineChapter(id: 'op-1122', title: '第1122话 最后的岛', group: ChapterGroup.serial, no: 1122),
      OnlineChapter(id: 'op-1121', title: '第1121话 草帽', group: ChapterGroup.serial, no: 1121),
      OnlineChapter(id: 'op-1120', title: '第1120话 约定', group: ChapterGroup.serial, no: 1120),
      OnlineChapter(id: 'op-109', title: '第109话 伙伴', group: ChapterGroup.serial, no: 109),
    ],
    'aot': _simpleChapters('aot', 139, 8),
    'opm': _simpleChapters('opm', 251, 8),
    'jjk': _simpleChapters('jjk', 271, 8),
    'spy': _simpleChapters('spy', 109, 8),
    'frieren': _simpleChapters('frieren', 139, 8),
    'kusuriya': _simpleChapters('kusuriya', 84, 6),
    'blue_lock': _simpleChapters('blue_lock', 291, 6),
  };

  static List<OnlineChapter> _simpleChapters(String comicId, int latest, int count) {
    final titles = ['决战之后', '最后的呼吸', '破晓', '继承', '羁绊', '回廊', '日常', '新的旅程'];
    return [
      for (var i = 0; i < count; i++)
        OnlineChapter(
          id: '$comicId-${latest - i}',
          title: '第${latest - i}话 ${titles[i % titles.length]}',
          group: ChapterGroup.serial,
          no: (latest - i).toDouble(),
        ),
    ];
  }

  static const _sourceCaps = {
    'explore',
    'categories',
    'category',
    'search',
    'loadComicInfo',
    'loadComicPages',
    'getImageLoadingConfig',
    'init',
  };

  static List<OnlineSource> seedSources(DateTime now) => [
    OnlineSource(
      manifest: const SourceManifest(
        specVersion: 2,
        id: 'manhuagui',
        name: '漫画柜',
        version: '1.0.0',
        lang: 'ja',
        baseUrl: 'https://www.manhuagui.com',
        entryClass: 'ManhuaguiSource',
        sourceFile: 'source.js',
        hosts: ['manhuagui.com', 'www.manhuagui.com', 'cf.mhgui.com'],
        description: '漫画柜示例源（真实站点结构，演示数据离线回放）。',
        headers: {'Referer': 'https://www.manhuagui.com/'},
      ),
      capabilities: _sourceCaps,
      lastUsedAt: now.subtract(const Duration(hours: 2)),
      importedAt: now.subtract(const Duration(days: 12)),
      glyphOverride: '柜',
    ),
    OnlineSource(
      manifest: const SourceManifest(
        specVersion: 2,
        id: 'copymanga',
        name: '拷贝漫画',
        version: '2.1.3',
        lang: 'zh',
        baseUrl: 'https://www.copymanga.org',
        entryClass: 'CopymangaSource',
        sourceFile: 'source.js',
        hosts: ['copymanga.org', 'www.copymanga.org', 'img.copymanga.org'],
        description: '拷贝漫画示例源。',
      ),
      capabilities: _sourceCaps.difference({'init'}),
      lastUsedAt: now.subtract(const Duration(days: 1)),
      importedAt: now.subtract(const Duration(days: 9)),
      glyphOverride: '拷',
    ),
    OnlineSource(
      manifest: const SourceManifest(
        specVersion: 2,
        id: 'mangabz',
        name: 'MangaBZ',
        version: '0.9.2',
        lang: 'zh',
        baseUrl: 'https://www.mangabz.com',
        entryClass: 'MangaBzSource',
        sourceFile: 'source.js',
        hosts: ['mangabz.com', 'www.mangabz.com'],
        description: 'MangaBZ 示例源（用于展示熔断红点）。',
      ),
      capabilities: {'explore', 'category', 'search', 'loadComicInfo', 'loadComicPages'},
      enabled: false,
      consecutiveFailures: 3,
      importedAt: now.subtract(const Duration(days: 4)),
      glyphOverride: 'BZ',
    ),
  ];

  static List<ReadingProgress> seedProgress(DateTime now) => [
    ReadingProgress(
      sourceId: 'manhuagui',
      sourceName: '漫画柜',
      comicId: 'kimetsu',
      comicTitle: '鬼灭之刃',
      coverTone: CoverTone.red,
      chapterId: 'kimetsu-18',
      chapterTitle: '第18回',
      page: 10,
      pageCount: 26,
      updatedAt: now.subtract(const Duration(hours: 2)),
    ),
    ReadingProgress(
      sourceId: 'manhuagui',
      sourceName: '漫画柜',
      comicId: 'inou',
      comicTitle: '日常系的异能战斗',
      coverTone: CoverTone.blue,
      chapterId: 'inou-206',
      chapterTitle: '第206话',
      page: 3,
      pageCount: 21,
      updatedAt: now.subtract(const Duration(hours: 2, minutes: 10)),
    ),
    ReadingProgress(
      sourceId: 'manhuagui',
      sourceName: '漫画柜',
      comicId: 'onepiece',
      comicTitle: '海贼王',
      coverTone: CoverTone.orange,
      chapterId: 'op-109',
      chapterTitle: '第206话',
      page: 3,
      pageCount: 26,
      updatedAt: now.subtract(const Duration(hours: 2, minutes: 20)),
    ),
  ];

  static List<DownloadTask> seedDownloads(DateTime now) => [
    DownloadTask(
      id: 'dl-kimetsu-18',
      sourceId: 'manhuagui',
      comicId: 'kimetsu',
      comicTitle: '鬼灭之刃',
      coverTone: CoverTone.red,
      chapterId: 'kimetsu-18',
      chapterTitle: '第18回',
      total: 26,
      done: 18,
      failed: 0,
      status: DownloadStatus.downloading,
      target: DownloadTarget.library,
      translate: true,
      updatedAt: now.subtract(const Duration(minutes: 3)),
    ),
    DownloadTask(
      id: 'dl-inou-206',
      sourceId: 'manhuagui',
      comicId: 'inou',
      comicTitle: '日常系的异能战斗',
      coverTone: CoverTone.blue,
      chapterId: 'inou-206',
      chapterTitle: '第206话',
      total: 21,
      done: 21,
      failed: 0,
      status: DownloadStatus.done,
      target: DownloadTarget.library,
      updatedAt: now.subtract(const Duration(minutes: 22)),
    ),
    DownloadTask(
      id: 'dl-onepiece-109',
      sourceId: 'manhuagui',
      comicId: 'onepiece',
      comicTitle: '海贼王',
      coverTone: CoverTone.orange,
      chapterId: 'op-109',
      chapterTitle: '第109话',
      total: 26,
      done: 23,
      failed: 3,
      status: DownloadStatus.partial,
      target: DownloadTarget.library,
      updatedAt: now.subtract(const Duration(minutes: 40)),
    ),
  ];

  static OnlineComic? comicById(String id) {
    for (final comic in longStripComics) {
      if (comic.id == id) return comic;
    }
    return null;
  }

  static List<OnlineChapter> chaptersOf(String comicId) => chapters[comicId] ?? const [];

  static int pageCountOf(String comicId) => switch (comicId) {
    'inou' => 21,
    'kusuriya' => 18,
    'blue_lock' => 22,
    _ => 26,
  };

  static List<FeedSection> feedPage(int page) {
    final update = longStripComics.take(7).toList();
    final popular = [
      longStripComics[4],
      longStripComics[5],
      longStripComics[6],
      longStripComics[7],
      longStripComics[0],
      longStripComics[1],
      longStripComics[2],
    ];
    if (page <= 1) {
      return [
        FeedSection(
          id: 'update',
          title: '最近更新',
          items: update,
          pageSize: 42,
          hint: 'explore · section=update · page=1',
        ),
        FeedSection(id: 'popular', title: '人气作品', items: popular, pageSize: 42, hint: 'section=popular'),
      ];
    }
    return [
      FeedSection(
        id: 'update',
        title: '最近更新',
        items: longStripComics.skip(7).toList(),
        pageSize: 42,
        hint: 'explore · section=update · page=$page',
      ),
      FeedSection(
        id: 'popular',
        title: '人气作品',
        items: longStripComics.skip(7).toList().reversed.toList(),
        pageSize: 42,
        hint: 'section=popular · page=$page',
      ),
    ];
  }

  static List<OnlineComic> comicsInCategory(String categoryId, {int page = 1}) {
    final name = categoryNames[categoryId];
    if (name == null) return const [];
    final matched = longStripComics.where((comic) => comic.tags.contains(name)).toList();
    if (matched.isEmpty) {
      // 少量题材没有标签：返回前几部，保证分类页可用（对应设计稿的兜底口径）。
      return page <= 1 ? longStripComics.take(4).toList() : const [];
    }
    return page <= 1 ? matched : matched.skip(6).toList();
  }

  static List<OnlineComic> search(String keyword, {int page = 1}) {
    final normalized = keyword.trim().toLowerCase();
    if (normalized.isEmpty) return const [];
    final matched = longStripComics.where((comic) {
      if (comic.title.toLowerCase().contains(normalized)) return true;
      if ((comic.author ?? '').toLowerCase().contains(normalized)) return true;
      return comic.tags.any((tag) => tag.toLowerCase().contains(normalized));
    }).toList();
    return page <= 1 ? matched : matched.skip(6).toList();
  }
}
