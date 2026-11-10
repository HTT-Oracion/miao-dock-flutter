/*
 * 在线漫画源运行时前奏（随 App 发布，不是数据源）。
 *
 * 数据源通过 sendMessage 与宿主通信；HTTP 返回 Promise，DOM 查询是同步返回。
 * 这里只暴露计划 §5.3 / §4.4 约定的最小能力，避免把 Flutter 对象泄露给源。
 */
'use strict';

var APP = { version: '0.1.0' };

function sourceError(code, message) {
  var e = new Error(message || code || 'SOURCE_CRASHED');
  e.code = code || 'SOURCE_CRASHED';
  return e;
}

class SourceBase {
  constructor() {}
}

function setTimeout(callback, delay) {
  const id = (setTimeout._id = (setTimeout._id || 0) + 1);
  sendMessage({ method: 'delay', time: delay || 0 }).then(function () {
    callback();
  });
  return id;
}

function clearTimeout(_id) {}

var console = {
  log: function () { sendMessage({ method: 'log', level: 'info', title: 'source', content: Array.prototype.join.call(arguments, ' ') }); },
  info: function () { console.log.apply(console, arguments); },
  warn: function () { sendMessage({ method: 'log', level: 'warning', title: 'source', content: Array.prototype.join.call(arguments, ' ') }); },
  error: function () { sendMessage({ method: 'log', level: 'error', title: 'source', content: Array.prototype.join.call(arguments, ' ') }); },
};

function Cookie(name, value, domain, path) {
  this.name = name;
  this.value = value;
  this.domain = domain;
  this.path = path;
}

var Network = {
  async sendRequest(method, url, headers, data, extra) {
    const result = await sendMessage({
      method: 'http',
      http_method: method || 'GET',
      url: url,
      headers: headers || {},
      data: data,
      extra: extra || {},
      sourceId: globalThis.__activeSourceId || null,
    });
    if (result && result.error) throw sourceError(result.errorCode || 'NETWORK', result.error);
    return result;
  },
  async get(url, headers, extra) {
    return this.sendRequest('GET', url, headers, undefined, extra);
  },
  async post(url, headers, data, extra) {
    return this.sendRequest('POST', url, headers, data, extra);
  },
  async put(url, headers, data, extra) {
    return this.sendRequest('PUT', url, headers, data, extra);
  },
  async delete(url, headers, extra) {
    return this.sendRequest('DELETE', url, headers, undefined, extra);
  },
  async fetchBytes(method, url, headers, data, extra) {
    return this.sendRequest(method, url, headers, data, Object.assign({}, extra, { bytes: true }));
  },
  setCookies(url, cookies) {
    return sendMessage({ method: 'cookie', function: 'set', url: url, cookies: cookies || [] });
  },
  getCookies(url) {
    return sendMessage({ method: 'cookie', function: 'get', url: url });
  },
};

class HtmlDocument {
  constructor(html) {
    this._key = (HtmlDocument._key = (HtmlDocument._key || 0) + 1);
    sendMessage({ method: 'html', function: 'parse', key: this._key, data: String(html == null ? '' : html) });
  }
  querySelector(query) {
    const key = sendMessage({ method: 'html', function: 'querySelector', key: this._key, query: query });
    return key == null ? null : new HtmlElement(this._key, key);
  }
  querySelectorAll(query) {
    const keys = sendMessage({ method: 'html', function: 'querySelectorAll', key: this._key, query: query });
    return keys.map((key) => new HtmlElement(this._key, key));
  }
  getElementById(id) {
    const key = sendMessage({ method: 'html', function: 'getElementById', key: this._key, id: id });
    return key == null ? null : new HtmlElement(this._key, key);
  }
  dispose() {
    sendMessage({ method: 'html', function: 'dispose', key: this._key });
  }
}

