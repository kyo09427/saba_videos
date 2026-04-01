import 'package:flutter/material.dart';
import '../services/app_update_service.dart';

/// アップデート通知ダイアログ。
///
/// 状態遷移:
///   1. 初期表示: バージョン情報・リリースノートを表示
///   2. ダウンロード中: プログレスバー表示（キャンセル不可）
///   3. インストール準備完了: 「インストール」ボタン表示
class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;

  const UpdateDialog({super.key, required this.updateInfo});

  /// ダイアログを表示するショートカット。
  static Future<void> show(BuildContext context, UpdateInfo info) {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => UpdateDialog(updateInfo: info),
    );
  }

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

enum _UpdateStep { prompt, downloading, readyToInstall }

class _UpdateDialogState extends State<UpdateDialog> {
  _UpdateStep _step = _UpdateStep.prompt;
  String? _downloadedPath;
  String? _errorMessage;

  final _service = AppUpdateService.instance;

  Future<void> _startDownload() async {
    setState(() {
      _step = _UpdateStep.downloading;
      _errorMessage = null;
    });

    final path = await _service.downloadApk(widget.updateInfo.downloadUrl);

    if (!mounted) return;

    if (path != null) {
      setState(() {
        _downloadedPath = path;
        _step = _UpdateStep.readyToInstall;
      });
    } else {
      setState(() {
        _step = _UpdateStep.prompt;
        _errorMessage = 'ダウンロードに失敗しました。もう一度お試しください。';
      });
    }
  }

  Future<void> _install() async {
    if (_downloadedPath == null) return;
    await _service.installApk(_downloadedPath!);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // ダウンロード中は戻るボタンを無効化
      canPop: _step != _UpdateStep.downloading,
      child: AlertDialog(
        backgroundColor: const Color(0xFF272727),
        title: Row(
          children: [
            const Icon(Icons.system_update, color: Color(0xFFF20D0D)),
            const SizedBox(width: 8),
            Text(
              'アップデートがあります',
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ],
        ),
        content: _buildContent(),
        actions: _buildActions(),
      ),
    );
  }

  Widget _buildContent() {
    return SizedBox(
      width: double.maxFinite,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // バージョン情報
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'v${widget.updateInfo.versionName}',
              style: const TextStyle(
                color: Color(0xFFF20D0D),
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // リリースノート
          if (widget.updateInfo.releaseNotes.isNotEmpty) ...[
            const Text(
              '変更内容',
              style: TextStyle(
                color: Color(0xFFAAAAAA),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.updateInfo.releaseNotes,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
            const SizedBox(height: 12),
          ],

          // ダウンロード進捗
          if (_step == _UpdateStep.downloading) ...[
            const Text(
              'ダウンロード中...',
              style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 13),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<double>(
              valueListenable: _service.downloadProgress,
              builder: (_, progress, __) {
                return Column(
                  children: [
                    LinearProgressIndicator(
                      value: progress,
                      backgroundColor: const Color(0xFF1A1A1A),
                      valueColor: const AlwaysStoppedAnimation(Color(0xFFF20D0D)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${(progress * 100).toStringAsFixed(0)}%',
                      style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 12),
                    ),
                  ],
                );
              },
            ),
          ],

          // エラーメッセージ
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Color(0xFFFF5555), fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  List<Widget> _buildActions() {
    if (_step == _UpdateStep.downloading) {
      return [
        const Padding(
          padding: EdgeInsets.only(right: 16, bottom: 8),
          child: Text(
            'ダウンロードが完了するまでお待ちください',
            style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 11),
          ),
        ),
      ];
    }

    if (_step == _UpdateStep.readyToInstall) {
      return [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('後で', style: TextStyle(color: Color(0xFFAAAAAA))),
        ),
        ElevatedButton(
          onPressed: _install,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFF20D0D),
            foregroundColor: Colors.white,
          ),
          child: const Text('インストール'),
        ),
      ];
    }

    // prompt ステップ
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('後で', style: TextStyle(color: Color(0xFFAAAAAA))),
      ),
      ElevatedButton(
        onPressed: _startDownload,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFF20D0D),
          foregroundColor: Colors.white,
        ),
        child: const Text('アップデート'),
      ),
    ];
  }
}
