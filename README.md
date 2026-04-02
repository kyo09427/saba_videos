# SabaTube

仲間内でYouTubeの限定公開動画を共有し、楽しむための「秘密基地」的カタログアプリです。

## 特徴

- 🔐 **共有パスワードによる招待制**: 仲間内だけでアクセス
- 📹 **YouTube動画カタログ**: サムネイル付きで見やすい一覧表示
- 🏷️ **カテゴリ・タグ分類**: メインカテゴリ（雑談/ゲーム/音楽/ネタ/その他）とサブタグで動画を整理
- 🔍 **検索機能**: タイトル・カテゴリ・タグで横断検索（ひらがな/カタカナ区別なし）
- 👤 **ユーザープロフィール / チャンネル機能**: アバター・ユーザー名・自己紹介の設定、チャンネル登録が可能
- 📡 **登録チャンネル**: フォローしたユーザーの動画だけを絞り込んで閲覧
- 📅 **タイムライン**: 年月別に動画投稿履歴を振り返ることができるアーカイブ機能
- 🎯 **シンプルな操作**: タップでYouTubeアプリを起動
- ⚡ **リアルタイム更新**: 誰かが投稿したらすぐに反映
- ⚡ **高速表示**: TTLキャッシュでホーム・マイページ・チャンネルなどの再表示を高速化
- 📋 **プレイリスト機能**: 動画をプレイリストにまとめて整理。投稿・編集時に選択でき、チャンネルページからまとめて視聴可能
- 🔔 **アプリ内通知**: チャンネル登録しているユーザーが動画を投稿すると即座に通知が届く。未読バッジ表示・既読管理対応
- 🎨 **YouTubeライクなUI**: 使い慣れたインターフェース

## 技術スタック

- **フロントエンド**: Flutter 3.10.1+ (Dart)
- **バックエンド/DB**: Supabase
- **認証**: Supabase Auth (メールアドレス・パスワード + Discord OAuth)
- **ストレージ**: Supabase Storage (アバター画像)
- **対応プラットフォーム**: Android、iOS、Web
- **WebデプロイURL**: https://saba-videos.okasis.win

## セットアップ

### 必要な環境

- Flutter SDK 3.10.1以上
- Dart SDK 3.10.1以上
- Android Studio または Visual Studio Code
- Supabaseアカウント

### 1. リポジトリのクローン

```bash
git clone <repository-url>
cd saba_videos
```

### 2. 依存関係のインストール

```bash
flutter pub get
```

### 3. Supabaseプロジェクトの設定