class HtmlElement {
  constructor(doc, key) {
    this._doc = doc;
    this._key = key;
  }
  get text() {
    return sendMessage({ method: 'html', function: 'getText', doc: this._doc, key: this._key });
  }
  get attributes() {
    return sendMessage({ method: 'html', function: 'getAttributes', doc: this._doc, key: this._key });
  }
  get innerHTML() {
    return sendMessage({ method: 'html', function: 'getInnerHTML', doc: this._doc, key: this._key });
  }
  get children() {
    return sendMessage({ method: 'html', function: 'getChildren', doc: this._doc, key: this._key }).map(
      (key) => new HtmlElement(this._doc, key),
    );
  }
  get nodes() {
    return sendMessage({ method: 'html', function: 'getNodes', doc: this._doc, key: this._key }).map(
      (key) => new HtmlNode(this._doc, key),
    );
  }
  get childNodes() {
    return this.nodes;
  }
  get classNames() {
    return sendMessage({ method: 'html', function: 'getClassNames', doc: this._doc, key: this._key });
  }
  get id() {
    return sendMessage({ method: 'html', function: 'getId', doc: this._doc, key: this._key });
  }
  get localName() {
    return sendMessage({ method: 'html', function: 'getLocalName', doc: this._doc, key: this._key });
  }
  get parent() {
    const key = sendMessage({ method: 'html', function: 'getParent', doc: this._doc, key: this._key });
    return key == null ? null : new HtmlElement(this._doc, key);
  }
  get previousElementSibling() {
    const key = sendMessage({ method: 'html', function: 'getPreviousSibling', doc: this._doc, key: this._key });
    return key == null ? null : new HtmlElement(this._doc, key);
  }
  get nextElementSibling() {
    const key = sendMessage({ method: 'html', function: 'getNextSibling', doc: this._doc, key: this._key });
    return key == null ? null : new HtmlElement(this._doc, key);
  }
  querySelector(query) {
    const key = sendMessage({ method: 'html', function: 'dom_querySelector', doc: this._doc, key: this._key, query: query });
    return key == null ? null : new HtmlElement(this._doc, key);
  }
  querySelectorAll(query) {
    return sendMessage({ method: 'html', function: 'dom_querySelectorAll', doc: this._doc, key: this._key, query: query }).map(
      (key) => new HtmlElement(this._doc, key),
    );
  }
}

class HtmlNode {
  constructor(doc, key) {
    this._doc = doc;
    this._key = key;
  }
  get text() {
    return sendMessage({ method: 'html', function: 'node_text', doc: this._doc, key: this._key });
  }
  get type() {
    return sendMessage({ method: 'html', function: 'node_type', doc: this._doc, key: this._key });
  }
  toElement() {
    const key = sendMessage({ method: 'html', function: 'node_toElement', doc: this._doc, key: this._key });
    return key == null ? null : new HtmlElement(this._doc, key);
  }
}

var Convert = {
  encodeUtf8: (value) => sendMessage({ method: 'convert', type: 'utf8', value: value, isEncode: true }),
  decodeUtf8: (value) => sendMessage({ method: 'convert', type: 'utf8', value: value, isEncode: false }),
  encodeBase64: (value) => sendMessage({ method: 'convert', type: 'base64', value: value, isEncode: true }),
  decodeBase64: (value) => sendMessage({ method: 'convert', type: 'base64', value: value, isEncode: false }),
  md5: (value) => sendMessage({ method: 'convert', type: 'md5', value: value, isEncode: true }),
  sha1: (value) => sendMessage({ method: 'convert', type: 'sha1', value: value, isEncode: true }),
  sha256: (value) => sendMessage({ method: 'convert', type: 'sha256', value: value, isEncode: true }),
};


// ── 上游单文件源兼容层 ─────────────────────────────────────────────
// 这些构造器只保留源脚本实际使用的字段；字段缺失时由适配器按空处理。
function Comic({ id, title, subtitle, subTitle, cover, tags, description, maxPage, language, favoriteId, stars, author, latestChapter, updatedAt, updateTime, rank, score } = {}) {
  this.id = id;
  this.title = title;
  this.subtitle = subtitle ?? subTitle;
  this.subTitle = this.subtitle;
  this.cover = cover;
  this.tags = tags;
  this.description = description;
  this.maxPage = maxPage;
  this.language = language;
  this.favoriteId = favoriteId;
  this.stars = stars;
  this.author = author;
  this.latestChapter = latestChapter ?? this.subtitle;
  this.updatedAt = updatedAt ?? updateTime;
  this.updateTime = this.updatedAt;
  this.rank = rank;
  this.score = score;
}

