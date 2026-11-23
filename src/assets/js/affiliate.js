const REF_STORAGE_KEY = 'thamoto_ref';
const REF_TTL_DAYS = 30;

function sanitizeCode(raw) {
  return String(raw || '')
    .trim()
    .toUpperCase()
    .replace(/[^A-Z0-9_-]/g, '')
    .slice(0, 24);
}

export const AffiliateTracker = {
  captureFromUrl() {
    try {
      const params = new URLSearchParams(window.location.search);
      const refParam = params.get('ref') || params.get('ctv');
      if (refParam) {
        this.setRefCode(refParam);
      }
    } catch {
      // Ignore malformed URLs
    }
  },

  setRefCode(rawCode) {
    const code = sanitizeCode(rawCode);
    if (!code) return null;
    const expiresAt = Date.now() + REF_TTL_DAYS * 24 * 60 * 60 * 1000;
    try {
      localStorage.setItem(REF_STORAGE_KEY, JSON.stringify({ code, expiresAt }));
    } catch {
      // Ignore storage quota errors
    }
    return code;
  },

  getRefCode() {
    try {
      const raw = localStorage.getItem(REF_STORAGE_KEY);
      if (!raw) return '';
      const parsed = JSON.parse(raw);
      if (!parsed || !parsed.code) return '';
      if (parsed.expiresAt && Date.now() > parsed.expiresAt) {
        localStorage.removeItem(REF_STORAGE_KEY);
        return '';
      }
      return sanitizeCode(parsed.code);
    } catch {
      return '';
    }
  },

  clearRefCode() {
    try {
      localStorage.removeItem(REF_STORAGE_KEY);
    } catch {
      // Ignore
    }
  },

  buildShareUrl(path = '/', code = '') {
    const cleanCode = sanitizeCode(code);
    const origin = window.location.origin;
    const url = new URL(path, origin);
    if (cleanCode) {
      url.searchParams.set('ref', cleanCode);
    }
    return url.toString();
  }
};
