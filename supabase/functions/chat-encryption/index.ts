import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, type SupabaseClient } from "npm:@supabase/supabase-js@2.117.3";

const encoder = new TextEncoder();
const decoder = new TextDecoder();
const columns = "TinNhanID,NguoiGuiID,NguoiNhanID,DonHangID,NoiDung,NoiDungMaHoa,NoiDungNonce,MaHoaPhienBan,DaChinhSua,DaThuHoi,ThoiGianGui,TrangThai";

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

async function presentAndMigrate(row: Record<string, unknown>, key: CryptoKey, user: SupabaseClient, allowMigration = true) {
  if (row.DaThuHoi === true) return { ...row, NoiDung: "", ImageUrl: null };
  let content: string;
  if (row.MaHoaPhienBan === 1 && typeof row.NoiDungMaHoa === "string" && typeof row.NoiDungNonce === "string") {
    const plain = await crypto.subtle.decrypt(
      { name: "AES-GCM", iv: fromBase64(row.NoiDungNonce) }, key, fromBase64(row.NoiDungMaHoa),
    );
    content = decoder.decode(plain);
  } else {
    content = typeof row.NoiDung === "string" ? row.NoiDung : "";
    if (allowMigration && content.length > 0) {
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

async function presentMany(rows: Record<string, unknown>[], key: CryptoKey, user: SupabaseClient, allowMigration = true) {
  const result: Record<string, unknown>[] = [];
  for (let start = 0; start < rows.length; start += 10) {
    const batch = rows.slice(start, start + 10);
    result.push(...await Promise.all(batch.map((row) => presentAndMigrate(row, key, user, allowMigration))));
  }
  return result;
}

async function addImageUrls(rows: Record<string, unknown>[], admin: SupabaseClient) {
  return await Promise.all(rows.map(async (row) => {
    if (row.DaThuHoi === true) return { ...row, NoiDung: "", ImageUrl: null };
    const content = typeof row.NoiDung === "string" ? row.NoiDung : "";
    if (!content.startsWith("image:")) return row;
    const path = content.slice("image:".length);
    const { data, error } = await admin.storage.from("chat-images").createSignedUrl(path, 3600);
    if (error || !data?.signedUrl) {
      console.error("Chat image signing failed", error?.message ?? "signed_url_missing");
      return { ...row, NoiDung: "Không thể tải ảnh tin nhắn này.", ImageUrl: null };
    }
    return { ...row, NoiDung: "Ảnh", ImageUrl: data.signedUrl };
  }));
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

  const admin = createClient(url, serviceRole, { auth: { persistSession: false, autoRefreshToken: false } });
  const accessToken = authorization.replace(/^Bearer\s+/i, "");
  const user = createClient(url, publishable, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } });
  let isServiceRole = accessToken === serviceRole;
  if (!isServiceRole) {
    // Ask Postgres to validate the caller's signed JWT claims. The RPC is
    // executable only by service_role and returns a key only for that role;
    // decoding JWT segments here is unreliable for padded/base64url payloads.
    const { data: keyCheck, error: tokenError } = await user.rpc("get_chat_encryption_key");
    isServiceRole = !tokenError && typeof keyCheck === "string" && keyCheck.length > 0;
  }
  if (!isServiceRole) {
    const { data: userResult, error: authError } = await user.auth.getUser(accessToken);
    if (authError || !userResult.user) return json({ error: "Unauthorized" }, 401);
  }

  try {
    const input = await request.json();
    const action = input.action;
    if (action === "present_web_messages") {
      if (!isServiceRole || !Array.isArray(input.message_ids) || input.message_ids.length > 100 ||
          input.message_ids.some((id: unknown) => !Number.isSafeInteger(id) || Number(id) < 1)) {
        return json({ error: "Invalid request" }, 403);
      }
      const ids = [...new Set(input.message_ids as number[])];
      const { data, error } = await admin.from("TinNhan").select(columns).in("TinNhanID", ids);
      if (error) throw error;
      const presented = await presentMany((data ?? []) as Record<string, unknown>[], await encryptionKey(admin), admin, false);
      return json({ messages: await addImageUrls(presented, admin) });
    }
    if (action === "edit_message") {
      if (!isServiceRole) return json({ error: "Invalid request" }, 403);
      const messageId = Number(input.message_id);
      const senderAccountId = Number(input.sender_account_id);
      const content = typeof input.content === "string" ? input.content.trim() : "";
      if (!Number.isSafeInteger(messageId) || messageId < 1 || !Number.isSafeInteger(senderAccountId) || senderAccountId < 1 ||
          !content || [...content].length > 1000) {
        return json({ error: "Tin nhắn phải có từ 1 đến 1.000 ký tự." }, 400);
      }
      const { data: message, error: messageError } = await admin.from("TinNhan").select(columns)
        .eq("TinNhanID", messageId).eq("NguoiGuiID", senderAccountId).maybeSingle();
      if (messageError) throw messageError;
      if (!message) return json({ error: "Không tìm thấy tin nhắn của người gửi." }, 404);
      const current = await presentAndMigrate(message, await encryptionKey(admin), admin, false);
      if (String(current.NoiDung ?? "").startsWith("image:")) {
        return json({ error: "Không thể sửa nội dung của tin nhắn ảnh." }, 400);
      }
      const encrypted = await encrypt(await encryptionKey(admin), content);
      const { error: updateError } = await admin.from("TinNhan").update({
        "NoiDung": "", "NoiDungMaHoa": encrypted.ciphertext,
        "NoiDungNonce": encrypted.nonce, "MaHoaPhienBan": 1, "DaChinhSua": true,
      }).eq("TinNhanID", messageId).eq("NguoiGuiID", senderAccountId);
      if (updateError) throw updateError;
      return json({ ok: true });
    }
    if (action === "edit") {
      if (isServiceRole) return json({ error: "Invalid request" }, 403);
      const messageId = Number(input.message_id);
      const content = typeof input.content === "string" ? input.content.trim() : "";
      if (!Number.isSafeInteger(messageId) || messageId < 1 || !content || [...content].length > 1000) {
        return json({ error: "Tin nhắn phải có từ 1 đến 1.000 ký tự." }, 400);
      }
      const { data: accountId, error: accountError } = await user.rpc("get_current_account_id");
      if (accountError || typeof accountId !== "number") throw accountError ?? new Error("Account unavailable");
      const { data: message, error: messageError } = await user.from("TinNhan").select(columns)
        .eq("TinNhanID", messageId).eq("NguoiGuiID", accountId).maybeSingle();
      if (messageError) throw messageError;
      if (!message) return json({ error: "Chỉ có thể chỉnh sửa tin nhắn do bạn gửi." }, 403);
      const current = await presentAndMigrate(message, await encryptionKey(admin), user, false);
      if (String(current.NoiDung ?? "").startsWith("image:")) {
        return json({ error: "Không thể chỉnh sửa tin nhắn ảnh." }, 400);
      }
      const encrypted = await encrypt(await encryptionKey(admin), content);
      const { data: updated, error: updateError } = await admin.from("TinNhan").update({
        "NoiDung": "", "NoiDungMaHoa": encrypted.ciphertext,
        "NoiDungNonce": encrypted.nonce, "MaHoaPhienBan": 1, "DaChinhSua": true,
      }).eq("TinNhanID", messageId).eq("NguoiGuiID", accountId).select("TinNhanID").maybeSingle();
      if (updateError) throw updateError;
      if (!updated) return json({ error: "Tin nhắn không còn tồn tại." }, 404);
      return json({ ok: true });
    }
    if (action === "create_image_upload") {
      if (!isServiceRole) return json({ error: "Invalid request" }, 403);
      const senderAccountId = Number(input.sender_account_id);
      const mimeType = String(input.mime_type ?? "");
      const extension = mimeType === "image/jpeg" ? "jpg" : mimeType === "image/png" ? "png" : mimeType === "image/webp" ? "webp" : null;
      if (!Number.isSafeInteger(senderAccountId) || senderAccountId < 1 || !extension) {
        return json({ error: "Ảnh không hợp lệ." }, 400);
      }
      const path = `${senderAccountId}/${crypto.randomUUID()}.${extension}`;
      const { data, error } = await admin.storage.from("chat-images").createSignedUploadUrl(path, { upsert: false });
      if (error) throw error;
      return json({ path, signed_url: data.signedUrl, token: data.token, api_key: publishable });
    }
    if (action === "send_message_web" || action === "create_image_message_web") {
      if (!isServiceRole) return json({ error: "Invalid request" }, 403);
      const senderAccountId = Number(input.sender_account_id);
      const recipientAccountId = Number(input.recipient_account_id);
      const orderId = input.order_id == null ? null : Number(input.order_id);
      const content = typeof input.content === "string" ? input.content.trim() : "";
      const isImage = action === "create_image_message_web";
      if (!Number.isSafeInteger(senderAccountId) || senderAccountId < 1 ||
          !Number.isSafeInteger(recipientAccountId) || recipientAccountId < 1 ||
          (orderId !== null && (!Number.isSafeInteger(orderId) || orderId < 1)) ||
          !content || [...content].length > 1000 || (isImage && !content.startsWith("image:")) ||
          (!isImage && content.startsWith("image:"))) {
        return json({ error: "Thông tin tin nhắn không hợp lệ." }, 400);
      }
      const encrypted = await encrypt(await encryptionKey(admin), content);
      const { data, error } = await admin.from("TinNhan").insert({
        NguoiGuiID: senderAccountId,
        NguoiNhanID: recipientAccountId,
        DonHangID: orderId,
        NoiDung: "",
        NoiDungMaHoa: encrypted.ciphertext,
        NoiDungNonce: encrypted.nonce,
        MaHoaPhienBan: 1,
        ThoiGianGui: new Date().toISOString(),
        TrangThai: "Đã gửi",
      }).select("TinNhanID").single();
      if (error) throw error;
      return json({ ok: true, id: data.TinNhanID });
    }
    if (action === "recall_message_web") {
      if (!isServiceRole) return json({ error: "Invalid request" }, 403);
      const messageId = Number(input.message_id);
      const senderAccountId = Number(input.sender_account_id);
      if (!Number.isSafeInteger(messageId) || messageId < 1 ||
          !Number.isSafeInteger(senderAccountId) || senderAccountId < 1) {
        return json({ error: "Thông tin tin nhắn không hợp lệ." }, 400);
      }
      const { data: message, error: messageError } = await admin.from("TinNhan").select(columns)
        .eq("TinNhanID", messageId).eq("NguoiGuiID", senderAccountId).maybeSingle();
      if (messageError) throw messageError;
      if (!message) return json({ error: "Không tìm thấy tin nhắn của người gửi." }, 404);
      const presented = await presentAndMigrate(message, await encryptionKey(admin), admin, false);
      const { data: recalled, error: recallError } = await admin.from("TinNhan").update({
        "DaThuHoi": true, "NoiDung": "Tin nhắn đã thu hồi", "NoiDungMaHoa": null,
        "NoiDungNonce": null, "MaHoaPhienBan": null,
      }).eq("TinNhanID", messageId).eq("NguoiGuiID", senderAccountId)
        .select("TinNhanID").maybeSingle();
      if (recallError) throw recallError;
      if (!recalled) return json({ error: "Tin nhắn không còn tồn tại." }, 404);
      const content = String(presented.NoiDung ?? "");
      if (content.startsWith("image:")) {
        const { error } = await admin.storage.from("chat-images").remove([content.slice("image:".length)]);
        if (error) console.error("Recalled web chat image cleanup failed", error.message);
      }
      return json({ ok: true });
    }
    if (action === "hide_message_web") {
      if (!isServiceRole) return json({ error: "Invalid request" }, 403);
      const messageId = Number(input.message_id);
      const accountId = Number(input.account_id);
      if (!Number.isSafeInteger(messageId) || messageId < 1 || !Number.isSafeInteger(accountId) || accountId < 1) {
        return json({ error: "Thông tin tin nhắn không hợp lệ." }, 400);
      }
      const { data: message, error: messageError } = await admin.from("TinNhan").select("TinNhanID")
        .eq("TinNhanID", messageId).maybeSingle();
      if (messageError) throw messageError;
      if (!message) return json({ error: "Tin nhắn không còn tồn tại." }, 404);
      const { error } = await admin.from("TinNhanAn").upsert({
        TaiKhoanID: accountId,
        TinNhanID: messageId,
        ThoiGianAn: new Date().toISOString(),
      }, { onConflict: "TaiKhoanID,TinNhanID", ignoreDuplicates: true });
      if (error) throw error;
      return json({ ok: true });
    }
    if (isServiceRole) return json({ error: "Unsupported action" }, 403);
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

    if (action === "send_image") {
      const mimeType = String(input.mime_type ?? "");
      const allowedMimeTypes = new Set(["image/jpeg", "image/png", "image/webp"]);
      const encoded = typeof input.image_base64 === "string" ? input.image_base64 : "";
      if (!allowedMimeTypes.has(mimeType) || !encoded || encoded.length > 7_000_000) {
        return json({ error: "Ảnh không hợp lệ hoặc vượt quá 5 MB." }, 400);
      }
      const bytes = fromBase64(encoded);
      if (bytes.length === 0 || bytes.length > 5 * 1024 * 1024) {
        return json({ error: "Ảnh không hợp lệ hoặc vượt quá 5 MB." }, 400);
      }
      const isPng = mimeType === "image/png" && bytes.length >= 8 &&
        [137, 80, 78, 71, 13, 10, 26, 10].every((value, index) => bytes[index] === value);
      const isJpeg = mimeType === "image/jpeg" && bytes.length >= 3 &&
        bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff;
      const isWebp = mimeType === "image/webp" && bytes.length >= 12 &&
        new TextDecoder().decode(bytes.slice(0, 4)) === "RIFF" &&
        new TextDecoder().decode(bytes.slice(8, 12)) === "WEBP";
      if (!isPng && !isJpeg && !isWebp) return json({ error: "Định dạng ảnh không hợp lệ." }, 400);
      const { data: accountId, error: accountError } = await user.rpc("get_current_account_id");
      if (accountError || typeof accountId !== "number") throw accountError ?? new Error("Account unavailable");
      const extension = mimeType === "image/jpeg" ? "jpg" : mimeType.slice("image/".length);
      const path = `${accountId}/${crypto.randomUUID()}.${extension}`;
      const { error: uploadError } = await admin.storage.from("chat-images").upload(path, bytes, {
        contentType: mimeType,
        upsert: false,
      });
      if (uploadError) throw uploadError;
      const encrypted = await encrypt(await encryptionKey(admin), `image:${path}`);
      const { data, error } = await user.rpc("send_chat_message_encrypted", {
        p_recipient_account_id: Number(input.peer_account_id),
        p_ciphertext: encrypted.ciphertext,
        p_nonce: encrypted.nonce,
        p_order_id: input.order_id == null ? null : Number(input.order_id),
      });
      if (error) {
        await admin.storage.from("chat-images").remove([path]);
        throw error;
      }
      const row = Array.isArray(data) ? data[0] : data;
      if (!row?.TinNhanID) {
        await admin.storage.from("chat-images").remove([path]);
        return json({ error: "Bạn không thể gửi ảnh vào cuộc trò chuyện này." }, 403);
      }
      return json({ ok: true, id: row?.TinNhanID });
    }

    if (action === "recall_message") {
      const messageId = Number(input.message_id);
      const { data: before, error: beforeError } = await user.from("TinNhan")
        .select(columns).eq("TinNhanID", messageId).maybeSingle();
      if (beforeError) throw beforeError;
      if (!before) return json({ error: "Message not found" }, 404);
      const presented = await presentAndMigrate(before, await encryptionKey(admin), user);
      const recalled = await user.rpc("recall_chat_message", { p_message_id: messageId });
      if (recalled.error) throw recalled.error;
      if (recalled.data !== true) return json({ error: "Cannot recall this message" }, 403);
      const content = String(presented.NoiDung ?? "");
      if (content.startsWith("image:")) {
        const { error } = await admin.storage.from("chat-images").remove([content.slice("image:".length)]);
        if (error) console.error("Recalled chat image cleanup failed", error.message);
      }
      return json({ ok: true });
    }

    if (action === "message") {
      const { data, error } = await user.from("TinNhan").select(columns).eq("TinNhanID", Number(input.message_id)).maybeSingle();
      if (error) throw error;
      if (!data) return json({ error: "Message not found" }, 404);
      const presented = await presentAndMigrate(data, await encryptionKey(admin), user);
      return json((await addImageUrls([presented], admin))[0]);
    }

    if (action === "messages") {
      let query = user.from("TinNhan").select(columns);
      const current = Number(input.current_account_id);
      const peer = Number(input.peer_account_id);
      query = input.order_id == null
        ? query.is("DonHangID", null).or(`NguoiGuiID.eq.${input.is_staff ? peer : current},NguoiNhanID.eq.${input.is_staff ? peer : current}`)
        : query.eq("DonHangID", Number(input.order_id));
      const { data: hiddenIds, error: hiddenError } = await user.rpc("get_hidden_chat_message_ids", {
        p_peer_account_id: peer,
        p_order_id: input.order_id == null ? null : Number(input.order_id),
      });
      if (hiddenError) throw hiddenError;
      const excluded = (hiddenIds ?? []).map((row: Record<string, unknown>) => Number(row.TinNhanID));
      if (excluded.length > 0) query = query.not("TinNhanID", "in", `(${excluded.join(",")})`);
      if (typeof input.before_message_id === "number") query = query.lt("TinNhanID", input.before_message_id);
      const pageSize = Math.max(1, Math.min(Number(input.page_size) || 10, 50));
      const { data, error } = await query
        .order("ThoiGianGui", { ascending: false })
        .order("TinNhanID", { ascending: false })
        .limit(pageSize + 1);
      if (error) throw error;
      const hasMore = (data ?? []).length > pageSize;
      const page = (data ?? []).slice(0, pageSize).reverse();
      const key = await encryptionKey(admin);
      const presented = await presentMany(page as Record<string, unknown>[], key, user);
      const messages = await addImageUrls(presented, admin);
      return json({ messages, has_more: hasMore });
    }

    if (action === "threads") {
      const [{ data: accountId, error: accountError }, { data: supportId, error: supportError }] = await Promise.all([
        user.rpc("get_current_account_id"), user.rpc("get_support_chat_recipient"),
      ]);
      if (accountError || supportError) throw accountError ?? supportError;
      if (input.is_staff === true) {
        const { data, error } = await user.rpc("get_staff_chat_inbox");
        if (error) throw error;
        const rows = (data ?? []).map((row: Record<string, unknown>) => ({
          peer_account_id: row.customer_account_id, current_account_id: accountId,
          title: row.customer_name ?? "Khách hàng", last_message: "Bạn có tin nhắn mới.",
          last_message_at: row.last_message_at, unread_count: row.unread_count ?? 0,
          is_staff: true, order_id: row.order_id, order_number: row.order_number,
          avatar_url: row.customer_avatar_url,
        })).filter((row: Record<string, unknown>) => input.initial_order_id == null || row.order_id === Number(input.initial_order_id));
        const pageSize = Math.max(1, Math.min(Number(input.page_size) || 10, 50));
        const offset = Math.max(0, Number(input.page) || 0) * pageSize;
        return json({ threads: rows.slice(offset, offset + pageSize), has_more: rows.length > offset + pageSize });
      }
      const [{ data: rows, error: rowsError }, { data: unread, error: unreadError }] = await Promise.all([
        user.from("TinNhan").select("TinNhanID,DonHangID,ThoiGianGui").order("ThoiGianGui", { ascending: true }).order("TinNhanID", { ascending: true }),
        user.from("thongbao").select("donhangid").eq("loaithongbao", "new_message").eq("dadoc", false),
      ]);
      if (rowsError || unreadError) throw rowsError ?? unreadError;
      const key = await encryptionKey(admin);
      const groups = new Map<string, { order_id: number | null; last: Record<string, unknown> | null; unread_count: number }>();
      for (const row of (rows ?? []) as Record<string, unknown>[]) {
        const groupKey = row.DonHangID == null ? "null" : String(row.DonHangID);
        const group = groups.get(groupKey) ?? { order_id: row.DonHangID, last: null, unread_count: 0 };
        group.last = row;
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
      const orderedGroups = [...groups.values()].sort((a, b) => {
        const time = (value: unknown) => value == null ? 0 : Date.parse(String(value));
        return time(b.last?.ThoiGianGui) - time(a.last?.ThoiGianGui);
      });
      const pageSize = Math.max(1, Math.min(Number(input.page_size) || 10, 50));
      const offset = Math.max(0, Number(input.page) || 0) * pageSize;
      const pageGroups = orderedGroups.slice(offset, offset + pageSize);
      const latestIds = pageGroups.flatMap((group) => group.last ? [group.last.TinNhanID] : []);
      const latestById = new Map<number, Record<string, unknown>>();
      if (latestIds.length > 0) {
        const { data: latestData, error: latestError } = await user
          .from("TinNhan").select(columns).in("TinNhanID", latestIds);
        if (latestError) throw latestError;
        for (const row of (latestData ?? []) as Record<string, unknown>[]) {
          latestById.set(Number(row.TinNhanID), row);
        }
      }
      const latestRows = await presentMany(
        latestIds.flatMap((id) => latestById.has(Number(id)) ? [latestById.get(Number(id))!] : []), key, user,
      );
      let latestIndex = 0;
      const result = pageGroups.map((group) => {
        const latest = group.last ? latestRows[latestIndex++] : null;
        const content = typeof latest?.NoiDung === "string" ? latest.NoiDung : "";
        return {
          peer_account_id: supportId, current_account_id: accountId,
          title: group.order_id == null ? "Hỗ trợ cửa hàng" : "Trao đổi về đơn hàng",
          last_message: latest ? (content.startsWith("image:") ? "📷 Ảnh" : content) : "Nhắn tin với cửa hàng",
          last_message_at: group.last?.ThoiGianGui ?? null,
          unread_count: group.unread_count, is_staff: false, order_id: group.order_id,
          order_number: group.order_id == null ? null : `#${group.order_id}`,
        };
      });
      return json({ threads: result, has_more: orderedGroups.length > offset + pageSize });
    }
    return json({ error: "Unsupported action" }, 400);
  } catch (error) {
    console.error("Chat encryption request failed", error instanceof Error ? error.message : "unknown_error");
    return json({ error: "Không thể xử lý tin nhắn lúc này." }, 500);
  }
});
