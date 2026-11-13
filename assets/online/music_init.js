/*
 * 在线音乐源运行时前奏（随 App 发布，不是数据源）。
 *
 * 与漫画源同协议：源通过 sendMessage 与宿主通信，HTTP 返回 Promise，
 * Convert 提供宿主侧哈希/编码（QuickJS 里跑哈希慢且不必要）。
 * 音乐源是纯 JSON API，不需要 DOM 桥 —— 协议里没有 `html` 方法。
 */
'use strict';

var APP = { version: '0.1.0' };

function sourceError(code, message) {
  var e = new Error(message || code || 'SOURCE_CRASHED');
  e.code = code || 'SOURCE_CRASHED';
  return e;
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
  log: function () { sendMessage({ method: 'log', level: 'info', title: 'music-source', content: Array.prototype.join.call(arguments, ' ') }); },
  info: function () { console.log.apply(console, arguments); },
  warn: function () { sendMessage({ method: 'log', level: 'warning', title: 'music-source', content: Array.prototype.join.call(arguments, ' ') }); },
  error: function () { sendMessage({ method: 'log', level: 'error', title: 'music-source', content: Array.prototype.join.call(arguments, ' ') }); },
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
      sourceId: globalThis.__activeMusicSourceId || null,
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
  setCookies(url, cookies) {
    return sendMessage({ method: 'cookie', function: 'set', url: url, cookies: cookies || [] });
  },
  getCookies(url) {
    return sendMessage({ method: 'cookie', function: 'get', url: url });
  },
  /// 二进制响应（咪咕混淆流等）：body 以 base64 在 bodyBase64 字段过桥。
  async fetchBytes(method, url, headers) {
    return this.sendRequest(method || 'GET', url, headers, undefined, { bytes: true });
  },
};

/// App 注入的会话 Cookie 原串（WebView 登录落盘那串）。
///
/// 酷狗等平台把票据当 URL 参数用而非 Cookie 头 —— Cookie 罐按域名隔离带不到
/// 网关域，源用它自己解析 userid / mid / token。未登录返回 ''。
async function getSessionCookie() {
  return sendMessage({ method: 'session', sourceId: globalThis.__activeMusicSourceId || null }) || '';
}

var Convert = {
  encodeUtf8: (value) => sendMessage({ method: 'convert', type: 'utf8', value: value, isEncode: true }),
  decodeUtf8: (value) => sendMessage({ method: 'convert', type: 'utf8', value: value, isEncode: false }),
  encodeBase64: (value) => sendMessage({ method: 'convert', type: 'base64', value: value, isEncode: true }),
  decodeBase64: (value) => sendMessage({ method: 'convert', type: 'base64', value: value, isEncode: false }),
  md5: (value) => sendMessage({ method: 'convert', type: 'md5', value: value }),
  sha1: (value) => sendMessage({ method: 'convert', type: 'sha1', value: value }),
  sha256: (value) => sendMessage({ method: 'convert', type: 'sha256', value: value }),
};

/// 表单编码：音乐接口大量使用 form-urlencoded POST，内置省得每个源手写。
function formEncode(obj) {
  const parts = [];
  for (const key of Object.keys(obj || {})) {
    const v = obj[key];
    if (v === undefined || v === null) continue;
    parts.push(encodeURIComponent(key) + '=' + encodeURIComponent(String(v)));
  }
  return parts.join('&');
}

/// QQ 音乐 sign：`zzc{hash[23,14,6,36,16,40,7,19]}{base64(xor)}{hash[16,1,32,12,19,27,8,5]}`。
///
/// hash 是 SHA1 十六进制串；取位序与异或表逐字对齐上游，改一位服务端回 sign error。
function qqSign(text) {
  const hash = Convert.sha1(text);
  const p1 = [23, 14, 6, 36, 16, 40, 7, 19].map((i) => (i < hash.length ? hash[i] : '')).join('');
  const p2 = [16, 1, 32, 12, 19, 27, 8, 5].map((i) => (i < hash.length ? hash[i] : '')).join('');
  const scramble = [89, 39, 179, 150, 218, 82, 58, 252, 177, 52, 186, 123, 120, 64, 242, 133, 143, 161, 121, 179];
  const bytes = scramble.map((v, i) => v ^ parseInt(hash.substr(i * 2, 2), 16));
  const middle = Convert.encodeBase64(bytes).replace(/[\/+=]/g, '');
  return ('zzc' + p1 + middle + p2).toLowerCase();
}

/// 判 HTTP 成功并解 JSON 的公共路径；非 JSON 响应直接抛错（错误信息带状态码）。
async function fetchJson(method, url, headers, data) {
  const res = await Network.sendRequest(method, url, headers, data);
  if (res.status < 200 || res.status >= 300) {
    throw sourceError('NETWORK', 'HTTP ' + res.status);
  }
  try {
    return JSON.parse(res.body);
  } catch (e) {
    throw sourceError('PARSE', 'response is not JSON (status ' + res.status + ')');
  }
}

class MusicSourceBase {
  constructor() {
    this.name = '';
    this.key = '';
    this.version = '';
    this.baseUrl = '';
    this.formHeaders = { 'content-type': 'application/x-www-form-urlencoded' };
  }

  loadData(key) {
    return sendMessage({ method: 'load_data', key: this.key, data_key: key });
  }
  saveData(key, data) {
    return sendMessage({ method: 'save_data', key: this.key, data_key: key, data: data });
  }
  deleteData(key) {
    return sendMessage({ method: 'delete_data', key: this.key, data_key: key, });
  }
  init() {}

  /// 表单 POST → JSON（绝大多数音乐接口的形状）。
  async postForm(path, form) {
    const url = /^https?:\/\//.test(path) ? path : this.baseUrl + path;
    return fetchJson('POST', url, this.formHeaders, formEncode(form));
  }

  async getJson(path, headers) {
    // path 兼容绝对 URL（酷狗等平台跨子域调用）与相对路径两种写法。
    const url = /^https?:\/\//.test(path) ? path : this.baseUrl + path;
    return fetchJson('GET', url, headers || {});
  }

  /// 质量档映射辅助：App 传 standard/high/lossless/hires/master。
  levelsFor(quality, map) {
    const m = map || {
      standard: ['standard', 'higher', 'exhigh'],
      high: ['exhigh', 'higher', 'standard'],
      lossless: ['lossless', 'exhigh', 'standard'],
      hires: ['hires', 'lossless', 'exhigh'],
      master: ['jymaster', 'hires', 'lossless'],
    };
    return m[quality] || m.standard;
  }
}

function log(level, title, content) {
  sendMessage({ method: 'log', level: level, title: title, content: content });
}

globalThis.APP = APP;
