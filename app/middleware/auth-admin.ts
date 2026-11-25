// P1-8: Route middleware UX cho khu vực quản trị.
// Lưu ý: Đây chỉ là lớp kiểm tra UX ở client; toàn bộ bảo mật thật sự nằm ở RLS & RPC phía Supabase.
export default defineNuxtRouteMiddleware(async () => {
  if (import.meta.server) return;
  const { supabase } = useSupabase();
  if (!supabase) return;
  // Không chặn truy cập trang /admin vì trang có form đăng nhập tích hợp sẵn;
  // middleware chỉ làm mới session nhẹ để tránh token hết hạn im lặng.
  await supabase.auth.getSession();
});
