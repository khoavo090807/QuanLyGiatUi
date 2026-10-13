import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.117.3";

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const columns = "TinNhanID,NguoiGuiID,NguoiNhanID,DonHangID,NoiDung,NoiDungMaHoa,NoiDungNonce,MaHoaPhienBan,ThoiGianGui,TrangThai";

function toBase64(bytes: Uint8Array): string {
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function fromBase64(value: string): Uint8Array {
  return Uint8Array.from(atob(value), (char) => char.charCodeAt(0));
}

async function encryptionKey(admin: SupabaseClient): Promise<CryptoKey> {
  const { data, error } = await admin.rpc("get_chat_encryption_key");
  if (error || typeof data !== "string") throw new Error("Chat encryption key unavailable");
  const bytes = fromBase64(data);
  if (bytes.length !== 32) throw new Error("Invalid chat encryption key length");
  return crypto.subtle.importKey("raw", bytes, "AES-GCM", false, ["encrypt", "decrypt"]);
}

async function encrypt(key: CryptoKey, content: string) {
  const nonce = crypto.getRandomValues(new Uint8Array(12));
  const ciphertext = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, key, encoder.encode(content)));
  return { ciphertext: toBase64(ciphertext), nonce: toBase64(nonce) };
}

async function presentAndMigrate(row: Record<string, unknown>, key: CryptoKey, user: SupabaseClient) {
  let content: string;
  if (row.MaHoaPhienBan === 1 && typeof row.NoiDungMaHoa === "string" && typeof row.NoiDungNonce === "string") {
    const plain = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: fromBase64(row.NoiDungNonce) }, key, fromBase64(row.NoiDungMaHoa),
    );
    content = decoder.decode(plain);
  } else {
    content = typeof row.NoiDung === "string" ? row.NoiDung : "";
    if (content.length > 0) {
      const encrypted = await encrypt(key, content);
      const { data, error } = await user.rpc("migrate_chat_message_encrypted", {
        p_message_id: row.TinNhanID,
        p_ciphertext: encrypted.ciphertext,
        p_nonce: encrypted.nonce,
      });
      if (error) console.error("Legacy message migration failed", error.code ?? "db_error");
      else if (data === true) {
        row.NoiDung = "";
        row.NoiDungMaHoa = encrypted.ciphertext;
        row.NoiDungNonce = encrypted.nonce;
        row.MaHoaPhienBan = 1;
      }
    }
  }
  return { ...row, NoiDung: content };
}