#### 3.1 Supabaseプロジェクトの作成
1. [Supabase](https://supabase.com/)でアカウントを作成
2. 新しいプロジェクトを作成
3. プロジェクトURLとAnon Keyを取得
   - Settings > API から確認できます

#### 3.2 環境変数の設定
1. プロジェクトルートに `.env` ファイルを作成
2. 以下の内容を記入:

```env
# Supabase設定
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key-here

# 共有パスワード（仲間内で共有）
SHARED_PASSWORD=your-shared-password

# Discord認証（指定サーバーのGuild ID）
DISCORD_GUILD_ID=your-discord-guild-id
```

⚠️ **重要**: `.env` ファイルは `.gitignore` に含まれており、Gitで追跡されません。チーム内で安全に共有してください。

#### 3.3 データベースのセットアップ

Supabaseダッシュボードの「SQL Editor」で以下のSQLファイルを**順番に**実行してください。

| ファイル | 説明 |
|---------|------|
| `database_setup.sql` | 基本テーブル・RLS・トリガー（必須） |
| `subscriptions_migration.sql` | チャンネル登録テーブル |
| `category_tags_migration.sql` | カテゴリ・タグテーブル |
| `playlist_migration.sql` | プレイリストテーブル |
| `discord_guild_migration.sql` | Discord検証フラグ |
| `notifications_migration.sql` | **通知テーブル・DBトリガー**（アプリ内通知機能） |
| `push_notifications_migration.sql` | **FCMプッシュ通知**（後述のFirebase設定後に実行） |

`database_setup.sql` には以下が含まれています:
- **videosテーブル**: 動画情報を保存
- **profilesテーブル**: ユーザープロフィール情報（ユーザー名、アバター、自己紹介）
- **RLSポリシー**: セキュリティ設定
- **インデックス**: パフォーマンス最適化
- **トリガー**: 新規ユーザー登録時の自動プロフィール作成

**Supabase Storageの設定**:
1. Supabaseダッシュボード > Storage > Create a new bucket
2. バケット名: `avatars`
3. Public bucket: ✅ はい（チェックを入れる）
4. File size limit: 5MB
5. Allowed MIME types: `image/jpeg`, `image/png`, `image/webp`
6. Create bucket をクリック
7. `avatars` バケットの Policies タブで以下のポリシーを追加:
   - **Anyone can view avatars**: SELECT (Policy: `true`)
   - **Users can upload their own avatar**: INSERT (Policy: `bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text`)
   - **Users can update their own avatar**: UPDATE (同上)
   - **Users can delete their own avatar**: DELETE (同上)

#### 3.4 プッシュ通知のセットアップ（Android / Web）

> アプリ内通知だけ使う場合はこのセクションはスキップできます。

**① Firebase プロジェクトの作成**

1. [Firebase Console](https://console.firebase.google.com/) でプロジェクトを作成（または既存を使用）
2. 左メニュー「プロジェクトの設定」> 「マイアプリ」> Android アイコンをクリック
3. Android パッケージ名 `com.example.saba_videos` を入力して登録
4. `google-services.json` をダウンロードし `android/app/` に配置

**② FlutterFire CLI でFirebase設定ファイルを生成**

```bash
# FlutterFire CLI のインストール（初回のみ）
dart pub global activate flutterfire_cli

# Firebase設定ファイルを生成（lib/firebase_options.dart が作成される）
flutterfire configure --project=<your-firebase-project-id>
```

> `lib/firebase_options.dart` は `.gitignore` に追加することを推奨します（APIキーが含まれるため）。

**③ Supabase の pg_net 拡張を有効化**

Supabase ダッシュボード > Database > Extensions > 「pg_net」を検索して Enable

**④ データベース設定を追加**

Supabase SQL Editor で実行:

```sql
ALTER DATABASE postgres
  SET app.supabase_url = 'https://xxxxxxxxxxxx.supabase.co';
ALTER DATABASE postgres
  SET app.supabase_service_role_key = 'eyJhbGci...';
```

※ `supabase_url` は Settings > API > Project URL
※ `supabase_service_role_key` は Settings > API > service_role（⚠️ 秘密キーのため厳重に管理）

**⑤ push_notifications_migration.sql を実行**

Supabase SQL Editor で `push_notifications_migration.sql` を実行

**⑥ FCM サービスアカウントキーを取得**

1. Firebase Console > プロジェクトの設定 > サービスアカウント
2. 「新しい秘密鍵の生成」をクリック → JSON ファイルをダウンロード
3. Supabase CLI でシークレットとして登録:

```bash
# JSON ファイルの内容をそのまま渡す（改行は保持）
supabase secrets set FCM_SERVICE_ACCOUNT_KEY="$(cat path/to/service-account.json)"
```

**⑦ Edge Function のデプロイ**

```bash
# Supabase CLI のインストール（初回のみ）
# https://supabase.com/docs/guides/cli

supabase login
supabase link --project-ref xxxxxxxxxxxx
supabase functions deploy send-push-notification
```

**⑧ Web プッシュ通知の追加設定**

> Web 版でもプッシュ通知を使う場合のみ実施。

1. Firebase Console > プロジェクトの設定 > Cloud Messaging > **Web Push certificates**
2. 「鍵ペアを生成」をクリックして VAPID 公開鍵を取得
3. `lib/services/notification_service.dart` の `_kWebVapidKey` に貼り付け

```dart
// lib/services/notification_service.dart
const _kWebVapidKey = 'ここにVAPID公開鍵を貼り付け';
```

4. Supabase SQL Editor で `supabase/migrations/add_web_fcm_token.sql` を実行
   - `profiles.web_fcm_token` カラムを追加
   - Web 用トリガー `on_new_notification_web` を作成
5. `push_notify_web_on_new_notification()` 関数内の `service_key` と URL を自プロジェクトの値に変更

#### 3.5 メール認証の設定
1. Supabaseダッシュボード > Authentication > Settings
2. "Enable email confirmations" を有効化
3. メールテンプレートをカスタマイズ（オプション）

### 4. アプリの起動

```bash
# Androidエミュレータで起動
flutter run

# 特定のデバイスを指定
flutter devices  # 利用可能なデバイスを確認
flutter run -d <device-id>

# リリースビルド
flutter run --release
```

## 使い方

### 初回登録

1. アプリを起動
2. 「新規登録はこちら」をタップ
3. 以下の情報を入力:
   - メールアドレス
   - パスワード（6文字以上）
   - パスワード確認
   - 共有パスワード（仲間から共有されたもの）
4. 「登録する」ボタンをタップ
5. 登録したメールアドレスに確認メールが届く
6. メール内のリンクをクリックして認証完了
7. アプリに戻ってログイン

### ログイン

1. メールアドレスとパスワードを入力
2. 「ログイン」ボタンをタップ

### 動画の閲覧

- ホーム画面に投稿された動画が一覧表示されます
- カードをタップするとYouTubeアプリ/ブラウザで動画が開きます
- 画面を下にスワイプして最新情報に更新できます

### 動画の投稿

1. 画面下部中央の「+」ボタンをタップ
2. YouTube URLを入力
   - 入力するとプレビューが表示されます
3. 動画タイトルを入力
4. 「投稿する」ボタンをタップ

### マイページ

1. 画面下部右端の「マイページ」をタップ
2. 以下の情報を確認・設定できます:
   - プロフィール情報
   - 投稿動画数などの統計
   - 各種設定
   - ヘルプ・使い方
   - ログアウト

### チャンネル機能

- 動画カード上のアバターをタップするとそのユーザーのチャンネルページへ遷移
- チャンネルページでは投稿動画一覧・登録者数・自己紹介を表示
- 「登録」ボタンでチャンネル登録 / 登録解除が可能（自分のチャンネルでは非表示）

### 登録チャンネル

1. ボトムナビゲーションの「登録チャンネル」をタップ
2. 登録しているチャンネルの動画のみが時系列で表示されます
3. PC表示では左サイドバーからチャンネルを選択して絞り込みが可能
4. スマホ表示ではフィルターアイコンからチャンネル選択が可能
5. カテゴリフィルターで「雑談」「ゲーム」などジャンルごとに絞り込みも可能

### タイムライン

1. ボトムナビゲーションの「タイムライン」をタップ
2. 全動画を年月別にグループ表示。新しい月が上に並びます
3. PC表示では左サイドバーから年・月をクリックして該当セクションへジャンプ可能
4. スマホ表示では上部の月チップをタップして移動が可能

## プロジェクト構成

```
web/
├── index.html                              # Webエントリーポイント
├── firebase-messaging-sw.js               # Service Worker（Webバックグラウンド通知）
├── manifest.json                          # PWAマニフェスト
└── icons/                                 # アイコン画像

supabase/
├── functions/
│   └── send-push-notification/
│       └── index.ts                       # FCM HTTP v1 API 呼び出し（Android・Web対応）
└── migrations/
    └── add_web_fcm_token.sql              # web_fcm_tokenカラム追加・Webトリガー作成

lib/
├── main.dart                               # エントリーポイント
├── models/                                 # データモデル
│   ├── video.dart                         # 動画モデル（カテゴリ・タグ対応）
│   ├── user_profile.dart                  # ユーザープロフィールモデル
│   ├── subscription.dart                  # チャンネル登録モデル
│   ├── channel_stats.dart                 # チャンネル統計モデル
│   ├── notification_model.dart            # 通知モデル
│   ├── tag.dart                           # タグモデル
│   └── app_user.dart                      # ユーザーモデル
├── services/                               # サービス層
│   ├── supabase_service.dart              # Supabase接続・登録管理
│   ├── cache_service.dart                 # TTLキャッシュサービス（メモリキャッシュ）
│   ├── notification_service.dart          # アプリ内通知・未読数管理・Realtime購読
│   ├── profile_service.dart               # プロフィール取得サービス
│   └── youtube_service.dart               # YouTube関連機能
├── utils/                                  # ユーティリティ
│   └── japanese_text_utils.dart           # ひらがな/カタカナ正規化ユーティリティ
├── screens/                                # 画面
│   ├── auth/                              # 認証関連
│   │   ├── login_screen.dart              # ログイン画面
│   │   ├── register_screen.dart           # 新規登録画面
│   │   └── email_verification_screen.dart # メール確認画面
│   ├── home/
│   │   └── home_screen.dart               # ホーム画面（カテゴリフィルター・検索バー付き動画一覧）
│   ├── channel/
│   │   └── channel_screen.dart            # チャンネルページ（タブ切り替え：動画/プレイリスト）
│   ├── playlist/
│   │   └── playlist_detail_screen.dart    # プレイリスト詳細（動画一覧）
│   ├── subscriptions/
│   │   └── subscriptions_screen.dart      # 登録チャンネル一覧・動画フィード
│   ├── timeline/
│   │   └── timeline_screen.dart           # タイムライン（年月別アーカイブ）
│   ├── post/
│   │   └── post_video_screen.dart         # 投稿画面（URL入力・プレビュー）
│   ├── notifications/
│   │   └── notifications_screen.dart      # 通知一覧画面（既読管理・チャンネル遷移）
│   └── profile/
│       ├── my_page_screen.dart            # マイページ画面（キャッシュ・プルリフレッシュ対応）
│       ├── my_videos_screen.dart          # 投稿動画管理・編集（プレイリスト選択対応）
│       └── edit_profile_screen.dart       # プロフィール編集画面
└── widgets/                                # 再利用可能なウィジェット
    ├── video_card.dart                    # 動画カード（汎用）
    ├── skeleton_widgets.dart              # スケルトンローディングウィジェット（プレイリストカード対応）
    └── app_bottom_navigation_bar.dart     # ボトムナビゲーション
```

## データベーススキーマ

### videos テーブル

| カラム名 | 型 | 説明 | 制約 |
|---------|---|------|------|
| id | UUID | 主キー | PRIMARY KEY, DEFAULT gen_random_uuid() |
| created_at | TIMESTAMPTZ | 作成日時 | DEFAULT NOW() |
| title | TEXT | 動画タイトル | NOT NULL |
| url | TEXT | YouTube URL | NOT NULL |
| user_id | UUID | 投稿者のUID | REFERENCES auth.users(id), NOT NULL |
| main_category | TEXT | メインカテゴリ | NOT NULL, DEFAULT '雑談' |

### profiles テーブル

| カラム名 | 型 | 説明 |
|---------|---|------|
| id | UUID | ユーザーID（auth.users参照） |
| username | TEXT | ユーザー名 |
| avatar_url | TEXT | アバター画像URL |
| bio | TEXT | 自己紹介文 |
| created_at | TIMESTAMPTZ | 登録日時 |
| fcm_token | TEXT | Android プッシュ通知用 FCM トークン（ログイン時に自動登録・ログアウト時にクリア） |
| web_fcm_token | TEXT | Web プッシュ通知用 FCM トークン（`add_web_fcm_token.sql` で追加） |

### tags テーブル / video_tags テーブル

| テーブル | 説明 |
|---------|------|
| tags | タグマスタ（name: タグ名） |
| video_tags | 動画とタグの多対多リレーション（video_id, tag_id） |

### playlists テーブル / playlist_videos テーブル

| カラム名 | 型 | 説明 |
|---------|---|------|
| id | UUID | 主キー |
| name | TEXT | プレイリスト名 |
| user_id | UUID | 作成者のユーザーID |
| created_at | TIMESTAMPTZ | 作成日時 |

`playlist_videos` テーブルで動画とプレイリストを多対多で関連付けます（`playlist_id`, `video_id`）。
`playlist_migration.sql` を Supabase の SQL Editor で実行してください。

### subscriptions テーブル

| カラム名 | 型 | 説明 |
|---------|---|------|
| id | UUID | 主キー |
| subscriber_id | UUID | 登録者のユーザーID |
| channel_id | UUID | 登録先チャンネルのユーザーID |
| created_at | TIMESTAMPTZ | 登録日時 |

### notifications テーブル

| カラム名 | 型 | 説明 |
|---------|---|------|
| id | UUID | 主キー |
| user_id | UUID | 通知受信者のユーザーID |
| type | TEXT | 通知種別（例: `new_video`） |
| title | TEXT | 通知タイトル |
| body | TEXT | 通知本文（動画タイトル） |
| data | JSONB | 付加データ（`video_id`, `channel_id`, `channel_name`） |
| is_read | BOOLEAN | 既読フラグ（デフォルト `false`） |
| created_at | TIMESTAMPTZ | 生成日時 |

動画投稿時に PostgreSQL トリガー（`on_new_video_notify`）が自動的に購読者全員分のレコードを生成します。
`notifications_migration.sql` を Supabase の SQL Editor で実行してください。

### インデックス

- `videos_created_at_idx`: 作成日時の降順（最新順取得の高速化）
- `videos_user_id_idx`: ユーザーIDでの検索の高速化

## 主要な機能実装

### 1. 認証システム
- Supabase Authを使用したメール認証
- 共有パスワードによる招待制
- セッション管理とリアルタイム認証状態監視

### 2. リアルタイム更新
- Supabase Realtimeを使用して新規投稿を即座に反映
- PostgreSQL Changesの購読により自動更新

### 3. YouTube連携
- URLからビデオIDを自動抽出（youtube.com / youtu.be 形式対応）
- サムネイル画像の自動取得と表示
- 外部アプリ起動による動画再生

### 4. カテゴリ・タグシステム
- 動画投稿時にメインカテゴリを選択
- サブカテゴリタグを複数設定（DB保持・検索に利用）
- ホーム/登録チャンネル画面でカテゴリフィルター対応
- 動画カードにはメインカテゴリバッジのみ表示（タグは非表示でパフォーマンス確保）
- ホーム画面の検索バーでタイトル・カテゴリ・タグを横断検索可能

### 5. チャンネル機能
- 動画カードのアバタータップでチャンネルページへ遷移
- チャンネルページ: 投稿動画一覧・登録者数・登録ボタン表示
- Supabaseの subscriptions テーブルで登録状態を管理

### 6. 登録チャンネル一覧
- フォロー中のユーザーの動画だけをフィード表示
- PCでは左サイドバーでチャンネル選択、スマホではダイアログ
- カテゴリフィルターをまたいで絞り込み可能

### 7. タイムライン（年月別アーカイブ）
- 全動画を年月でグループ化して降順（新しい月が上）に表示
- PCではサイドバーで年・月のツリーナビゲーション（クリックでジャンプ）
- スマホでは横スクロール月選択チップ
- 各月の動画件数バッジ付き

### 8. レスポンシブレイアウト
- 1列表示（600px未満）: SliverListで自然な高さに自動フィット
- 2〜4列グリッド（600px〜）: 画面幅に応じた列数で表示
- PC表示では左サイドバーを追加表示（登録チャンネル・タイムライン）

### 9. キャッシュシステム
- `CacheService`（シングルトン）によるTTL付きメモリキャッシュ
- キャッシュキー: ホーム動画・タイムライン・登録チャンネル・マイページプロフィール/動画数など
- デフォルトTTL 5分。プルダウンリフレッシュまたはデータ更新時に自動無効化

### 10. 検索機能（ホーム画面）
- AppBarの虫眼鏡アイコンで検索モードに切り替え
- 検索対象: 動画タイトル・メインカテゴリ・サブカテゴリタグ
- ひらがな/カタカナを区別しない検索（`japanese_text_utils.dart`の`containsIgnoreKana`を使用）
- カテゴリフィルターと組み合わせた絞り込みも可能

### 11. エラーハンドリング
- ネットワークエラーの適切な処理
- ユーザーフレンドリーなエラーメッセージ
- null安全性の確保

### 13. アプリ内通知機能

- 動画投稿時に PostgreSQL トリガーがDBレベルで購読者全員分の通知レコードを自動生成
  - アプリ経由・直接INSERT問わず確実に発火（投稿経路に依存しない設計）
- Supabase Realtime の WebSocket で新着通知をリアルタイム受信
  - `NotificationService.unreadCount`（`ValueNotifier<int>`）をインクリメント
  - ポーリングなし・差分受信のみ
- ホーム画面のベルアイコンに未読数バッジを `ValueListenableBuilder` で動的表示
- 通知一覧画面: 最新50件表示・未読ハイライト・タップで既読＋チャンネル遷移・一括既読ボタン
- ログアウト時に Realtime 購読を解除し未読数をリセット
- 将来のプッシュ通知実装向けに `registerFcmToken()` スタブと `push_notifications_migration.sql` を用意済み

### 12. プレイリスト機能
- 動画投稿・編集時にプレイリストを選択（チップUI）
- 新規プレイリストをダイアログからその場で作成可能
- チャンネルページに「プレイリスト」タブを追加（画面幅に応じた2〜4列レスポンシブグリッド）
- プレイリスト詳細画面で収録動画を一覧表示・タップでYouTube起動
- `PlaylistService` / `CacheKeys.channelPlaylists` によるキャッシュ対応
- スケルトンスクリーンでロード中のUXを改善

## トラブルシューティング

### Supabase接続エラー

**症状**: アプリ起動時に初期化エラーが発生

**解決策**:
1. `.env` ファイルが存在し、正しい場所にあるか確認
2. `SUPABASE_URL` と `SUPABASE_ANON_KEY` が正しいか確認
3. インターネット接続を確認
4. Supabaseプロジェクトが有効か確認

### ログインできない

**症状**: メールアドレスとパスワードでログインできない

**解決策**:
1. メール確認リンクをクリックしたか確認
2. パスワードが6文字以上か確認
3. Supabaseダッシュボード > Authentication > Users でユーザーが作成されているか確認
4. ユーザーの "Email Confirmed" が true になっているか確認

### 動画が表示されない

**症状**: ホーム画面に動画が表示されない

**解決策**:
1. Supabaseダッシュボード > Table Editor > videos でデータが存在するか確認
2. RLS (Row Level Security) ポリシーが正しく設定されているか確認
3. アプリを再起動してみる
4. 下にスワイプして手動更新してみる

### YouTube動画が開けない

**症状**: 動画カードをタップしても何も起こらない

**解決策**:
1. URLが正しいYouTube URLか確認
2. 動画が削除されていないか確認
3. YouTubeアプリがインストールされているか確認
4. ブラウザで開けるか試してみる

### メールが届かない

**症状**: 登録確認メールが届かない

**解決策**:
1. 迷惑メールフォルダを確認
2. メールアドレスのスペルミスがないか確認
3. Supabaseの送信制限に達していないか確認
4. Supabaseダッシュボード > Authentication > Logs でエラーを確認

## セキュリティ

### Row Level Security (RLS)
- 認証済みユーザーのみがデータにアクセス可能
- 投稿者のみが自分の投稿を削除可能
- SQLインジェクション対策

### 共有パスワード
- 新規登録時に検証
- 環境変数で管理
- Gitで追跡されない

### 環境変数
- `.env` ファイルは `.gitignore` で除外
- 機密情報を保護
- チーム内で安全に共有

## 今後の拡張案

### 未実装・改善候補
- [ ] 投稿者名での検索
- [ ] いいね・コメント機能
- [ ] 動画の埋め込み再生
- [ ] iOS プッシュ通知対応（APNs設定・`firebase_options.dart` の iOS 設定）
- [ ] 複数デバイス同時ログイン対応（`fcm_tokens` テーブルへの移行）
- [ ] 多言語対応

## バージョン履歴

### v2.2.0 (2026-04-02) - 最新版

- **Web プッシュ通知対応**
  - 🟢 **Web FCM 実装**: `NotificationService._initFcm()` の Web スキップを解除。VAPID キー（`_kWebVapidKey`）を使用して `FirebaseMessaging.instance.getToken()` でWebトークンを取得
  - 🟢 **プラットフォーム別トークン保存**: Android → `profiles.fcm_token` / Web → `profiles.web_fcm_token` にそれぞれ保存。ログイン時に他プラットフォームのトークンをクリアして重複通知を防止
  - 🟢 **Service Worker**: `web/firebase-messaging-sw.js` を追加。バックグラウンド・タブ非アクティブ時の通知を Service Worker が受信・表示
  - 🟢 **DBトリガー**: `push_notify_web_on_new_notification()` トリガー関数を新設。`notifications` テーブルへの INSERT 時に `web_fcm_token` 宛に Edge Function を呼び出す
  - 🟢 **Edge Function 更新**: `platform: 'web'` 時に FCM メッセージへ `webpush` フィールド（アイコン・クリックURL）を追加
  - 新規ファイル: `web/firebase-messaging-sw.js`（Service Worker）
  - 新規ファイル: `supabase/migrations/add_web_fcm_token.sql`（`web_fcm_token` カラム追加）
  - ✅ **動作確認済み**: Chrome（Web）でバックグラウンドプッシュ通知のエンドツーエンド動作を確認
- **マイページ テーマ設定改善**
  - 🟢 **3択セレクターに変更**: トグルスイッチから「ライトモード / ダークモード / システムのテーマに合わせる」の選択式に変更（`lib/screens/profile/my_page_screen.dart`）
  - 🟢 **初期値変更**: デフォルトを `ThemeMode.dark` → `ThemeMode.system`（端末設定に追従）に変更
  - 🟢 **デバイスごとに設定を保存**: `SharedPreferences` に `'system'` / `'light'` / `'dark'` を保存（`lib/services/theme_service.dart`）
- **通知トグル UX 改善**
  - 🟢 **SnackBar フィードバック追加**: 通知オン→「通知をオンにしました」/ オフ→「通知をオフにしました」をアイコン付きで2秒表示（`lib/screens/profile/my_page_screen.dart`）
- **登録チャンネル画面バグ修正**
  - 🔴 **グリッドオーバーフロー修正**: `childAspectRatio`（比率計算）を廃止し `mainAxisExtent`（ピクセル直接指定）に変更。サムネイル下部の余白過多と RenderFlex オーバーフロー警告を解消（`lib/screens/subscriptions/subscriptions_screen.dart`）

### v2.1.0 (2026-04-01)
- **Web版パフォーマンス改善**
  - 🟢 **スケルトンアニメーション共有化**: `SkeletonBox` が個別に持っていた `AnimationController` を廃止し、`_ShimmerProvider`（InheritedWidget）による1つの共有コントローラに統一。リスト表示時のCPU・GPU負荷を大幅削減
  - 🟢 **タイムライン画面スクロールスロットル化**: `_onScroll` ハンドラが毎フレーム `findRenderObject()` を呼び出していた問題を修正。100ms スロットルを導入しメインスレッドの負荷を軽減
  - 🟢 **`Image.network` → `CachedNetworkImage` 置き換え**: ホーム・タイムライン・登録チャンネル画面のサムネイル画像をキャッシュ対応に変更。スクロール時の再ダウンロードを防止
  - 🟢 **`RepaintBoundary` 追加**: ホーム画面の動画リスト・グリッドの各アイテムに `RepaintBoundary` を追加し、隣接カードへの再描画の連鎖を防止
- **UI改善**
  - 🟢 **アプリアイコンの適用**: ホーム画面AppBar・ログイン画面のダミーアイコンをアプリアイコン（`icon.png`）に変更。`pubspec.yaml` のassetsに `icon.png` を追加
  - 🟢 **ログイン画面のPC表示改善**: フォームの最大幅を480pxに制限しセンタリング。PC表示での引き伸ばしを解消
  - 🟢 **グリッドカード余白の修正**: ホーム・登録チャンネル画面のグリッドで `childAspectRatio` を固定値から動的計算に変更。画面幅が広くなるほど余白が増える問題を解消（セル幅からサムネイル高さ＋情報エリア高さを逆算）

### v2.0.0 (2026-03-29)
- **Androidプッシュ通知（FCM）対応を実装**
  - 🟢 **Firebase Messaging 統合**: `firebase_core` / `firebase_messaging` を追加、`NotificationService` に FCM 初期化・権限要求・トークン管理を実装
  - 🟢 **FCM トークン自動登録**: ログイン時にデバイストークンを取得して `profiles.fcm_token` に保存、トークン更新時も自動同期
  - 🟢 **ログアウト時のトークン削除**: 他デバイスへの誤送信を防ぐため `clearFcmToken()` を実装
  - 🟢 **バックグラウンド通知**: FCM SDK がアプリ終了・バックグラウンド時にシステム通知として自動表示
  - 🟢 **フォアグラウンド通知**: アプリ起動中でもシステム通知を表示 + アプリ内未読数をインクリメント
  - 🟢 **Supabase Edge Function**: `supabase/functions/send-push-notification/index.ts` を作成。サービスアカウントJWTフローで FCM HTTP v1 API を呼び出す
  - 🟢 **DBトリガー連携**: `notifications` INSERT 時に `pg_net` で Edge Function を非同期呼び出し
  - 変更: `android/settings.gradle.kts` / `android/app/build.gradle.kts`（google-services プラグイン追加）
  - 変更: `AndroidManifest.xml`（`POST_NOTIFICATIONS` 権限追加）
  - 更新: `push_notifications_migration.sql`（fcm_tokenカラム・pg_netトリガーを実装）
  - ⚠️ **セットアップ必須**: `flutterfire configure` で `lib/firebase_options.dart` を生成すること（README 3.4 参照）
  - ✅ **動作確認済み**: Android実機でプッシュ通知のエンドツーエンド動作を確認

### v1.9.0 (2026-03-28)
- **アプリ内通知機能を実装**
  - 🟢 **DBトリガーによる通知生成**: `videos` テーブルへの INSERT 時に PostgreSQL トリガー（`on_new_video_notify`）が発火し、購読者全員に通知レコードを自動生成
  - 🟢 **Supabase Realtime でリアルタイム受信**: WebSocket 経由で新着通知をリアルタイム受信し、ベルアイコンの未読バッジを即時更新
  - 🟢 **通知一覧画面**: 最新50件表示・未読ハイライト・タップで既読＋チャンネル遷移・一括既読ボタン・プルトゥリフレッシュ対応
  - 新規ファイル: `notifications_migration.sql`（notificationsテーブル・RLS・DBトリガー）
  - 新規ファイル: `lib/models/notification_model.dart`
  - 新規ファイル: `lib/services/notification_service.dart`
  - 新規ファイル: `lib/screens/notifications/notifications_screen.dart`

### v1.8.0 (2026-03-27)
- **PC版検索機能・UIの堅牢性向上と動画再生時間対応**
  - 🔴 **PC版検索バーのクラッシュ修正**: `SearchAnchor`のドロップダウンが未展開の状態でEnterを押下すると白画面でクラッシュする問題を、`isOpen`の事前チェックとフォーカス解除で修正
  - 🟡 **PC版検索バーのUX改善**: 検索窓のクリック（`onTap`）や文字入力（`onChanged`）に連動して検索履歴ドロップダウンが自然に開くように挙動を最適化
  - 🔴 **検索履歴での重大なエラー防止**: `SharedPreferences`が返す変更不可リスト（UnmodifiableListView）を直接操作した際に発生する`UnsupportedError`を回避するため、`.toList()`で安全なコピーを操作するよう堅牢性を向上
  - 🟢 **動画再生時間の表示**: サムネイル画像右下に、YouTube URLから取得した動画の再生時間（duration）バッジを表示するよう対応（チャンネル画面・登録チャンネル画面）
  - 🟢 **Web版の仕様追加**: Webブラウザ上ではCORSの制約で再生時間の自動取得ができないため、動画投稿画面にWeb版専用の「手動入力」案内を表示
  - 🟢 **登録チャンネルの新着フィルタ変更**: 「新しい動画」の抽出基準を「24時間以内」から「7日（1週間）以内」へ拡大表示するように変更

### v1.7.0 (2026-03-27)
- **Discordログイン 全問題修正**
  - 🔴 **レースコンディション修正**: ギルド検証完了まで HomeScreen を表示しないよう AuthWrapper を改修
  - 🔴 **ギルド検証の永続化**: 検証結果を `profiles.discord_guild_verified` に保存し、セッション復帰時も DB 参照で検証（`providerToken` null 問題の解消）
  - 🔴 **フェイルクローズ化**: `DISCORD_GUILD_ID` 未設定時はログインを拒否（従来はフェイルオープン）
  - 🔴 **モバイル Deep Link 修正**: `AndroidManifest.xml` / `Info.plist` にカスタムURLスキーム (`io.supabase.sabavideos://`) を追加し、Discord OAuth後に localhost に飛ばされるバグを修正
  - 🔴 **プラットフォーム別 redirectTo 設定**: Web は `Uri.base.origin`、モバイルは `io.supabase.sabavideos://login-callback` を自動選択
  - 🟡 **Guild ID 未設定時ボタン非表示**: `DiscordAuthService.isConfigured` が false の場合、Discordログインボタンとセパレーターを非表示
  - 🟡 **エラー画面 UX 改善**: エラー画面の「ログイン画面に戻る」が正しく機能するよう状態管理を修正
  - 新規ファイル: `discord_guild_migration.sql`（profiles テーブルに検証フラグ追加）
  - 新規ファイル: `DISCORD_SETUP_GUIDE.md`（Supabase ダッシュボード設定手順）

### v1.6.0 (2026-03-15)
- **プレイリスト機能を実装**
  - `playlists` / `playlist_videos` テーブル追加（`playlist_migration.sql`）
  - `lib/models/playlist.dart`: `Playlist` / `PlaylistWithMeta` モデル
  - `lib/services/playlist_service.dart`: プレイリストCRUD・動画関連付け管理
  - 動画投稿画面（`post_video_screen.dart`）にプレイリスト選択チップUI
  - 動画編集画面（`my_videos_screen.dart`）にプレイリスト選択追加（初期値読込・保存対応）
  - 新規プレイリスト作成ダイアログ（投稿・編集どちらからも利用可能）
  - チャンネルページ（`channel_screen.dart`）に「プレイリスト」タブ追加
    - 画面幅に応じて2〜4列のレスポンシブグリッド表示
    - 各カードにサムネイル・動画本数バッジを表示
  - プレイリスト詳細画面（`playlist_detail_screen.dart`）を新規作成
    - スケルトンスクリーン・プルトゥリフレッシュ・TTLキャッシュ(3分)対応
  - スケルトンウィジェット（`skeleton_widgets.dart`）にプレイリストカード用を追加
  - `CacheKeys.channelPlaylists` によるチャンネルプレイリストのキャッシュ対応
- **UIダークモード改善**
  - 動画編集シートのプレイリスト選択チップを既存ダークパレットに統一

### v1.5.0 (2026-03-06)
- **マイページキャッシュ実装**
  - `CacheService`を使いプロフィールと動画数を5分間キャッシュ
  - プルダウンリフレッシュ（`RefreshIndicator`）対応
  - プロフィール編集後に自動でキャッシュを無効化し再取得
- **ホーム画面に検索機能を追加**
  - AppBarの虫眼鏡アイコンで検索バーをトグル表示
  - タイトル・メインカテゴリ・サブカテゴリタグを横断検索
  - ひらがな/カタカナを区別しない検索に対応（`japanese_text_utils.dart`）
  - カテゴリフィルターと組み合わせた複合絞り込みが可能
- **新規ファイル追加**
  - `lib/services/cache_service.dart`: TTLキャッシュサービス
  - `lib/utils/japanese_text_utils.dart`: 日本語テキスト正規化ユーティリティ

### v1.4.0 (2026-02-27)
- タイムライン機能を実装（ボトムナビ「ショート」→「タイムライン」に変更）
  - 年月別アーカイブ表示
  - PC: サイドバーで年・月ナビゲーション
  - スマホ: 横スクロール月選択チップ
- 動画カードのサブカテゴリタグ表示を非表示化（内部検索には継続使用）
- レスポンシブグリッドのオーバーフロー修正
  - 1列表示(スマホ)をSliverGridからSliverListに変更
  - childAspectRatioをタグなしコンテンツ高さに最適化

### v1.3.0 (2026-02-16)
- チャンネル登録機能を実装
  - チャンネル登録 / 登録解除ボタン
  - 登録者数の表示
- 登録チャンネル画面をボトムナビに追加
  - 登録チャンネルのみの動画フィード
  - PC: 左サイドバーでチャンネル選択
  - カテゴリフィルター対応

### v1.2.0 (2026-02-14)
- カテゴリ・タグシステムの実装
  - 動画投稿時にメインカテゴリ選択
  - サブカテゴリタグの付与（DB管理）
  - カテゴリフィルターによる絞り込み
- チャンネルページの追加
  - プロフィール・動画一覧・統計表示
  - 動画カードからチャンネルへ遷移
- プロフィール編集画面の追加

### v1.1.0 (2026-02-07)
- YouTubeライクなUIデザインに刷新
- マイページ機能の追加
- ボトムナビゲーションの実装
- エラーハンドリングの改善
- パフォーマンスの最適化

### v1.0.0 (初回リリース)
- 基本的な認証機能
- 動画の投稿・閲覧機能
- リアルタイム更新
- YouTubeサムネイル表示

## ライセンス

このプロジェクトは私的利用を目的としています。

## 開発者

サバの仲間たち 🐟

## サポート

問題が発生した場合や機能リクエストがある場合は、以下の方法でお知らせください:

1. GitHubのIssuesで報告
2. 開発チームに直接連絡

## 貢献

このプロジェクトは仲間内での利用を目的としていますが、改善提案は歓迎します:

1. このリポジトリをフォーク
2. 新しいブランチを作成 (`git checkout -b feature/amazing-feature`)
3. 変更をコミット (`git commit -m 'Add some amazing feature'`)
4. ブランチにプッシュ (`git push origin feature/amazing-feature`)
5. プルリクエストを作成

## 技術的な詳細

### 使用しているパッケージ

- `supabase_flutter: ^2.9.4` - Supabaseクライアント
- `url_launcher: ^6.3.1` - 外部URLの起動
- `flutter_dotenv: ^5.2.1` - 環境変数管理
- `intl: ^0.20.1` - 日付フォーマット
- `cached_network_image: ^3.4.1` - 画像キャッシング

### アーキテクチャパターン

- **サービス層**: ビジネスロジックの分離
- **モデル層**: データ構造の定義
- **UI層**: プレゼンテーション層

### パフォーマンス最適化

- 画像のキャッシング
- リアルタイム購読の適切なクリーンアップ
- 不要な再レンダリングの削減
- インデックスによるデータベースクエリの高速化

---

---

**注意**: このアプリは仲間内での利用を目的としており、公開されたアプリストアでの配布は想定していません。