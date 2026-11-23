import { createClient, type SupabaseClient } from '@supabase/supabase-js';

let clientInstance: SupabaseClient | null = null;

export function useSupabase() {
  const config = useRuntimeConfig();
  const url = String(config.public.supabaseUrl || '');
  const anonKey = String(config.public.supabaseAnonKey || '');

  const isConfigured = Boolean(url && anonKey && !url.includes('YOUR_PROJECT_REF'));

  if (isConfigured && !clientInstance) {
    clientInstance = createClient(url, anonKey, {
      auth: {
        persistSession: import.meta.client,
        autoRefreshToken: import.meta.client,
        detectSessionInUrl: import.meta.client
      }
    });
  }

  const createEphemeralClient = () => {
    if (!isConfigured) return null;
    return createClient(url, anonKey, {
      auth: {
        persistSession: false,
        autoRefreshToken: false,
        detectSessionInUrl: false
      }
    });
  };

  return {
    supabase: clientInstance,
    isConfigured,
    createEphemeralClient
  };
}
