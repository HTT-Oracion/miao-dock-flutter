import 'dart:convert';

import 'package:dio/dio.dart';

import 'music_api_error.dart';

/// 音乐平台 HTTP 传输层（四平台共用）。
///
/// 职责边界：拼请求、注入平台头、把网络 / 解析失败收敛成 [MusicApiException]。
/// 不做业务解析、不做缓存、不伪造空数据 —— 各平台客户端自行解释响应体。
///
/// 平台接口是**第三方站点**，不是本项目自有服务：它们对 UA / Referer 敏感，
/// 缺少平台头会直接回 4xx 或空 JSON，所以头由各客户端在构造时给定。
class MusicHttp {
  MusicHttp({
    required this.platform,
    Dio? dio,
    Map<String, String> headers = const {},
    Duration connectTimeout = const Duration(seconds: 8),
    Duration receiveTimeout = const Duration(seconds: 15),
  }) : _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: connectTimeout,
               receiveTimeout: receiveTimeout,
               validateStatus: (_) => true,
               headers: {'Accept': 'application/json,text/plain,*/*', ...headers},
             ),
           ) {
    if (dio != null) _dio.options.headers.addAll(headers);
  }

  /// 平台标识（错误归因 / 诊断用）。
  final String platform;
  final Dio _dio;

  Dio get dio => _dio;

  /// GET JSON。非 2xx、非 JSON 一律抛 [MusicApiException]。
  ///
  /// [headers] 用于个别接口需要覆盖平台默认头（如酷狗登录接口要 Android UA 与来源标识头）。
  Future<dynamic> getJson(String url, {Map<String, dynamic>? query, Map<String, String>? headers}) async {
    try {
      final resp = await _dio.get<String>(
        url,
        queryParameters: query,
        options: Options(responseType: ResponseType.plain, headers: headers),
      );
      return _decode(resp, url);
    } on MusicApiException {
      rethrow;
    } on DioException catch (e) {
      throw MusicApiException.network(platform, e.message ?? '${e.type}', cause: e);
    }
  }

  /// POST 表单（网易云 / QQ 多数接口是表单或 JSON 体）。
  Future<dynamic> postForm(String url, Map<String, dynamic> form) async {
    try {
      final resp = await _dio.post<String>(
        url,
        data: Map<String, dynamic>.from(form)..removeWhere((_, v) => v == null),
        options: Options(responseType: ResponseType.plain, contentType: Headers.formUrlEncodedContentType),
      );
      return _decode(resp, url);
    } on MusicApiException {
      rethrow;
    } on DioException catch (e) {
      throw MusicApiException.network(platform, e.message ?? '${e.type}', cause: e);
    }
  }

  /// POST JSON 体（QQ musicu 接口）。
  Future<dynamic> postJson(String url, Object body) async {
    try {
      final text = body is String ? body : jsonEncode(body);
      final resp = await _dio.post<String>(
        url,
        data: text,
        options: Options(responseType: ResponseType.plain, contentType: 'application/json'),
      );
      return _decode(resp, url);
    } on MusicApiException {
      rethrow;
    } on DioException catch (e) {
      throw MusicApiException.network(platform, e.message ?? '${e.type}', cause: e);
    }
  }

  /// 原始字节（咪咕播放地址响应体是逐字节混淆流，不能按文本读）。
  Future<List<int>> getBytes(String url, {Map<String, dynamic>? query}) async {
    try {
      final resp = await _dio.get<List<int>>(
        url,
        queryParameters: query,
        options: Options(responseType: ResponseType.bytes),
      );
      final status = resp.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        throw MusicApiException.http(platform, status, url);
      }
      return resp.data ?? const [];
    } on MusicApiException {
      rethrow;
    } on DioException catch (e) {
      throw MusicApiException.network(platform, e.message ?? '${e.type}', cause: e);
    }
  }

  /// 纯文本（歌词 / 接口返回非 JSON 时用）。
  Future<String> getText(String url, {Map<String, String>? headers}) async {
    try {
      final resp = await _dio.get<String>(
        url,
        options: Options(responseType: ResponseType.plain, headers: headers),
      );
      final status = resp.statusCode ?? 0;
      if (status < 200 || status >= 300) {
        throw MusicApiException.http(platform, status, url);
      }
      return resp.data ?? '';
    } on MusicApiException {
      rethrow;
    } on DioException catch (e) {
      throw MusicApiException.network(platform, e.message ?? '${e.type}', cause: e);
    }
  }

  dynamic _decode(Response<String> resp, String url) {
    final status = resp.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw MusicApiException.http(platform, status, url);
    }
    final text = resp.data ?? '';
    if (text.trim().isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException catch (e) {
      throw MusicApiException.parse(platform, url, cause: e);
    }
  }
}
