# 総再生数機能 設計ドキュメント

## 概要

マイページに表示される「総再生数」は、自分が投稿した動画の YouTube 再生回数を合計して表示する機能。  
YouTube Data API v3 を使用するが、APIキーの流出を防ぐためにクライアント（Flutter）は APIキーに触れず、Supabase Edge Function をサーバー中継として利用する。

---

## アーキテクチャ

```
Flutter クライアント
    │
    │  functions.invoke('youtube-views', body: { videoUrls: [...] })
    │  ※ Supabase JWT を Authorization ヘッダーに自動付与
    ▼
Supabase Edge Function (youtube-views)  ← YOUTUBE_API_KEY はここにのみ存在
    │
    │  GET https://www.googleapis.com/youtube/v3/videos
    │      ?part=statistics&id=ID1,ID2,...&key=YOUTUBE_API_KEY
    ▼
YouTube Data API v3
```

---

## APIキー管理・セキュリティ

| 場所 | 保持するか | 理由 |
|---|---|---|
| `.env` ファイル | **持たない** | Flutter Web は `build/web/assets/.env` として公開されるため流出する |
| Flutter コード内 | **持たない** | dart2js でバンドルされるため逆コンパイルで取得可能 |
| GitHub Secrets | **持たない** | CI/CD で使う場合のみ必要。今回は不要 |
| Supabase Edge Function Secret | **ここのみ保持** | サーバーサイド専用。クライアントには絶対に返らない |

### Supabase Secret への登録方法

```bash
supabase secrets set YOUTUBE_API_KEY='AIzaXXXXXXXXXXXXXXXXXXXXXXX'
```

### Edge Function 内での参照

```typescript
const apiKey = Deno.env.get('YOUTUBE_API_KEY');
```

`Deno.env.get()` はサーバーサイドのみで動作し、レスポンスには含まれない。

---

## データフロー（詳細）

### 1. Flutter クライアント側 (`my_page_screen.dart`)

```
_loadUserData() が呼ばれる
    │
    ├─ キャッシュが有効？ → YES → キャッシュ値を表示して終了
    │
    └─ NO（キャッシュなし or isRefresh=true）
          │
          ├─ Supabase: videos テーブルから自分の動画の url 一覧を取得
          │    .from('videos').select('url').eq('user_id', user.id)
          │
          ├─ videoUrls が空？ → YES → totalViews = 0 のままスキップ
          │
          └─ NO → functions.invoke('youtube-views', body: { videoUrls })
                       │
                       ├─ 成功 → res.data['totalViews'] を num で受け取り .toInt()
                       └─ 失敗 → debugPrint のみ、totalViews = 0 のまま続行
```

**型キャストの注意点:**  
Dart の JSON デシリアライズでは `int` JSON 値が `num` として返ることがある。  
`is int` ではなく `is num` で受け取り `.toInt()` で変換している。

```dart
if (res.data != null && res.data['totalViews'] is num) {
  totalViews = (res.data['totalViews'] as num).toInt();
}
```

### 2. Edge Function 側 (`supabase/functions/youtube-views/index.ts`)

```
リクエスト受信
    │
    ├─ Authorization ヘッダーなし → 401 Unauthorized
    │
    ├─ JWT 検証（supabaseClient.auth.getUser()）
    │       └─ 失敗 → 401 Unauthorized
    │
    ├─ body: { videoUrls: string[] } を取得
    │       └─ 空配列 → { totalViews: 0 } を返す
    │
    ├─ 各 URL から YouTube Video ID を抽出（extractVideoId）
    │       対応フォーマット:
    │         - https://youtu.be/VIDEO_ID
    │         - https://www.youtube.com/watch?v=VIDEO_ID
    │         - https://www.youtube.com/embed/VIDEO_ID
    │         - https://www.youtube.com/v/VIDEO_ID
    │
    ├─ 無効 ID を除外（11文字の英数字 + _ + - のみ許可）
    │
    ├─ YouTube Data API v3 をバッチ呼び出し（50本ずつ）
    │       GET /youtube/v3/videos?part=statistics&id=ID1,ID2,...
    │
    └─ 各動画の statistics.viewCount を合計して返す
         { totalViews: number }
```

---

## キャッシュ設計

### キャッシュキー

```dart
CacheKeys.myPageTotalViews  // = 'my_page_total_views'
```

### TTL（有効期限）

通常のキャッシュ（5分）ではなく、**日本時間の翌日 0:00 まで**を TTL として設定。

```dart
Duration _ttlUntilJstMidnight() {
  const jstOffset = Duration(hours: 9);
  final nowUtc = DateTime.now().toUtc();
  final nowJst = nowUtc.add(jstOffset);
  final tomorrowJst = DateTime(nowJst.year, nowJst.month, nowJst.day + 1);
  final tomorrowUtc = tomorrowJst.subtract(jstOffset);
  return tomorrowUtc.difference(nowUtc);
}
```

**理由:** YouTube の再生数は急激に変動しないため、1日1回の更新で十分。  
毎回 API を叩くと YouTube API のクォータ（1日10,000ユニット）を無駄に消費する。

### キャッシュを即時無効化するタイミング

動画を削除すると、その動画の再生数分だけ総再生数が減るべきなので、削除と同時に `myPageTotalViews` キャッシュを破棄する。

| 操作 | 呼び出し元 | 無効化するキャッシュ |
|---|---|---|
| 動画を削除 | `home_screen.dart` / `_handleDelete` | `homeVideos`, `myVideos`, **`myPageTotalViews`** |
| 動画を削除 | `my_videos_screen.dart` / `_handleDelete` | `myVideos`, `homeVideos`, **`myPageTotalViews`** |

```dart
CacheService.instance.invalidate(CacheKeys.myPageTotalViews);
```

削除後に次回マイページを開いたとき、削除済み動画の URL は Supabase から消えているため、  
Edge Function に送るリストには含まれず、自動的に減算された値が返る。

---

## クロスプラットフォーム対応

`_supabase.functions.invoke()` は iOS / Android / Web で同一コードで動作する。  
Supabase SDK が各プラットフォームの HTTP スタックを適切に使用するため、分岐不要。

---

## YouTube API クォータ消費量の試算

YouTube Data API v3 の `videos.list` は **1リクエストで1ユニット**消費する。  
動画が50本以下なら1リクエスト = 1ユニット。  
キャッシュにより1日1回しか呼ばれないため、ユーザー1人 = **1日1ユニット**程度。

無料枠: 1日 10,000 ユニット → 約10,000ユーザーが同日にマイページを開いても枯渇しない。

---

## エラーハンドリング

| エラーケース | 挙動 |
|---|---|
| Edge Function が応答しない | `try/catch` で捕捉、`totalViews = 0` のまま表示 |
| YouTube API キーが未設定 | Edge Function が `500: API key not configured` を返す |
| 動画 URL が YouTube 形式でない | `extractVideoId` が `null` を返し除外される |
| 認証切れ（JWT 期限切れ） | Edge Function が `401` を返す |
| 動画本数が 50 本超え | 50 本ずつバッチ処理（自動対応済み） |

---

## 関連ファイル

| ファイル | 役割 |
|---|---|
| `lib/screens/profile/my_page_screen.dart` | 取得・表示・キャッシュ制御 |
| `lib/services/cache_service.dart` | キャッシュキー定義・TTL管理 |
| `lib/screens/home/home_screen.dart` | 削除時のキャッシュ無効化 |
| `lib/screens/profile/my_videos_screen.dart` | 削除時のキャッシュ無効化 |
| `supabase/functions/youtube-views/index.ts` | Edge Function 本体（APIキー保持） |