function ComicDetails({ title, subtitle, subTitle, cover, description, tags, chapters, recommend, author, status, latestChapter, updatedAt, updateTime } = {}) {
  this.title = title;
  this.subtitle = subtitle ?? subTitle;
  this.cover = cover;
  this.description = description;
  this.tags = tags;
  this.chapters = chapters;
  this.recommend = recommend;
  this.author = author;
  this.status = status;
  this.latestChapter = latestChapter;
  this.updatedAt = updatedAt ?? updateTime;
  this.updateTime = this.updatedAt;
}

function ImageLoadingConfig({ url, method, data, headers } = {}) {
  this.url = url;
  this.method = method;
  this.data = data;
  this.headers = headers;
}

class ComicSource {
  name = '';
  key = '';
  version = '';
  minAppVersion = '';
  url = '';
  account = {};
  translation = {};

  loadData(key) {
    return sendMessage({ method: 'load_data', key: this.key, data_key: key });
  }
  saveData(key, data) {
    return sendMessage({ method: 'save_data', key: this.key, data_key: key, data: data });
  }
  deleteData(key) {
    return sendMessage({ method: 'delete_data', key: this.key, data_key: key });
  }
  translate(key) {
    return key;
  }
  init() {}
}

function log(level, title, content) {
  sendMessage({ method: 'log', level: level, title: title, content: content });
}

// ── 上游字段 → 本项目能力 DTO ─────────────────────────────────────
function __legacyTags(value) {
  if (value == null) return [];
  if (Array.isArray(value)) return value.map((e) => String(e)).filter(Boolean);
  if (typeof value === 'object') {
    const out = [];
    for (const key of Object.keys(value)) {
      const items = value[key];
      if (Array.isArray(items)) {
        for (const item of items) out.push(String(item));
      } else if (items != null && typeof items !== 'object') {
        out.push(String(items));
      }
    }
    if (out.length === 0) {
      for (const key of Object.keys(value)) out.push(String(key));
    }
    return out;
  }
  return [String(value)];
}

function __legacyAuthor(source, tags) {
  if (source.author != null) {
    if (Array.isArray(source.author)) return source.author.map((e) => String(e)).filter(Boolean).join(', ');
    const text = String(source.author).trim();
    if (text) return text;
  }
  const names = ['author', 'authors', 'artist', 'artists', '作者', '画师'];
  const raw = source.tags;
  if (raw && typeof raw === 'object' && !Array.isArray(raw)) {
    for (const key of Object.keys(raw)) {
      if (names.indexOf(String(key).toLowerCase()) >= 0) {
        const value = raw[key];
        if (Array.isArray(value)) return value.map((e) => String(e)).filter(Boolean).join(', ');
        if (value != null && String(value).trim()) return String(value).trim();
      }
    }
  }
  for (const tag of tags) {
    const m = /^(?:作者|author)[:：]\s*(.+)$/i.exec(tag);
    if (m) return m[1].trim();
  }
  return undefined;
}

function __legacyUpdate(source, tags) {
  const direct = source.updateTime ?? source.updatedAt ?? source.update;
  if (direct != null && String(direct).trim()) return String(direct).trim();
  const names = ['更新', '最後更新', '最后更新', 'update', 'last update', '更新时间'];
  const raw = source.tags;
  if (raw && typeof raw === 'object' && !Array.isArray(raw)) {
    for (const key of Object.keys(raw)) {
      if (names.indexOf(String(key).toLowerCase()) >= 0) {
        const value = raw[key];
        const text = Array.isArray(value) ? (value.length ? String(value[0]) : '') : String(value || '');
        if (text.trim()) return text.trim();
      }
    }
  }
  for (const tag of tags) {
    const m = /^(?:更新于|更新|更新时间|update)[:：]\s*(.+)$/i.exec(tag);
    if (m) return m[1].trim();
  }
  return undefined;
}

