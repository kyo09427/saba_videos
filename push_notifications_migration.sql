-- ============================================================
-- プッシュ通知対応マイグレーション
-- 実行日: 実行前に以下の前提条件を確認してください
--
-- 【前提条件】
-- 1. Supabase ダッシュボード > Database > Extensions で
--    「pg_net」を有効化してください。
--
-- 2. Supabase ダッシュボード > SQL Editor で以下を実行し、
--    データベース設定を行ってください:
--
--    ALTER DATABASE postgres
--      SET app.supabase_url = 'https://xxxxxxxxxxxx.supabase.co';
--    ALTER DATABASE postgres
--      SET app.supabase_service_role_key = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';
--
--    ※ supabase_url は Supabase ダッシュボード > Settings > API > Project URL
--    ※ supabase_service_role_key は Settings > API > service_role key
--
-- 3. Supabase Edge Function のデプロイ（DEPLOYMENT.md参照）
-- ============================================================

-- ------------------------------------------------------------
-- 1. profiles テーブルに FCM トークンカラムを追加
-- ------------------------------------------------------------
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS fcm_token TEXT;

CREATE INDEX IF NOT EXISTS profiles_fcm_token_idx
  ON profiles (id)
  WHERE fcm_token IS NOT NULL;

-- ------------------------------------------------------------
-- 2. トリガー関数: notifications INSERT 時にプッシュ通知を送信
--    pg_net で Edge Function を非同期呼び出し
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION push_notify_on_new_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  recipient_fcm_token TEXT;
  supabase_url        TEXT;
  service_role_key    TEXT;
BEGIN
  -- 受信者のFCMトークンを取得
  SELECT fcm_token INTO recipient_fcm_token
  FROM profiles
  WHERE id = NEW.user_id;

  -- FCMトークン未登録の場合はスキップ
  IF recipient_fcm_token IS NULL THEN
    RETURN NEW;
  END IF;

  -- データベース設定からSupabase接続情報を取得
  supabase_url     := current_setting('app.supabase_url', TRUE);
  service_role_key := current_setting('app.supabase_service_role_key', TRUE);

  -- 設定が未登録の場合はスキップ（上記の前提条件2を実行してください）
  IF supabase_url IS NULL OR service_role_key IS NULL THEN
    RAISE WARNING 'push_notify: app.supabase_url または app.supabase_service_role_key が未設定です';
    RETURN NEW;
  END IF;

  -- Edge Function を非同期で呼び出す（pg_net）
  PERFORM net.http_post(
    url     := supabase_url || '/functions/v1/send-push-notification',
    body    := jsonb_build_object(
                 'token', recipient_fcm_token,
                 'title', NEW.title,
                 'body',  NEW.body,
                 'data',  COALESCE(NEW.data, '{}'::jsonb)
               )::text,
    headers := jsonb_build_object(
                 'Content-Type',  'application/json',
                 'Authorization', 'Bearer ' || service_role_key
               )
  );

  RETURN NEW;
END;
$$;

-- ------------------------------------------------------------
-- 3. トリガー: notifications INSERT 後に発火
-- ------------------------------------------------------------
DROP TRIGGER IF EXISTS on_notification_push ON notifications;

CREATE TRIGGER on_notification_push
  AFTER INSERT ON notifications
  FOR EACH ROW
  EXECUTE FUNCTION push_notify_on_new_notification();
