/**
 * Supabase Edge Function: send-push-notification
 *
 * DBトリガー（push_notify_on_new_notification）から呼び出され、
 * FCM HTTP v1 API を使ってデバイスにプッシュ通知を送信する。
 *
 * 必要なシークレット:
 *   supabase secrets set FCM_SERVICE_ACCOUNT_KEY='<サービスアカウントJSONの全文>'
 *
 * デプロイ:
 *   supabase functions deploy send-push-notification
 */

interface ServiceAccountKey {
  project_id: string;
  private_key: string;
  client_email: string;
  token_uri: string;
}

interface PushPayload {
  token: string;
  title: string;
  body: string;
  data?: Record<string, unknown>;
  platform?: 'android' | 'web'; // 省略時は android 扱い
}

// ------------------------------------------------------------------
// OAuth2 アクセストークン取得（サービスアカウント JWT フロー）
// ------------------------------------------------------------------

function base64urlEncode(data: string): string {
  return btoa(data).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

function uint8ArrayToBase64url(bytes: Uint8Array): string {
  let binary = "";
  bytes.forEach((b) => (binary += String.fromCharCode(b)));
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

async function getAccessToken(serviceAccount: ServiceAccountKey): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  const header = base64urlEncode(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const payload = base64urlEncode(
    JSON.stringify({
      iss: serviceAccount.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: serviceAccount.token_uri ?? "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    })
  );

  const signingInput = `${header}.${payload}`;

  // PEM 秘密鍵を CryptoKey にインポート
  const pemKey = serviceAccount.private_key.replace(/\\n/g, "\n");
  const keyBody = pemKey
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");

  const binaryKey = Uint8Array.from(atob(keyBody), (c) => c.charCodeAt(0));

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  // JWT に署名
  const encoder = new TextEncoder();
  const signatureBuffer = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    encoder.encode(signingInput)
  );

  const signature = uint8ArrayToBase64url(new Uint8Array(signatureBuffer));
  const jwt = `${signingInput}.${signature}`;

  // JWT を access_token に交換
  const tokenResponse = await fetch(
    serviceAccount.token_uri ?? "https://oauth2.googleapis.com/token",
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: jwt,
      }),
    }
  );

  if (!tokenResponse.ok) {
    const err = await tokenResponse.text();
    throw new Error(`アクセストークン取得失敗: ${err}`);
  }

  const tokenData = await tokenResponse.json();
  return tokenData.access_token as string;
}

// ------------------------------------------------------------------
// FCM HTTP v1 API でプッシュ通知を送信
// ------------------------------------------------------------------

async function sendPushNotification(
  serviceAccount: ServiceAccountKey,
  accessToken: string,
  payload: PushPayload
): Promise<void> {
  // data フィールドはすべての値を string に変換する必要がある
  const stringData = payload.data
    ? Object.fromEntries(
        Object.entries(payload.data).map(([k, v]) => [k, String(v)])
      )
    : undefined;

  const isWeb = payload.platform === 'web';

  const message: Record<string, unknown> = {
    token: payload.token,
    notification: {
      title: payload.title,
      body: payload.body,
    },
    data: stringData,
  };

  if (isWeb) {
    // Web プッシュ通知の設定
    message.webpush = {
      headers: { Urgency: "high" },
      notification: {
        icon: "/icons/Icon-192.png",
        badge: "/icons/Icon-192.png",
        // 通知クリック時にアプリを前面に出す
        click_action: "/",
      },
      fcm_options: {
        link: "/",
      },
    };
  } else {
    // Android プッシュ通知の設定
    message.android = {
      priority: "high",
      notification: {
        sound: "default",
        click_action: "FLUTTER_NOTIFICATION_CLICK",
      },
    };
  }

  const fcmResponse = await fetch(
    `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ message }),
    }
  );

  if (!fcmResponse.ok) {
    const error = await fcmResponse.text();
    // UNREGISTERED: アプリの再インストール等でトークンが無効化された状態。
    // エラーではなく正常終了とし、次回アプリ起動時にトークンが更新される。
    if (fcmResponse.status === 404 && error.includes("UNREGISTERED")) {
      console.warn(`FCMトークンが無効 (UNREGISTERED)。アプリ再起動時に自動更新されます。`);
      return;
    }
    throw new Error(`FCM送信失敗 (${fcmResponse.status}): ${error}`);
  }
}

// ------------------------------------------------------------------
// エントリーポイント
// ------------------------------------------------------------------

Deno.serve(async (req: Request) => {
  // CORS プリフライト
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: { "Access-Control-Allow-Origin": "*" },
    });
  }

  try {
    let fcmKeyJson = Deno.env.get("FCM_SERVICE_ACCOUNT_KEY");
    if (!fcmKeyJson) {
      throw new Error("FCM_SERVICE_ACCOUNT_KEY が設定されていません");
    }

    // シェル展開や設定ミスで前後にシングル/ダブルクォートが付く場合を除去
    fcmKeyJson = fcmKeyJson.trim().replace(/^['"]|['"]$/g, "");

    let serviceAccount: ServiceAccountKey;
    try {
      serviceAccount = JSON.parse(fcmKeyJson);
    } catch {
      throw new Error(
        `FCM_SERVICE_ACCOUNT_KEY のJSON解析に失敗しました。` +
        `先頭5文字: "${fcmKeyJson.slice(0, 5)}" ` +
        `末尾5文字: "${fcmKeyJson.slice(-5)}" ` +
        `※ Supabase ダッシュボードからシークレットを再設定してください。`
      );
    }

    const payload: PushPayload = await req.json();

    if (!payload.token) {
      return new Response(
        JSON.stringify({ error: "token は必須です" }),
        { status: 400, headers: { "Content-Type": "application/json" } }
      );
    }

    const accessToken = await getAccessToken(serviceAccount);
    await sendPushNotification(serviceAccount, accessToken, payload);

    return new Response(
      JSON.stringify({ success: true }),
      { headers: { "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Edge Function エラー:", error);
    return new Response(
      JSON.stringify({ error: String(error) }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
});
