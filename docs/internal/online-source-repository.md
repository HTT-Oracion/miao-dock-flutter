# 在线漫画数据源仓库格式

> 应用不内置源仓库。用户可在「设置 › 漫画源」粘贴仓库 `index.json` 地址，
> 也可以直接粘贴单个 `.js` 源或旧版 `source.json` 地址。仓库由用户自行维护、
> 自行托管；安装第三方脚本前请确认来源可信。

## 一、推荐：社区单文件源仓库

一个静态站点 / raw 仓库只需要：

```
repo/
├── index.json
└── manhuagui.js
```

`index.json` 是条目数组：

```json
[
  {
    "name": "漫画柜",
    "fileName": "manhuagui.js",
    "key": "ManHuaGui",
    "version": "1.2.1",
    "description": "漫画柜（看漫画）在线源"
  }
]
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `key` | ✅ | 源稳定 id；同一源更新时保持不变 |
| `name` | ✅ | 显示名 |
| `fileName` | ✅ | 相对 `index.json` 的脚本路径 |
| `version` | ⭕ | 语义化版本；用于「可更新」提示 |
| `description` | ⭕ | 列表说明 |
| `url` | ⭕ | 也可直接给脚本绝对地址；给了就不再看 `fileName` |

也接受 `{ "name": "...", "sources": [...] }` 形式，或 `url`/`fileName` 混用。
条目的 `fileName` 会相对 `index.json` 的地址解析。

## 二、单文件源脚本

源沿用社区约定的 `ComicSource` 类：

```js
class MySource extends ComicSource {
  name = '示例源';
  key = 'MySource';
  version = '1.0.0';
  baseUrl = 'https://example.com';

  explore = [{
    title: '推荐',
    type: 'multiPartPage',
    load: async (page) => [{ title: '分区', comics: [] }],
  }];

  category = { title: '分类', parts: [...] };
  categoryComics = { load: async (category, param, options, page) => ({ comics: [], maxPage: 1 }) };
  search = { load: async (keyword, options, page) => ({ comics: [], maxPage: 1 }) };
  comic = {
    loadInfo: async (id) => new ComicDetails({ title: '', chapters: new Map() }),
    loadEp: async (comicId, epId) => ({ images: [] }),
    onImageLoad: (url, comicId, epId) => ({ headers: {} }),
  };
}
```

应用加载时会：

1. 用 `class ... extends ComicSource` 定位入口类；
2. 从脚本读取 `name/key/version/baseUrl`，从脚本中的绝对 URL 提取域名白名单；
3. 在 QuickJS 中实例化并调用 `init()`；
4. 通过兼容层把 `explore / category / search / comic.loadInfo / comic.loadEp /
   comic.onImageLoad` 映射为应用内部统一 DTO。

`Comic`、`ComicDetails`、`ImageLoadingConfig`、`Network`、`HtmlDocument`、
`Convert`、`ComicSource.loadData/saveData/deleteData`、`log` 均按社区源惯例提供。
账号登录 / WebView / 评论等扩展 API 暂未接入。

## 三、安装与更新

1. 「链接导入」先抓取 URL：
   - JSON 数组 / 含 `sources` 的 JSON → 仓库，写入「源仓库」并打开源列表；
   - JSON 含 `specVersion` → 旧版源包，直接安装；
   - JavaScript 文本 → 单文件 `ComicSource`，直接安装。
2. 仓库条目点「安装」才下载脚本；相同 `key` 已安装时提示覆盖。
3. 仓库条目版本与已安装版本不同时显示「更新到 x.y.z」，点击走覆盖安装。
4. 安装后的源记录 `sourceUrl` 与 `libraryId`；覆盖后 QuickJS 会卸载旧实例，
   下次浏览加载新脚本。

## 四、可选：旧版 `source.json` 包

为兼容早期本地源，仍支持：

```
mysource/
├── source.json
├── source.js
└── icon.png
```

`source.json` 的 `specVersion` 为 2，字段与 `SourceManifest` 一致；脚本类需
`extends SourceBase` 并实现 `loadComicInfo`。这条路径不是推荐入口，仓库索引
优先使用上面的单文件格式。

## 五、限制与安全

- 仅支持 `http` / `https`；单个清单 ≤ 512 KB，单个脚本 ≤ 2 MB。
- 源脚本在 QuickJS 中执行，单 runtime、64 MB 内存上限、单次调用 20s 超时。
- 请求受脚本中提取的域名白名单约束；图片同样受限。
- 图片缓存在 `online/images/<sourceId>/`，删除源时清除。
- 应用不内置源、不提供官方源市场；第三方源的行为与可用性由源维护者负责。