function __legacyComic(source) {
  if (!source) return null;
  const id = source.id == null ? '' : String(source.id).trim();
  const title = source.title == null ? '' : String(source.title).trim();
  if (!id || !title) return null;
  const tags = __legacyTags(source.tags);
  const author = __legacyAuthor(source, tags);
  const updatedAt = __legacyUpdate(source, tags);
  const rank = source.rank == null ? undefined : (parseInt(source.rank, 10) || undefined);
  let status = source.status === 'completed' ? 'completed' : (source.status === 'ongoing' ? 'ongoing' : undefined);
  if (!status) {
    for (const tag of tags) {
      if (tag.indexOf('完结') >= 0) { status = 'completed'; break; }
      if (tag.indexOf('连载') >= 0) { status = 'ongoing'; break; }
    }
  }
  return {
    id,
    title,
    cover: source.cover ? String(source.cover) : undefined,
    subtitle: source.subtitle != null ? String(source.subtitle) : (source.subTitle != null ? String(source.subTitle) : undefined),
    latestChapter: source.latestChapter != null ? String(source.latestChapter) : (source.subtitle != null ? String(source.subtitle) : undefined),
    author,
    tags,
    description: source.description != null ? String(source.description) : '',
    status,
    updatedAt,
    rank,
  };
}

function __legacyChapterNo(title) {
  let m = /第\s*([0-9]+(?:\.[0-9]+)?)\s*[话話回卷集部期]/.exec(title);
  if (m) return parseFloat(m[1]);
  m = /(?:vol|ch|chapter)\.?\s*([0-9]+(?:\.[0-9]+)?)/i.exec(title);
  return m ? parseFloat(m[1]) : undefined;
}

function __legacyChapters(value) {
  if (value == null) return [];
  const out = [];
  const push = (title, id) => {
    if (id == null || title == null) return;
    const key = String(id);
    const text = String(title);
    if (!key || !text) return;
    out.push({ id: key, title: text, no: __legacyChapterNo(text) });
  };
  if (Array.isArray(value)) {
    for (const item of value) {
      if (item && typeof item === 'object') push(item.title ?? item.name, item.id ?? item.key);
    }
  } else if (typeof value.forEach === 'function') {
    value.forEach((title, id) => push(title, id));
  } else if (typeof value === 'object') {
    for (const key of Object.keys(value)) {
      const item = value[key];
      if (item && typeof item === 'object') push(item.title ?? item.name, key);
      else push(item, key);
    }
  }
  return out;
}

function __legacyParts(value) {
  if (value == null) return [];
  const out = [];
  const add = (title, comics) => {
    const list = (comics || []).map(__legacyComic).filter(Boolean);
    if (list.length > 0) out.push({ title: String(title || '推荐'), comics: list });
  };
  if (Array.isArray(value)) {
    for (const part of value) {
      if (!part) continue;
      if (Array.isArray(part.comics)) add(part.title, part.comics);
      else if (Array.isArray(part.items)) add(part.title, part.items);
    }
  } else if (typeof value === 'object') {
    for (const key of Object.keys(value)) add(key, value[key]);
  }
  return out;
}

async function __legacyExplore(source, ctx) {
  const page = (ctx && ctx.page) || 1;
  const sections = [];
  let hasMore = false;
  const pages = Array.isArray(source.explore) ? source.explore : [];
  for (let i = 0; i < pages.length; i++) {
    const entry = pages[i];
    if (!entry) continue;
    const type = entry.type || 'multiPartPage';
    if (type === 'multiPartPage' || type === 'singlePageWithMultiPart') {
      const raw = await entry.load(page);
      const parts = __legacyParts(raw);
      for (let j = 0; j < parts.length; j++) {
        sections.push({
          id: 'explore-' + i + '-' + j,
          title: parts[j].title,
          layout: 'grid',
          items: parts[j].comics,
        });
      }
    } else if (type === 'multiPageComicList') {
      const res = await entry.load(page);
      const list = (res && (res.comics || res.items) || []).map(__legacyComic).filter(Boolean);
      if (list.length > 0) {
        sections.push({ id: 'explore-' + i, title: entry.title || source.name, layout: 'grid', items: list });
      }
      if (res && res.maxPage && page < res.maxPage) hasMore = true;
    } else if (typeof entry.load === 'function') {
      const raw = await entry.load(page);
      const parts = __legacyParts(raw);
      for (let j = 0; j < parts.length; j++) {
        sections.push({ id: 'explore-' + i + '-' + j, title: parts[j].title, layout: 'grid', items: parts[j].comics });
      }
    }
  }
  return { sections, hasMore, page };
}

