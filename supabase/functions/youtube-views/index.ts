/**
 * Supabase Edge Function: youtube-views
 *
 * 自分の動画URLリストを受け取り、YouTube Data API v3 で
 * 合計再生回数を取得して返す。
 *
 * APIキーはシークレットとしてサーバーサイドにのみ保持し、
 * クライアントには一切露出しない。
 *
 * 必要なシークレット:
 *   supabase secrets set YOUTUBE_API_KEY='AIzaXXXXXXXXXXXXXXXXXXXXXXX'
 *
 * デプロイ:
 *   supabase functions deploy youtube-views
 */

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

/** YouTube URL からビデオID（11文字）を抽出する */
function extractVideoId(url: string): string | null {
  try {
    const uri = new URL(url.trim());

    // youtu.be/VIDEO_ID 形式
    if (uri.hostname === 'youtu.be' || uri.hostname === 'www.youtu.be') {
      const id = uri.pathname.split('/')[1]?.split('?')[0];
      return validateId(id);
    }

    // youtube.com 形式
    if (uri.hostname.includes('youtube.com')) {
      // ?v=VIDEO_ID
      const v = uri.searchParams.get('v');
      if (v) return validateId(v);

      // /embed/VIDEO_ID または /v/VIDEO_ID
      const parts = uri.pathname.split('/').filter(Boolean);
      const embedIdx = parts.indexOf('embed');
      if (embedIdx !== -1 && parts[embedIdx + 1]) return validateId(parts[embedIdx + 1]);
      const vIdx = parts.indexOf('v');
      if (vIdx !== -1 && parts[vIdx + 1]) return validateId(parts[vIdx + 1]);
    }

    return null;
  } catch {
    return null;
  }
}

function validateId(id: string | undefined): string | null {
  if (!id) return null;
  const clean = id.split('?')[0].split('&')[0];
  return /^[a-zA-Z0-9_-]{11}$/.test(clean) ? clean : null;
}

Deno.serve(async (req: Request) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    // ── 認証チェック（ログイン済みユーザーのみ許可）──────────────────
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: authHeader } } },
    );

    const { data: { user }, error: authError } = await supabaseClient.auth.getUser();
    if (authError || !user) {
      return new Response(
        JSON.stringify({ error: 'Unauthorized' }),
        { status: 401, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // ── リクエストボディからURLリストを取得 ──────────────────────────
    const { videoUrls } = await req.json() as { videoUrls: string[] };

    if (!Array.isArray(videoUrls) || videoUrls.length === 0) {
      return new Response(
        JSON.stringify({ totalViews: 0 }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // ── APIキーはサーバーサイドのシークレットからのみ取得 ─────────────
    const apiKey = Deno.env.get('YOUTUBE_API_KEY');
    if (!apiKey) {
      return new Response(
        JSON.stringify({ error: 'API key not configured' }),
        { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // ── ビデオIDを抽出（無効なURLは除外）────────────────────────────
    const videoIds = videoUrls
      .map(extractVideoId)
      .filter((id): id is string => id !== null);

    if (videoIds.length === 0) {
      return new Response(
        JSON.stringify({ totalViews: 0 }),
        { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    // ── YouTube Data API v3 でバッチ取得（最大50本ずつ）─────────────
    let totalViews = 0;

    for (let i = 0; i < videoIds.length; i += 50) {
      const batch = videoIds.slice(i, i + 50);
      const idsParam = batch.join(',');

      const ytUrl = new URL('https://www.googleapis.com/youtube/v3/videos');
      ytUrl.searchParams.set('part', 'statistics');
      ytUrl.searchParams.set('id', idsParam);
      ytUrl.searchParams.set('key', apiKey);

      const ytRes = await fetch(ytUrl.toString());
      if (!ytRes.ok) continue;

      const ytJson = await ytRes.json() as {
        items?: Array<{ statistics?: { viewCount?: string } }>;
      };

      for (const item of ytJson.items ?? []) {
        totalViews += parseInt(item.statistics?.viewCount ?? '0', 10);
      }
    }

    return new Response(
      JSON.stringify({ totalViews }),
      { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );

  } catch (err) {
    return new Response(
      JSON.stringify({ error: String(err) }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  }
});
