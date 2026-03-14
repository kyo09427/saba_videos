/// プレイリストデータモデル
library;

import 'package:flutter/foundation.dart';

/// プレイリスト（基本情報）
@immutable
class Playlist {
  final String id;
  final String userId;
  final String name;
  final DateTime createdAt;

  const Playlist({
    required this.id,
    required this.userId,
    required this.name,
    required this.createdAt,
  });

  factory Playlist.fromJson(Map<String, dynamic> json) {
    return Playlist(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'user_id': userId,
        'name': name,
      };

  @override
  bool operator ==(Object other) =>
      identical(this, other) || (other is Playlist && other.id == id);

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Playlist(id: $id, name: $name)';
}

/// プレイリスト（メタ情報付き）
///
/// チャンネル画面のプレイリスト一覧表示用。
/// サムネイル（最新動画）と動画本数を含みます。
@immutable
class PlaylistWithMeta {
  final Playlist playlist;

  /// プレイリスト内の動画本数
  final int videoCount;

  /// 最新動画のサムネイルURL（動画がない場合はnull）
  final String? thumbnailUrl;

  const PlaylistWithMeta({
    required this.playlist,
    required this.videoCount,
    this.thumbnailUrl,
  });

  String get id => playlist.id;
  String get userId => playlist.userId;
  String get name => playlist.name;
  DateTime get createdAt => playlist.createdAt;

  /// 「N本の動画」形式の表示文字列
  String get videoCountLabel => '$videoCount本の動画';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistWithMeta && other.playlist.id == playlist.id);

  @override
  int get hashCode => playlist.id.hashCode;
}
