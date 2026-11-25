/**
 * Xuất dữ liệu ra file CSV chuẩn UTF-8 BOM (mở tiếng Việt không lỗi font trên Excel).
 */
export function exportToCsv(
  filename: string,
  headers: string[],
  rows: Array<Array<string | number | null | undefined>>
) {
  if (!import.meta.client) return;

  const escapeCell = (val: string | number | null | undefined) => {
    const str = String(val ?? '');
    // Chống CSV formula injection khi mở bằng Excel
    const safe = /^[=+\-@]/.test(str) ? `'${str}` : str;
    if (/[",\r\n]/.test(safe)) {
      return `"${safe.replace(/"/g, '""')}"`;
    }
    return safe;
  };

  const lines = [
    headers.map(escapeCell).join(','),
    ...rows.map((r) => r.map(escapeCell).join(',')),
  ];

  const bom = '\uFEFF';
  const blob = new Blob([bom + lines.join('\r\n')], { type: 'text/csv;charset=utf-8;' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename.endsWith('.csv') ? filename : `${filename}.csv`;
  document.body.appendChild(a);
  a.click();
  document.body.removeChild(a);
  URL.revokeObjectURL(url);
}
