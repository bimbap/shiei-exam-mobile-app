import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../config/app_config.dart';
import '../auth/token_storage.dart';
import '../update/app_update_service.dart';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio dio;
  static VoidCallback? onSessionTerminated;
  static void Function(AppUpdateInfo info)? onForceUpdateRequired;

  ApiClient._internal() {
    dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: const Duration(milliseconds: AppConfig.connectTimeoutMs),
        receiveTimeout: const Duration(milliseconds: AppConfig.receiveTimeoutMs),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (!AppConfig.isAllowedServerBaseUrl(AppConfig.baseUrl)) {
            return handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                error: 'Blocked cleartext HTTP request to non-local host: ${AppConfig.baseUrl}',
              ),
            );
          }
          options.baseUrl = AppConfig.baseUrl;
          options.headers['X-App-Version'] = AppUpdateService.currentAppVersion;
          options.headers['X-App-Build'] = AppUpdateService.currentAppBuild.toString();
          options.headers['X-App-Platform'] = Platform.isIOS ? 'ios' : (Platform.isWindows ? 'windows' : 'android');
          final token = await TokenStorage.getToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException error, handler) async {
          final path = error.requestOptions.path;
          final statusCode = error.response?.statusCode;

          if (statusCode == 426) {
            final rawData = error.response?.data;
            if (rawData is Map) {
              final payload = rawData['data'] is Map
                  ? Map<String, dynamic>.from(rawData['data'] as Map)
                  : Map<String, dynamic>.from(rawData);
              final rawInfo = AppUpdateInfo.fromJson(payload);
              final info = AppUpdateService.instance.normalizeUpdatePolicy(rawInfo);
              AppUpdateService.instance.latestUpdateInfo = info;
              if (AppUpdateService.instance.isForceUpdateRequired(info) || info.hasUpdate) {
                onForceUpdateRequired?.call(info);
              }
            }
          }

          final isAuthEndpoint = path.contains('/auth/login') ||
              path.contains('/auth/student-login') ||
              path.contains('/auth/admin-login');

          if (statusCode == 401 && !isAuthEndpoint) {
            final token = await TokenStorage.getToken();
            final hasActiveToken = token != null && token.isNotEmpty;
            if (hasActiveToken) {
              // Single active session enforcement: previous token invalidated
              debugPrint('[ApiClient] 401 Unauthorized received on $path with active token. Session terminated.');
              await TokenStorage.clearToken();
              onSessionTerminated?.call();
            }
          }
          return handler.next(error);
        },
      ),
    );
  }

  Future<Response<T>> get<T>(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return dio.get<T>(path, queryParameters: queryParameters, options: options);
  }

  Future<Response<T>> post<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return dio.post<T>(path, data: data, queryParameters: queryParameters, options: options);
  }

  Future<Response<T>> put<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return dio.put<T>(path, data: data, queryParameters: queryParameters, options: options);
  }

  Future<Response<T>> delete<T>(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) {
    return dio.delete<T>(path, data: data, queryParameters: queryParameters, options: options);
  }
}
