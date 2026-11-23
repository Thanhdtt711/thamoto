const REF_STORAGE_KEY = 'thamoto_ref';
const REF_TTL_DAYS = 30;

function sanitizeCode(raw: unknown): string {
  return String(raw || '')
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9_-]/g, '')
    .slice(0, 24);
}

export function useAffiliate() {
  const refCode = useState<string>('affiliate-ref', () => '');

  const setRefCode = (rawCode: string) => {
    const code = sanitizeCode(rawCode);
    if (!code) return '';
    refCode.value = code;
    if (import.meta.client) {
      const expiresAt = Date.now() + REF_TTL_DAYS * 24 * 60 * 60 * 1000;
      try {
        localStorage.setItem(REF_STORAGE_KEY, JSON.stringify({ code, expiresAt }));
      } catch {
        // Ignore
      }
    }
    return code;
  };

  const getRefCode = (): string => {
    if (refCode.value) return refCode.value;
    if (!import.meta.client) return '';
    try {
      const raw = localStorage.getItem(REF_STORAGE_KEY);
      if (!raw) return '';
      const parsed = JSON.parse(raw);
      if (!parsed?.code) return '';
      if (parsed.expiresAt && Date.now() > parsed.expiresAt) {
        localStorage.removeItem(REF_STORAGE_KEY);
        return '';
      }
      refCode.value = sanitizeCode(parsed.code);
      return refCode.value;
    } catch {
      return '';
    }
  };

  const captureFromRoute = () => {
    if (!import.meta.client) return;
    const route = useRoute();
    const param = route.query.ref || route.query.ctv;
    if (param) {
      setRefCode(Array.isArray(param) ? String(param[0]) : String(param));
    } else {
      getRefCode();
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
    setRefCode,
    getRefCode,
    captureFromRoute,
    buildShareUrl
  };
}
