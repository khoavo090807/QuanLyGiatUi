import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const encoder = new TextEncoder();
const tokenEndpoint = "https://oauth2.googleapis.com/token";

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

function encodeJson(value: unknown): string {
  return base64Url(encoder.encode(JSON.stringify(value)));
}

async function createGoogleAccessToken(serviceAccount: {
  client_email: string;
  private_key: string;
  token_uri?: string;
}): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${encodeJson({ alg: "RS256", typ: "JWT" })}.${encodeJson({
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: serviceAccount.token_uri ?? tokenEndpoint,
    iat: now,
    exp: now + 3600,
  })}`;
  const pem = serviceAccount.private_key
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replaceAll(/\s/g, "");
  const keyBytes = Uint8Array.from(atob(pem), (character) => character.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, encoder.encode(unsigned)),
  );
  const assertion = `${unsigned}.${base64Url(signature)}`;
  const response = await fetch(serviceAccount.token_uri ?? tokenEndpoint, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const result = await response.json();
  if (!response.ok || typeof result.access_token !== "string") {
    throw new Error(`Google OAuth token request failed (${response.status})`);
  }
  return result.access_token;
}

function constantTimeEquals(left: string, right: string): boolean {
  const a = encoder.encode(left);
  const b = encoder.encode(right);
  if (a.length !== b.length) return false;
  let difference = 0;
  for (let index = 0; index < a.length; index++) difference |= a[index] ^ b[index];
  return difference === 0;
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const expectedSecret = Deno.env.get("PUSH_WEBHOOK_SECRET");
  const suppliedSecret = request.headers.get("x-push-webhook-secret") ?? "";
  if (!expectedSecret || !constantTimeEquals(expectedSecret, suppliedSecret)) {
    return new Response("Unauthorized", { status: 401 });
  }

  const firebaseJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!firebaseJson || !supabaseUrl || !serviceRoleKey) {
    return new Response("Push provider secrets are not configured", { status: 503 });
  }

  try {
    const input = await request.json();
    const record = input.record ?? input;
    const accountId = Number(record.TaiKhoanID);
    if (!Number.isInteger(accountId)) {
      return new Response("Invalid notification account", { status: 400 });
    }

    const serviceAccount = JSON.parse(firebaseJson);
    const accessToken = await createGoogleAccessToken(serviceAccount);
    const tokensResponse = await fetch(
      `${supabaseUrl}/rest/v1/push_device_tokens?select=token&TaiKhoanID=eq.${accountId}`,
      { headers: { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}` } },
    );
    if (!tokensResponse.ok) {
      return new Response("Could not load device tokens", { status: 502 });
    }
    const tokenRows: Array<{ token: string }> = await tokensResponse.json();
    if (tokenRows.length === 0) return new Response(null, { status: 204 });

    const projectId = serviceAccount.project_id;
    if (typeof projectId !== "string" || !projectId) {
      return new Response("Firebase service account has no project_id", { status: 503 });
    }

    const title = String(record.TieuDe ?? "Thông báo mới").slice(0, 200);
    const body = String(record.NoiDung ?? "").slice(0, 1000);
    const invalidTokens: string[] = [];
    for (const row of tokenRows) {
      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token: row.token,
              notification: { title, body },
              data: {
                notification_id: String(record.ThongBaoID ?? ""),
                notification_type: String(record.LoaiThongBao ?? ""),
                order_id: String(record.DonHangID ?? ""),
              },
              android: { priority: "HIGH", notification: { channel_id: "laundry_updates" } },
            },
          }),
        },
      );
      if (!response.ok) {
        const error = await response.text();
        if (response.status === 404 || error.includes("UNREGISTERED")) {
          invalidTokens.push(row.token);
        } else {
          console.error(`FCM send failed with status ${response.status}`);
        }
      }
    }

    for (const token of invalidTokens) {
      await fetch(
        `${supabaseUrl}/rest/v1/push_device_tokens?token=eq.${encodeURIComponent(token)}`,
        {
          method: "DELETE",
          headers: { apikey: serviceRoleKey, Authorization: `Bearer ${serviceRoleKey}` },
        },
      );
    }
    return Response.json({ sent: tokenRows.length - invalidTokens.length });
  } catch (error) {
    console.error("Push notification delivery failed", error);
    return new Response("Push notification delivery failed", { status: 500 });
  }
});
