# Discordログイン修正後の Supabase 設定手順

## ⚠️ この手順を必ず実行してください

Discord ログインを正しく動作させるために、以下の手順を順番に実行してください。

---

## 手順 1: DBマイグレーション実行

Supabaseダッシュボード > **SQL Editor** を開いて、以下のSQLを実行します。

```sql
-- Discord ギルド検証フラグを profiles テーブルに追加
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS discord_guild_verified BOOLEAN DEFAULT FALSE;

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS discord_guild_verified_at TIMESTAMPTZ;
```

> **確認方法**: Table Editor > profiles テーブルに `discord_guild_verified` と `discord_guild_verified_at` カラムが表示されればOKです。

---

## 手順 2: Redirect URLs の設定

Supabaseダッシュボード > **Authentication** > **URL Configuration** を開きます。

### Site URL
```
https://sabatube.okasis.win
```

### Redirect URLs（許可リストに以下を全て追加）

| URL | 用途 |
|-----|------|
| `https://sabatube.okasis.win` | Web版本番環境 |
| `win.okasis.sabatube://login-callback` | Android / iOS アプリ |
| `http://localhost:*` | 開発環境（Chrome）|

※ 各URLを入力後、**Add URL** ボタンを押すこと

---

## 手順 3: Discord OAuth Provider 設定確認

Supabaseダッシュボード > **Authentication** > **Providers** > **Discord** を開きます。

以下が設定されていることを確認してください：

- ✅ **Enabled**: ON
- **Client ID**: Discord Developer Portal で取得したClient ID
- **Client Secret**: Discord Developer Portal で取得したClient Secret

### Discord Developer Portal でのコールバックURL設定

Discord Developer Portal (https://discord.com/developers/applications) を開き、
該当アプリの **OAuth2** > **Redirects** に以下が登録されていることを確認：

```
https://vqvyyyqhtbgxtmknuigf.supabase.co/auth/v1/callback
```

---

## 手順 4: 設定後の動作確認

1. **Web版** (`https://sabatube.okasis.win`):
   - 「Discordでログイン」ボタンをタップ
   - Discordの認証画面が開く
   - 認証後、アプリに戻ってホーム画面が表示されればOK

2. **開発環境** (`http://localhost:*`):
   - 同様にDiscordログインを試してみる

3. **Androidアプリ**:
   - ビルドし直してから「Discordでログイン」をタップ
   - Discord認証後、アプリに戻ってくることを確認
   - ※ localhostに飛ばされなくなるはず

---

## トラブルシューティング

### 「Discord認証の設定を確認してください」/ `Unable to exchange external code` エラーが発生する

このエラーはSupabaseがDiscordのトークン交換に失敗した場合に発生します。以下を順番に確認してください：

**① Discord Developer Portalのリダイレクト URI を確認**

Discord Developer Portal (https://discord.com/developers/applications) を開き、
該当アプリの **OAuth2** > **Redirects** に以下が登録されていることを確認：

```
https://<your-supabase-project-ref>.supabase.co/auth/v1/callback
```

> ⚠️ 正確なSupabaseプロジェクトURLはSupabaseダッシュボードの **Settings** > **API** で確認できます。
> アプリのエラー画面にも正確なURLが表示されます。

**② Supabase の Discord プロバイダー設定を確認**

Supabaseダッシュボード > **Authentication** > **Providers** > **Discord** を開き：
- ✅ **Enabled**: ON になっているか
- **Client ID**: Discord Developer Portalの「OAuth2 > Client ID」と一致しているか
- **Client Secret**: Discord Developer Portalの「OAuth2 > Client Secret」と一致しているか
  - Secretは再生成すると古い値が無効になります。再生成した場合はSupabaseも更新が必要です。

---

### 「指定のDiscordサーバーに参加していないため、ログインできません」と表示される
- Discord サーバー（Guild ID: `1195727435333894144`）に参加していることを確認

### 「Discordサーバーのメンバーシップが確認できません。再度ログインしてください。」と表示される
- 一度ログアウト → 再度Discordでログインする
- DBマイグレーション (手順1) が実行済みか確認

### モバイルで認証後もlocalhostに飛ばされる
- AndroidManifest.xml / Info.plist のDeep Link設定が反映されるよう、アプリを完全に再ビルドしてください
  - Android: `flutter build apk` または `flutter run` し直す
  - iOS: Xcode Clean Build Folder 後に再実行