function __legacyCategoryParts(source) {
  const category = source.category;
  if (!category || !Array.isArray(category.parts)) return [];
  return category.parts;
}

function __legacyCategories(source) {
  const parts = __legacyCategoryParts(source);
  const groups = [];
  for (let i = 0; i < parts.length; i++) {
    const part = parts[i];
    const categories = Array.isArray(part.categories) ? part.categories : [];
    const items = [];
    for (let j = 0; j < categories.length; j++) {
      const raw = categories[j];
      const label = raw && typeof raw === 'object' ? (raw.label ?? raw.name) : raw;
      if (label == null) continue;
      items.push({ id: i + ':' + j, name: String(label) });
    }
    if (items.length > 0) groups.push({ id: String(i), name: String(part.name || '分类'), items });
  }
  return groups;
}

async function __legacyCategory(source, ctx) {
  const category = source.category;
  const comics = source.categoryComics;
  const id = String((ctx && ctx.id) || '');
  const page = (ctx && ctx.page) || 1;
  if (!category || !comics || typeof comics.load !== 'function') {
    return { items: [], page, hasMore: false };
  }
  const pair = id.split(':');
  const partIndex = parseInt(pair[0], 10) || 0;
  const itemIndex = parseInt(pair[1], 10) || 0;
  const part = (category.parts || [])[partIndex];
  if (!part) return { items: [], page, hasMore: false };
  const raw = (part.categories || [])[itemIndex];
  const label = raw && typeof raw === 'object' ? (raw.label ?? raw.name) : raw;
  const param = Array.isArray(part.categoryParams) ? part.categoryParams[itemIndex] : (part.params ? part.params[itemIndex] : label);
  const options = (comics.optionList || []).map(() => '');
  const res = await comics.load(label == null ? '' : String(label), param, options, page);
  const items = (res && (res.comics || res.items) || []).map(__legacyComic).filter(Boolean);
  const maxPage = (res && res.maxPage) || 1;
  return { items, page, hasMore: page < maxPage };
}

async function __legacySearch(source, ctx) {
  const page = (ctx && ctx.page) || 1;
  const keyword = String((ctx && ctx.keyword) || '');
  if (!source.search || typeof source.search.load !== 'function') {
    return { items: [], page, hasMore: false };
  }
  const options = (source.search.optionList || []).map(() => '');
  const res = await source.search.load(keyword, options, page);
  const items = (res && (res.comics || res.items) || []).map(__legacyComic).filter(Boolean);
  const maxPage = (res && res.maxPage) || 1;
  return { items, page, hasMore: page < maxPage };
}

async function __legacyDetail(source, ctx) {
  const id = String((ctx && ctx.id) || '');
  const loader = source.comic && source.comic.loadInfo;
  if (typeof loader !== 'function') throw sourceError('SPEC_UNSUPPORTED', 'comic.loadInfo');
  const detail = await loader.call(source.comic, id);
  if (!detail) throw sourceError('NOT_FOUND', id);
  const detailTags = __legacyTags(detail.tags);
  const comic = __legacyComic({
    ...detail,
    id: detail.id ?? id,
    title: detail.title,
    cover: detail.cover,
    subtitle: detail.subtitle ?? detail.subTitle,
    description: detail.description,
    tags: detail.tags,
    author: detail.author ?? __legacyAuthor(detail, detailTags),
    updateTime: detail.updateTime ?? __legacyUpdate(detail, detailTags),
    status: detail.status,
  });
  if (!comic) throw sourceError('PARSE_FAILED', 'detail title missing');
  const chapters = __legacyChapters(detail.chapters);
  comic.chapterCount = chapters.length;
  return { ...comic, chapters };
}

