/// 有道错误码 → 统一错误码 + 用户可读文案（D-050）。
///
/// ## 来源
/// 逐条照抄 `miao-dock/src-tauri/src/mangasvc/translate/errors.rs` 的
/// `YOUDAO_TEXT_CODES` / `YOUDAO_LLM_CODES`，文案不改写 —— 用户看到的话术应与原项目一致。
///
/// ## 为什么两张表
/// 文本接口（`/api`）与大模型接口（`/proxy/http/llm-trans`）的码表**不同**：
/// - `205` / `203` 只在文本表里；
/// - `902000` / `1` 只在大模型表里。
/// 用错表会把「没开通大模型翻译」误报成别的错误，所以表必须按接口分开。
library;

/// 一条错误码映射：上游码 → (统一码, 文案)。
typedef YoudaoCode = (String code, String message);

/// 文本翻译接口码表。
const Map<String, YoudaoCode> youdaoTextCodes = {
  '101': ('TRANSLATE_INVALID_INPUT', '上游报告缺少必填参数'),
  '102': ('TRANSLATE_INVALID_INPUT', '上游不支持该翻译方向'),
  '103': ('TRANSLATE_TEXT_TOO_LONG', '待翻译文本超过上游单次长度上限（5000 字符）'),
  '108': ('TRANSLATE_AUTH_FAILED', '应用 ID（appKey）无效'),
  '110': ('TRANSLATE_AUTH_FAILED', '应用不存在或未生效'),
  '112': ('TRANSLATE_AUTH_FAILED', '所请求的翻译服务不存在'),
  '116': ('TRANSLATE_INVALID_INPUT', '上游报告参数无效'),
  '202': ('TRANSLATE_AUTH_FAILED', '签名校验失败（appSecret 或签名算法有误）'),
  '203': ('TRANSLATE_AUTH_FAILED', '来源 IP 不在应用的白名单内'),
  '205': ('TRANSLATE_AUTH_FAILED', '应用平台类型与请求不一致'),
  '206': ('TRANSLATE_AUTH_FAILED', '时间戳无效（本地时钟偏差过大）'),
  // 重放：本仓硬约束是「每次请求（含重试）重算 salt + curtime + sign」——
  // 撞 207 先怀疑我们自己复用了签名，而不是上游不稳（方案 §7.3）。
  '207': ('TRANSLATE_AUTH_FAILED', '重复请求被上游拒绝（salt/curtime 必须每次重新生成）'),
  '301': ('TRANSLATE_UPSTREAM_ERROR', '上游词典查询失败'),
  '302': ('TRANSLATE_UPSTREAM_ERROR', '上游翻译查询失败'),
  '303': ('TRANSLATE_UPSTREAM_ERROR', '上游服务端异常'),
  '304': ('TRANSLATE_UPSTREAM_ERROR', '上游翻译失败'),
  '308': ('TRANSLATE_INVALID_INPUT', '上游报告参数无效'),
  '309': ('TRANSLATE_INVALID_INPUT', '领域（domain）参数错误'),
  '310': ('TRANSLATE_UNSUPPORTED_FEATURE', '该翻译领域未开通'),
  '401': ('TRANSLATE_QUOTA_EXCEEDED', '账户欠费，请充值后重试'),
  '411': ('TRANSLATE_RATE_LIMITED', '请求频率超过上游限制，请稍后再试'),
  '412': ('TRANSLATE_RATE_LIMITED', '请求字符数超过上游限额，请稍后再试'),
};

/// 大模型翻译接口码表（比文本表短，且码值不同）。
const Map<String, YoudaoCode> youdaoLlmCodes = {
  '1': ('TRANSLATE_UPSTREAM_ERROR', '上游未知错误'),
  '101': ('TRANSLATE_INVALID_INPUT', '上游报告缺少必填参数'),
  '108': ('TRANSLATE_AUTH_FAILED', '应用 ID（appKey）无效'),
  '110': ('TRANSLATE_AUTH_FAILED', '应用没有该接口的权限'),
  '112': ('TRANSLATE_AUTH_FAILED', '所请求的翻译服务不存在'),
  '202': ('TRANSLATE_AUTH_FAILED', '签名校验失败（appSecret 或签名算法有误）'),
  '206': ('TRANSLATE_AUTH_FAILED', '时间戳无效（本地时钟偏差过大）'),
  '207': ('TRANSLATE_AUTH_FAILED', '重复请求被上游拒绝（salt/curtime 必须每次重新生成）'),
  '902000': ('TRANSLATE_UPSTREAM_ERROR', '上游大模型翻译调用失败'),
};

/// 统一错误。
class TranslateError {
  const TranslateError(this.code, this.message, {this.upstreamCode, this.api = ''});

  /// 统一码（`TRANSLATE_*`）。
  final String code;

  /// 用户可读文案。
  final String message;

  /// 上游原始码（便于排障；未登记码也有值）。
  final String? upstreamCode;

  /// `text` / `llm`。
  final String api;

  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    if (upstreamCode != null) 'upstreamCode': upstreamCode,
    if (api.isNotEmpty) 'api': api,
  };
}

/// 把上游码映射成统一错误。
///
/// 未登记码**不吞掉**：文案里带上平台、接口与原始码，否则用户只会看到「翻译失败」，
/// 而排障时最需要的恰恰是那个码。
TranslateError mapYoudaoCode(String code, {required String api}) {
  final table = api == 'llm' ? youdaoLlmCodes : youdaoTextCodes;
  final hit = table[code];
  if (hit != null) {
    return TranslateError(hit.$1, hit.$2, upstreamCode: code, api: api);
  }
  return TranslateError(
    'TRANSLATE_UPSTREAM_ERROR',
    '上游返回未登记的错误码 $code（平台 youdaoZhiYun 接口 $api）',
    upstreamCode: code,
    api: api,
  );
}