async function presentMany(rows: Record<string, unknown>[], key: CryptoKey, user: SupabaseClient) {
  const result: Record<string, unknown>[] = [];
  for (let start = 0; start < rows.length; start += 10) {
    const batch = rows.slice(start, start + 10);
    result.push(...await Promise.all(batch.map((row) => presentAndMigrate(row, key, user))));
  }
  return result;
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", "Cache-Control": "no-store" },
  });
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  const authorization = request.headers.get("Authorization");
  const url = Deno.env.get("SUPABASE_URL");
  const publishable = Deno.env.get("SUPABASE_ANON_KEY") ??
    (Deno.env.get("SUPABASE_PUBLISHABLE_KEYS") ? JSON.parse(Deno.env.get("SUPABASE_PUBLISHABLE_KEYS")!).default : null);
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!authorization || !url || !publishable || !serviceRole) return json({ error: "Server configuration is incomplete" }, 503);

  const user = createClient(url, publishable, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } });
  const admin = createClient(url, serviceRole, { auth: { persistSession: false, autoRefreshToken: false } });
  const accessToken = authorization.replace(/^Bearer\s+/i, "");
  const { data: userResult, error: authError } = await user.auth.getUser(accessToken);
  if (authError || !userResult.user) return json({ error: "Unauthorized" }, 401);

  try {
    const input = await request.json();
    const action = input.action;
    if (action === "send") {
      const content = typeof input.content === "string" ? input.content.trim() : "";
      if (!content || [...content].length > 1000) return json({ error: "Tin nhắn phải có từ 1 đến 1.000 ký tự." }, 400);
      const encrypted = await encrypt(await encryptionKey(admin), content);
      const { data, error } = await user.rpc("send_chat_message_encrypted", {
        p_recipient_account_id: Number(input.peer_account_id),
        p_ciphertext: encrypted.ciphertext,
        p_nonce: encrypted.nonce,
        p_order_id: input.order_id == null ? null : Number(input.order_id),
      });
      if (error) throw error;
      const row = Array.isArray(data) ? data[0] : data;
      return json({ ok: true, id: row?.TinNhanID });
    }

    if (action === "message") {
      const { data, error } = await user.from("TinNhan").select(columns).eq("TinNhanID", Number(input.message_id)).maybeSingle();
      if (error) throw error;
      if (!data) return json({ error: "Message not found" }, 404);
      return json(await presentAndMigrate(data, await encryptionKey(admin), user));
    }

    if (action === "messages") {
      let query = user.from("TinNhan").select(columns);
      query = input.order_id == null ? query.is("DonHangID", null) : query.eq("DonHangID", Number(input.order_id));
      const { data, error } = await query.order("ThoiGianGui", { ascending: true }).order("TinNhanID", { ascending: true });
      if (error) throw error;
      const current = Number(input.current_account_id);
      const peer = Number(input.peer_account_id);
      const filtered = (data ?? []).filter((row) => input.order_id != null ||
        (input.is_staff ? row.NguoiGuiID === peer || row.NguoiNhanID === peer : row.NguoiGuiID === current || row.NguoiNhanID === current));
      const key = await encryptionKey(admin);
      const messages = await presentMany(filtered as Record<string, unknown>[], key, user);
      return json(messages);
    }

    if (action === "threads") {
      const [{ data: accountId, error: accountError }, { data: supportId, error: supportError }] = await Promise.all([
        user.rpc("get_current_account_id"), user.rpc("get_support_chat_recipient"),
      ]);
      if (accountError || supportError) throw accountError ?? supportError;
      if (input.is_staff === true) {
        const { data, error } = await user.rpc("get_staff_chat_inbox");
        if (error) throw error;
        return json((data ?? []).map((row: Record<string, unknown>) => ({
          peer_account_id: row.customer_account_id, current_account_id: accountId,
          title: row.customer_name ?? "Khách hàng", last_message: "Bạn có tin nhắn mới.",
          last_message_at: row.last_message_at, unread_count: row.unread_count ?? 0,
          is_staff: true, order_id: row.order_id, order_number: row.order_number,
          avatar_url: row.customer_avatar_url,
        })).filter((row: Record<string, unknown>) => input.initial_order_id == null || row.order_id === Number(input.initial_order_id)));
      }
      const [{ data: rows, error: rowsError }, { data: unread, error: unreadError }] = await Promise.all([
        user.from("TinNhan").select(columns).order("ThoiGianGui", { ascending: true }).order("TinNhanID", { ascending: true }),
        user.from("thongbao").select("donhangid").eq("loaithongbao", "new_message").eq("dadoc", false),
      ]);
      if (rowsError || unreadError) throw rowsError ?? unreadError;
      const key = await encryptionKey(admin);
      const groups = new Map<string, { order_id: number | null; last: Record<string, unknown> | null; unread_count: number }>();
      const migratedRows = await presentMany((rows ?? []) as Record<string, unknown>[], key, user);
      for (const migrated of migratedRows) {
        const groupKey = migrated.DonHangID == null ? "null" : String(migrated.DonHangID);
        const group = groups.get(groupKey) ?? { order_id: migrated.DonHangID, last: null, unread_count: 0 };
        group.last = migrated;
        groups.set(groupKey, group);
      }
      for (const row of unread ?? []) {
        const groupKey = row.donhangid == null ? "null" : String(row.donhangid);
        const group = groups.get(groupKey) ?? { order_id: row.donhangid, last: null, unread_count: 0 };
        group.unread_count++;
        groups.set(groupKey, group);
      }
      if (input.initial_order_id != null) {
        for (const [keyName, value] of groups) if (value.order_id !== Number(input.initial_order_id)) groups.delete(keyName);
        const keyName = String(Number(input.initial_order_id));
        if (!groups.has(keyName)) groups.set(keyName, { order_id: Number(input.initial_order_id), last: null, unread_count: 0 });
      }
      if (groups.size === 0) groups.set("null", { order_id: null, last: null, unread_count: 0 });
      const result = [...groups.values()].map((group) => ({
        peer_account_id: supportId, current_account_id: accountId,
        title: group.order_id == null ? "Hỗ trợ cửa hàng" : "Trao đổi về đơn hàng",
        last_message: group.last?.NoiDung ?? "Nhắn tin với cửa hàng",
        last_message_at: group.last?.ThoiGianGui ?? null,
        unread_count: group.unread_count, is_staff: false, order_id: group.order_id,
        order_number: group.order_id == null ? null : `#${group.order_id}`,
      }));
      result.sort((a, b) => {
        const time = (value: unknown) => value == null ? 0 : Date.parse(String(value));
        return time(b.last_message_at) - time(a.last_message_at);
      });
      return json(result);
    }
    return json({ error: "Unsupported action" }, 400);
  } catch (error) {
    console.error("Chat encryption request failed", error instanceof Error ? error.message : "unknown_error");
    return json({ error: "Không thể xử lý tin nhắn lúc này." }, 500);
  }
});
