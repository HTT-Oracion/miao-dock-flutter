import 'online_models.dart';

/// 分类接口失败时的常用题材兜底（功能兜底，不是演示漫画数据）。
const List<CategoryGroup> fallbackCategoryGroups = [
  CategoryGroup(
    id: 'genre',
    name: '题材',
    items: [
      CategoryItem(id: 'rexue', name: '热血'),
      CategoryItem(id: 'maoxian', name: '冒险'),
      CategoryItem(id: 'mofa', name: '魔法'),
      CategoryItem(id: 'xiaoyuan', name: '校园'),
      CategoryItem(id: 'lianai', name: '恋爱'),
      CategoryItem(id: 'xuanyi', name: '悬疑'),
      CategoryItem(id: 'kehuan', name: '科幻'),
      CategoryItem(id: 'gaoxiao', name: '搞笑'),
      CategoryItem(id: 'dushi', name: '都市'),
      CategoryItem(id: 'lishi', name: '历史'),
      CategoryItem(id: 'zhanzheng', name: '战争'),
      CategoryItem(id: 'kongbu', name: '恐怖'),
      CategoryItem(id: 'wuxia', name: '武侠'),
      CategoryItem(id: 'yundong', name: '运动'),
    ],
  ),
];
