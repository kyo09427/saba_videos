-- ============================================
-- プレイリスト機能 マイグレーション (v1.6.0)
-- ============================================
-- このSQLをSupabaseダッシュボードのSQL Editorで実行してください
-- 既存テーブル（videos, profiles, tags, video_tags, subscriptions）とコンフリクトしません

-- 1. playlistsテーブルを作成
CREATE TABLE IF NOT EXISTS playlists (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE NOT NULL,
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  CONSTRAINT playlists_name_length CHECK (char_length(name) >= 1 AND char_length(name) <= 50)
);

-- インデックス
CREATE INDEX IF NOT EXISTS playlists_user_id_idx ON playlists(user_id);
CREATE INDEX IF NOT EXISTS playlists_created_at_idx ON playlists(created_at DESC);

-- RLS有効化
ALTER TABLE playlists ENABLE ROW LEVEL SECURITY;

-- 認証済みユーザーは全プレイリストを閲覧可能
DROP POLICY IF EXISTS "認証済みユーザーは全プレイリストを閲覧可能" ON playlists;
CREATE POLICY "認証済みユーザーは全プレイリストを閲覧可能"
  ON playlists FOR SELECT
  USING (auth.role() = 'authenticated');

-- 本人のみプレイリストを作成可能
DROP POLICY IF EXISTS "本人のみプレイリストを作成可能" ON playlists;
CREATE POLICY "本人のみプレイリストを作成可能"
  ON playlists FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- 本人のみプレイリストを更新可能
DROP POLICY IF EXISTS "本人のみプレイリストを更新可能" ON playlists;
CREATE POLICY "本人のみプレイリストを更新可能"
  ON playlists FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- 本人のみプレイリストを削除可能
DROP POLICY IF EXISTS "本人のみプレイリストを削除可能" ON playlists;
CREATE POLICY "本人のみプレイリストを削除可能"
  ON playlists FOR DELETE
  USING (auth.uid() = user_id);


-- 2. playlist_videosテーブルを作成（多対多リレーション）
CREATE TABLE IF NOT EXISTS playlist_videos (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  playlist_id UUID REFERENCES playlists(id) ON DELETE CASCADE NOT NULL,
  video_id UUID REFERENCES videos(id) ON DELETE CASCADE NOT NULL,
  added_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(playlist_id, video_id)   -- 同じ組み合わせの重複を防ぐ
);

-- インデックス
CREATE INDEX IF NOT EXISTS playlist_videos_playlist_id_idx ON playlist_videos(playlist_id);
CREATE INDEX IF NOT EXISTS playlist_videos_video_id_idx ON playlist_videos(video_id);
CREATE INDEX IF NOT EXISTS playlist_videos_added_at_idx ON playlist_videos(added_at DESC);

-- RLS有効化
ALTER TABLE playlist_videos ENABLE ROW LEVEL SECURITY;

-- 認証済みユーザーは全 playlist_videos を閲覧可能
DROP POLICY IF EXISTS "認証済みユーザーは全playlist_videosを閲覧可能" ON playlist_videos;
CREATE POLICY "認証済みユーザーは全playlist_videosを閲覧可能"
  ON playlist_videos FOR SELECT
  USING (auth.role() = 'authenticated');

-- プレイリスト所有者のみ動画を追加可能
DROP POLICY IF EXISTS "プレイリスト所有者のみ動画を追加可能" ON playlist_videos;
CREATE POLICY "プレイリスト所有者のみ動画を追加可能"
  ON playlist_videos FOR INSERT
  WITH CHECK (
    auth.uid() = (
      SELECT user_id FROM playlists WHERE id = playlist_id
    )
  );

-- プレイリスト所有者のみ動画を削除可能
DROP POLICY IF EXISTS "プレイリスト所有者のみ動画を削除可能" ON playlist_videos;
CREATE POLICY "プレイリスト所有者のみ動画を削除可能"
  ON playlist_videos FOR DELETE
  USING (
    auth.uid() = (
      SELECT user_id FROM playlists WHERE id = playlist_id
    )
  );
