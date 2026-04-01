import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:open_file/open_file.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:convert';

/// 利用可能なアップデート情報
class UpdateInfo {
  final String versionName;
  final int versionCode;
  final String downloadUrl;
  final String releaseNotes;
  final String releasedAt;

  const UpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.downloadUrl,
    required this.releaseNotes,
    required this.releasedAt,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      versionName: json['version_name'] as String? ?? '',
      versionCode: (json['version_code'] as num?)?.toInt() ?? 0,
      downloadUrl: json['download_url'] as String? ?? '',
      releaseNotes: json['release_notes'] as String? ?? '',
      releasedAt: json['released_at'] as String? ?? '',
    );
  }
}

/// アプリの自動アップデートを管理するシングルトンサービス。
///
/// 責務:
///   - GitHub Releases の latest.json からバージョン情報を取得
///   - 現在のバージョンと比較し、アップデートが必要か判定
///   - APK のダウンロードと進捗通知
///   - システムインストーラーの起動
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  /// ダウンロード進捗 (0.0 〜 1.0)。UI側は ValueListenableBuilder でリッスンする。
  final ValueNotifier<double> downloadProgress = ValueNotifier(0.0);

  /// ダウンロード中かどうか
  final ValueNotifier<bool> isDownloading = ValueNotifier(false);

  // ------------------------------------------------------------------
  // アップデート確認
  // ------------------------------------------------------------------

  /// GitHub Releases の latest.json を取得し、現在のバージョンと比較する。
  ///
  /// アップデートがある場合は [UpdateInfo] を返す。
  /// 最新バージョン使用中または取得失敗の場合は null を返す。
  Future<UpdateInfo?> checkForUpdate() async {
    // Android 専用機能（Web では Platform.isAndroid が使用不可のため先にチェック）
    if (kIsWeb || !Platform.isAndroid) return null;

    try {
      final latestJsonUrl = dotenv.env['GITHUB_LATEST_JSON_URL'];
      if (latestJsonUrl == null || latestJsonUrl.isEmpty) {
        debugPrint('⚠️ AppUpdateService: GITHUB_LATEST_JSON_URL が設定されていません');
        return null;
      }

      // latest.json を取得
      final response = await http
          .get(Uri.parse(latestJsonUrl))
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        debugPrint('⚠️ AppUpdateService: latest.json の取得失敗 (${response.statusCode})');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final updateInfo = UpdateInfo.fromJson(json);

      // 現在のバージョンコードと比較
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersionCode = int.tryParse(packageInfo.buildNumber) ?? 0;

      debugPrint(
        '📦 AppUpdateService: 現在=${packageInfo.version}+$currentVersionCode, '
        '最新=${updateInfo.versionName}+${updateInfo.versionCode}',
      );

      if (updateInfo.versionCode > currentVersionCode) {
        return updateInfo;
      }

      return null;
    } catch (e) {
      debugPrint('❌ AppUpdateService.checkForUpdate: $e');
      return null;
    }
  }

  // ------------------------------------------------------------------
  // APK ダウンロード
  // ------------------------------------------------------------------

  /// APK をダウンロードしてキャッシュディレクトリに保存する。
  ///
  /// 戻り値: 保存先ファイルパス。失敗時は null。
  Future<String?> downloadApk(String downloadUrl) async {
    try {
      isDownloading.value = true;
      downloadProgress.value = 0.0;

      final cacheDir = await getTemporaryDirectory();
      final savePath = '${cacheDir.path}/SabaTube_update.apk';
      final file = File(savePath);

      // ストリーミングダウンロードで進捗を追跡
      final request = http.Request('GET', Uri.parse(downloadUrl));
      final response = await request.send().timeout(const Duration(minutes: 10));

      if (response.statusCode != 200) {
        debugPrint('❌ AppUpdateService: APK ダウンロード失敗 (${response.statusCode})');
        return null;
      }

      final totalBytes = response.contentLength ?? 0;
      int receivedBytes = 0;

      final sink = file.openWrite();
      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes += chunk.length;
        if (totalBytes > 0) {
          downloadProgress.value = receivedBytes / totalBytes;
        }
      }
      await sink.close();

      downloadProgress.value = 1.0;
      debugPrint('✅ AppUpdateService: APK ダウンロード完了 → $savePath');
      return savePath;
    } catch (e) {
      debugPrint('❌ AppUpdateService.downloadApk: $e');
      return null;
    } finally {
      isDownloading.value = false;
    }
  }

  // ------------------------------------------------------------------
  // インストール
  // ------------------------------------------------------------------

  /// ダウンロード済み APK をシステムのインストーラーで開く。
  Future<void> installApk(String filePath) async {
    try {
      final result = await OpenFile.open(filePath, type: 'application/vnd.android.package-archive');
      debugPrint('📲 AppUpdateService: インストーラー起動 → ${result.message}');
    } catch (e) {
      debugPrint('❌ AppUpdateService.installApk: $e');
    }
  }
}
