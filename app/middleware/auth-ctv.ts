// P1-8: Route middleware UX cho cổng CTV.
// Bảo mật dữ liệu được thực thi ở RLS & RPC phía Supabase.
export default defineNuxtRouteMiddleware(async () => {
  if (import.meta.server) return;
  const { supabase } = useSupabase();
  if (!supabase) return;
  await supabase.auth.getSession();
});
