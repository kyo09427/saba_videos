-- ============================================================
-- Web FCM トークン対応マイグレーション
--
-- 実行手順:
--   Supabase ダッシュボード > SQL Editor に貼り付けて実行
-- ============================================================

-- 1. profiles テーブルに web_fcm_token カラムを追加
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS web_fcm_token TEXT;

-- 2. インデックスを追加（送信対象の絞り込みを高速化）
CREATE INDEX IF NOT EXISTS profiles_web_fcm_token_idx
  ON profiles (id)
  WHERE web_fcm_token IS NOT NULL;

-- 3. トリガー関数を更新
--    Android (fcm_token) と Web (web_fcm_token) の両方にプッシュ通知を送信する
CREATE OR REPLACE FUNCTION push_notify_on_new_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  recipient_fcm_token     TEXT;
  recipient_web_fcm_token TEXT;
  supabase_url            TEXT;
  service_role_key        TEXT;
  edge_url                TEXT;
BEGIN
  -- 受信者の Android / Web FCM トークンを両方取得
  SELECT fcm_token, web_fcm_token
  INTO recipient_fcm_token, recipient_web_fcm_token
  FROM profiles
  WHERE id = NEW.user_id;

  -- どちらのトークンも未登録の場合はスキップ
  IF recipient_fcm_token IS NULL AND recipient_web_fcm_token IS NULL THEN
    RETURN NEW;
  END IF;

  -- データベース設定から Supabase 接続情報を取得
  supabase_url     := current_setting('app.supabase_url', TRUE);
  service_role_key := current_setting('app.supabase_service_role_key', TRUE);

  IF supabase_url IS NULL OR service_role_key IS NULL THEN
    RAISE WARNING 'push_notify: app.supabase_url または app.supabase_service_role_key が未設定です';
    RETURN NEW;
  END IF;

  edge_url := supabase_url || '/functions/v1/send-push-notification';

  -- Android トークンへ送信
  IF recipient_fcm_token IS NOT NULL THEN
    PERFORM net.http_post(
      url     := edge_url,
      body    := jsonb_build_object(
                   'token',    recipient_fcm_token,
                   'title',    NEW.title,
                   'body',     NEW.body,
                   'data',     COALESCE(NEW.data, '{}'::jsonb),
                   'platform', 'android'
                 )::text,
      headers := jsonb_build_object(
                   'Content-Type',  'application/json',
                   'Authorization', 'Bearer ' || service_role_key
                 )
    );
  END IF;

  -- Web トークンへ送信
  IF recipient_web_fcm_token IS NOT NULL THEN
    PERFORM net.http_post(
      url     := edge_url,
      body    := jsonb_build_object(
                   'token',    recipient_web_fcm_token,
                   'title',    NEW.title,
                   'body',     NEW.body,
                   'data',     COALESCE(NEW.data, '{}'::jsonb),
                   'platform', 'web'
                 )::text,
      headers := jsonb_build_object(
                   'Content-Type',  'application/json',
                   'Authorization', 'Bearer ' || service_role_key
                 )
    );
  END IF;

  RETURN NEW;
END;
$$;
