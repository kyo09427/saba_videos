-- ============================================
-- 動画メタデータ機能 マイグレーション (v1.7.0)
-- ============================================
-- このSQLをSupabaseダッシュボードのSQL Editorで実行してください
-- 既存テーブル（videos, profiles, tags, video_tags, subscriptions, playlists, playlist_videos）
-- とコンフリクトしません。

-- 1. videosテーブルに duration カラムを追加（例: "12:45" や "1:23:45"）
ALTER TABLE videos
ADD COLUMN IF NOT EXISTS duration TEXT;

-- 2. videosテーブルに youtube_title カラムを追加
--    （oEmbed APIで取得したYouTube上の実際のタイトルを保存）
ALTER TABLE videos
ADD COLUMN IF NOT EXISTS youtube_title TEXT;

-- インデックスは不要（テキスト検索には使わないため）

-- 確認クエリ（実行後にコメントアウトしてください）
-- SELECT column_name, data_type FROM information_schema.columns
-- WHERE table_name = 'videos' ORDER BY ordinal_position;
