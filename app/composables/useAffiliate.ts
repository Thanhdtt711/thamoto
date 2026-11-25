const REF_STORAGE_KEY = 'thamoto_ref';
const REF_COOKIE_NAME = 'thamoto_ref';
const REF_TTL_DAYS = 30;

function sanitizeCode(raw: unknown): string {
  return String(raw || '')
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9_-]/g, '')
    .slice(0, 24);
}

function readCookie(name: string): string {
  if (!import.meta.client) return '';
  const match = document.cookie.match(new RegExp(`(?:^|; )${name}=([^;]*)`));
  return match ? decodeURIComponent(match[1] || '') : '';
}

function writeCookie(name: string, value: string, days: number) {
  if (!import.meta.client) return;
  const maxAge = Math.max(0, Math.floor(days * 24 * 60 * 60));
  document.cookie = `${name}=${encodeURIComponent(value)}; path=/; max-age=${maxAge}; SameSite=Lax`;
}

export function useAffiliate() {
  const refCode = useState<string>('affiliate-ref', () => '');
  const refSource = useState<'link' | 'manual'>('affiliate-ref-source', () => 'link');
  const refClickId = useState<string | null>('affiliate-click-id', () => null);

  const setRefCode = (rawCode: string, source: 'link' | 'manual' = 'link', clickId: string | null = null) => {
    const code = sanitizeCode(rawCode);
    if (!code) return '';
    refCode.value = code;
    refSource.value = source;
    if (clickId) refClickId.value = clickId;

    if (import.meta.client) {
      const expiresAt = Date.now() + REF_TTL_DAYS * 24 * 60 * 60 * 1000;
      try {
        localStorage.setItem(REF_STORAGE_KEY, JSON.stringify({ code, source, clickId: refClickId.value, expiresAt }));
      } catch {
        // Ignore quota errors
      }
      writeCookie(REF_COOKIE_NAME, code, REF_TTL_DAYS);
    }
    return code;
  };

  const getRefCode = (): string => {
    if (refCode.value) return refCode.value;
    if (!import.meta.client) return '';
    try {
      const raw = localStorage.getItem(REF_STORAGE_KEY);
      if (raw) {
        const parsed = JSON.parse(raw);
        if (parsed?.code && (!parsed.expiresAt || Date.now() <= parsed.expiresAt)) {
          refCode.value = sanitizeCode(parsed.code);
          refSource.value = parsed.source === 'manual' ? 'manual' : 'link';
          refClickId.value = parsed.clickId || null;
          return refCode.value;
        }
        localStorage.removeItem(REF_STORAGE_KEY);
      }
    } catch {
      // Fallback to cookie
    }

    const fromCookie = sanitizeCode(readCookie(REF_COOKIE_NAME));
    if (fromCookie) {
      refCode.value = fromCookie;
      refSource.value = 'link';
      return fromCookie;
    }
    return '';
  };

  const captureFromRoute = () => {
    if (!import.meta.client) return;
    const route = useRoute();
    const param = route.query.ref || route.query.ctv;
    if (param) {
      const clean = setRefCode(Array.isArray(param) ? String(param[0]) : String(param), 'link');
      if (clean) {
        trackClickIfAvailable(clean, route.fullPath);
      }
    } else {
      getRefCode();
    }
  };

  const trackClickIfAvailable = async (code: string, landingPath: string) => {
    if (!import.meta.client) return;
    const dedupeKey = `thamoto_click_${code}`;
    try {
      const last = Number(sessionStorage.getItem(dedupeKey) || 0);
      if (Date.now() - last < 5 * 60 * 1000) return;
      sessionStorage.setItem(dedupeKey, String(Date.now()));
    } catch {
      // Ignore
    }

    const { supabase, isConfigured } = useSupabase();
    if (!isConfigured || !supabase) return;
    try {
      let sid = localStorage.getItem('thamoto_sid');
      if (!sid) {
        sid = crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + Math.random().toString(36).slice(2);
        localStorage.setItem('thamoto_sid', sid);
      }
      const { data } = await supabase.rpc('track_click', {
        p_affiliate_code: code,
        p_landing_path: landingPath.slice(0, 255),
        p_session_id: sid
      });
      if (data?.click_id) {
        setRefCode(code, 'link', String(data.click_id));
      }
    } catch {
      // Graceful fallback if P1 click tracking migration is not yet applied
    }
  };

  const buildShareUrl = (path = '/', code = '') => {
    const cleanCode = sanitizeCode(code);
    const origin = import.meta.client ? window.location.origin : 'https://thamoto.vercel.app';
    const url = new URL(path, origin);
    if (cleanCode) url.searchParams.set('ref', cleanCode);
    return url.toString();
  };

  return {
    refCode,
    refSource,
    refClickId,
    setRefCode,
    getRefCode,
    captureFromRoute,
    buildShareUrl
  };
}
