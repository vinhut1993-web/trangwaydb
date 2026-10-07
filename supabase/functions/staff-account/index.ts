// Supabase Edge Function: staff-account
// Tạo tài khoản, cấp lại mật khẩu, khoá/mở khoá cho nhân sự Trang Way.
// Chỉ Giám đốc / Phó GĐ / Admin gọi được (kiểm bằng trangway.is_hr_admin()).
// Dùng với database v1.2 (01_schema.sql). Mật khẩu chỉ nằm trong Supabase Auth.
// Deploy: supabase functions deploy staff-account
//
// Gọi từ app:
//   supabase.functions.invoke('staff-account', { body: {
//     action: 'create', staff_code: 'NV-003', username: 'tranthuha',
//     email: 'hatt@trangway.vn',        // bỏ trống → tranthuha@trangway.local
//     temp_password: 'TrangWay@2026' } })
//   { action: 'reset_password', staff_code, temp_password }
//   { action: 'lock', staff_code, reason }   |   { action: 'unlock', staff_code }
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  const url = Deno.env.get("SUPABASE_URL")!;

  // 1. Kiểm quyền người gọi bằng chính token của họ
  const caller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    db: { schema: "trangway" },
  });
  const { data: allowed, error: permErr } = await caller.rpc("is_hr_admin");
  if (permErr || !allowed) return json({ error: "Chỉ Giám đốc, Phó GĐ hoặc Admin được quản lý tài khoản" }, 403);

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { db: { schema: "trangway" } });
  const body = await req.json();
  const { action, staff_code } = body;

  const { data: staff, error: staffErr } = await admin
    .from("staff").select("id, auth_user_id, username, login_email").eq("code", staff_code).single();
  if (staffErr || !staff) return json({ error: `Không có nhân sự mã ${staff_code}` }, 404);

  const strong = (p: string) => typeof p === "string" && p.length >= 8 && /[A-Za-z]/.test(p) && /\d/.test(p);

  if (action === "create") {
    if (staff.auth_user_id) return json({ error: "Nhân sự này đã có tài khoản" }, 409);
    const username = String(body.username ?? "").trim().toLowerCase();
    if (!/^[a-z0-9._]{3,32}$/.test(username)) return json({ error: "Tên đăng nhập 3–32 ký tự: chữ thường, số, dấu chấm, gạch dưới" }, 400);
    if (!strong(body.temp_password)) return json({ error: "Mật khẩu tạm tối thiểu 8 ký tự, có chữ và số" }, 400);
    const email = String(body.email || `${username}@trangway.local`).trim().toLowerCase();
    const { data: created, error } = await admin.auth.admin.createUser({ email, password: body.temp_password, email_confirm: true });
    if (error || !created.user) return json({ error: error?.message ?? "Không tạo được tài khoản" }, 400);
    const { error: linkErr } = await admin.rpc("fn_link_staff_account",
      { p_staff_code: staff_code, p_auth_user_id: created.user.id, p_login_email: email, p_username: username });
    if (linkErr) {
      await admin.auth.admin.deleteUser(created.user.id);   // không để lại tài khoản mồ côi
      return json({ error: linkErr.message }, 400);
    }
    return json({ ok: true, login: username, email });
  }

  if (!staff.auth_user_id) return json({ error: "Nhân sự này chưa có tài khoản" }, 400);

  if (action === "reset_password") {
    if (!strong(body.temp_password)) return json({ error: "Mật khẩu tạm tối thiểu 8 ký tự, có chữ và số" }, 400);
    const { error } = await admin.auth.admin.updateUserById(staff.auth_user_id, { password: body.temp_password });
    if (error) return json({ error: error.message }, 400);
    await admin.from("staff").update({ must_change_password: true }).eq("id", staff.id);
    return json({ ok: true });
  }

  if (action === "lock" || action === "unlock") {
    const lock = action === "lock";
    // Khoá cả phía Supabase Auth để phiên đăng nhập cũ hết hiệu lực
    const { error } = await admin.auth.admin.updateUserById(staff.auth_user_id, { ban_duration: lock ? "876000h" : "none" });
    if (error) return json({ error: error.message }, 400);
    const { error: lockErr } = await admin.rpc("fn_set_staff_lock",
      { p_staff_id: staff.id, p_locked: lock, p_reason: body.reason ?? null });
    if (lockErr) return json({ error: lockErr.message }, 400);
    return json({ ok: true });
  }

  return json({ error: "action phải là create, reset_password, lock hoặc unlock" }, 400);
});