async function __legacyPages(source, ctx) {
  const comic = source.comic;
  if (!comic || typeof comic.loadEp !== 'function') throw sourceError('SPEC_UNSUPPORTED', 'comic.loadEp');
  const res = await comic.loadEp(String((ctx && ctx.id) || ''), String((ctx && ctx.chapterId) || ''));
  if (Array.isArray(res)) return res;
  if (res && Array.isArray(res.images)) return res.images;
  return [];
}

async function __legacyImageConfig(source, ctx) {
  const comic = source.comic;
  const loader = comic && (comic.onImageLoad || comic.onThumbnailLoad);
  if (typeof loader !== 'function') return {};
  const cfg = await loader.call(comic, String((ctx && ctx.url) || ''), String((ctx && ctx.comicId) || ''), String((ctx && ctx.chapterId) || ''));
  if (!cfg) return {};
  return {
    url: cfg.url,
    method: cfg.method,
    headers: cfg.headers,
  };
}

function __legacyRankTabs(source) {
  const rank = source.rank;
  const tabs = [];
  const add = (id, title) => {
    if (id == null) return;
    tabs.push({ id: String(id), title: String(title == null || title === '' ? id : title) });
  };
  if (rank) {
    const rawTabs = Array.isArray(rank.tabs) ? rank.tabs : (Array.isArray(rank) ? rank : []);
    for (let i = 0; i < rawTabs.length; i++) {
      const item = rawTabs[i];
      if (item && typeof item === 'object') add(item.id ?? i, item.title ?? item.name ?? item.id ?? i);
      else add(i, item);
    }
  }
  if (tabs.length === 0 && source.categoryComics && source.categoryComics.ranking) {
    const options = source.categoryComics.ranking.options || [];
    for (const option of options) {
      const text = String(option);
      const split = text.indexOf('-');
      if (split < 0) continue;
      add(text.slice(0, split), text.slice(split + 1));
    }
  }
  return tabs;
}

async function __legacyRank(source, ctx) {
  const id = String((ctx && ctx.id) || '');
  const page = (ctx && ctx.page) || 1;
  let loader = source.rank && source.rank.load;
  if (typeof loader !== 'function' && source.categoryComics && source.categoryComics.ranking) {
    loader = source.categoryComics.ranking.load;
  }
  if (typeof loader !== 'function') return { items: [], page, hasMore: false };
  const res = await loader.call(source.rank && source.rank.load === loader ? source.rank : source.categoryComics.ranking, id, page);
  const items = (res && (res.comics || res.items) || []).map(__legacyComic).filter(Boolean);
  const maxPage = (res && res.maxPage) || 1;
  return { items, page, hasMore: page < maxPage, total: items.length };
}

function __makeLegacyAdapter(source) {
  return {
    name: source.name,
    key: source.key,
    version: source.version,
    explore: (ctx) => __legacyExplore(source, ctx),
    categories: () => __legacyCategories(source),
    category: (ctx) => __legacyCategory(source, ctx),
    rankTabs: () => __legacyRankTabs(source),
    rank: (ctx) => __legacyRank(source, ctx),
    search: (ctx) => __legacySearch(source, ctx),
    loadComicInfo: (ctx) => __legacyDetail(source, ctx),
    loadComicPages: (ctx) => __legacyPages(source, ctx),
    getImageLoadingConfig: (ctx) => __legacyImageConfig(source, ctx),
    init: async () => { if (typeof source.init === 'function') await source.init(); },
  };
}

globalThis.SourceBase = SourceBase;
globalThis.Network = Network;
globalThis.HtmlDocument = HtmlDocument;
globalThis.HtmlElement = HtmlElement;
globalThis.HtmlNode = HtmlNode;
globalThis.Convert = Convert;
globalThis.sourceError = sourceError;
globalThis.APP = APP;
globalThis.console = console;
globalThis.Comic = Comic;
globalThis.ComicDetails = ComicDetails;
globalThis.ImageLoadingConfig = ImageLoadingConfig;
globalThis.ComicSource = ComicSource;
globalThis.log = log;
globalThis.__makeLegacyAdapter = __makeLegacyAdapter;
