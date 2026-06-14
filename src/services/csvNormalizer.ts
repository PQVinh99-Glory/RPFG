// Helper to remove Vietnamese tones/accents
function removeAccents(str: string): string {
  return str
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/đ/g, 'd')
    .replace(/Đ/g, 'D');
}

// Clean and normalize a header string for matching
function cleanHeader(header: string): string {
  if (!header) return '';
  return removeAccents(header)
    .trim()
    .toLowerCase()
    .replace(/[\s\-_./()]/g, ''); // Bỏ khoảng trắng, _, -, ., /, (, )
}

// =============================================
// INVENTORY CSV: map về tag_id + bin
// =============================================
const INVENTORY_ALIASES: Record<string, string[]> = {
  tag_id: ['tagid', 'batch', 'lpno', 'code', 'barcode', 'tagid', 'tag'],
  bin:    ['bin', 'location', 'vitri', 'vi_tri', 'kho', 'warehouse', 'loc']
};

// =============================================
// MASTER DATA CSV: map về batch, stock_code, qty, warehouse, create_date
// Hỗ trợ cả 2 schema: cũ (batch, stock_code, warehouse) và DB thực (tag_id, lp_no, wh_location)
// CSV mẫu: Stock Code, Warehouse, CREATEDATE, BATCH, Qty
// =============================================
const MASTER_DATA_ALIASES: Record<string, string[]> = {
  batch: [
    'batch', 'tagid', 'tag_id', 'code', 'barcode',
    // CSV mẫu dùng "BATCH"
    'BATCH'
  ],
  stock_code: [
    'stockcode', 'lpno', 'lp_no', 'lpno(stockcode)', 'itemcode', 'productcode',
    // CSV mẫu dùng "Stock Code"
    'stockcode', 'stock code', 'stock_code'
  ],
  qty: [
    'qty', 'quantity', 'soluong', 'so_luong', 'pcs', 'count',
    // CSV mẫu dùng "Qty"
    'Qty', 'QTY'
  ],
  warehouse: [
    'warehouse', 'wh', 'kho', 'whcode', 'whlocation', 'wh_location',
    // CSV mẫu dùng "Warehouse"
    'Warehouse', 'WAREHOUSE'
  ],
  create_date: [
    'createdate', 'create_date', 'date',
    // CSV mẫu dùng "CREATEDATE"
    'CREATEDATE', 'CreateDate', 'Create Date', 'createdatetime'
  ]
};

export function normalizeCsvData(
  rawRows: Record<string, any>[],
  type: 'inventory' | 'master_data'
): any[] {
  const aliases = type === 'inventory' ? INVENTORY_ALIASES : MASTER_DATA_ALIASES;

  return rawRows.map(row => {
    const normalizedRow: Record<string, any> = {};

    // Khởi tạo trường mặc định
    if (type === 'inventory') {
      normalizedRow.tag_id = '';
      normalizedRow.bin = '';
    } else {
      normalizedRow.batch = '';
      normalizedRow.stock_code = '';
      normalizedRow.qty = 0;
      normalizedRow.warehouse = '';
      normalizedRow.create_date = '';
    }

    // Duyệt qua từng key trong row gốc và map vào schema chuẩn
    Object.entries(row).forEach(([rawKey, val]) => {
      const cleanedKey = cleanHeader(rawKey);

      for (const [schemaKey, aliasList] of Object.entries(aliases)) {
        // So sánh cả cleaned và raw để bắt "Stock Code" → stockcode
        const cleanedAliases = aliasList.map(a => cleanHeader(a));
        if (cleanedKey === cleanHeader(schemaKey) || cleanedAliases.includes(cleanedKey)) {
          if (schemaKey === 'qty') {
            const parsedQty = parseFloat(String(val).replace(/,/g, ''));
            normalizedRow[schemaKey] = isNaN(parsedQty) ? 0 : parsedQty;
          } else {
            normalizedRow[schemaKey] = val !== null && val !== undefined
              ? String(val).trim()
              : '';
          }
          break;
        }
      }
    });

    return normalizedRow;
  });
}

// =============================================
// VALIDATE: lọc dòng hợp lệ
// =============================================
export function filterValidInventoryRows(rows: any[]): { tag_id: string; bin: string }[] {
  return rows
    .filter(r => r.tag_id && r.tag_id.trim() !== '')
    .map(r => ({
      tag_id: r.tag_id.trim(),
      bin:    r.bin ? r.bin.trim() : ''
    }));
}

export function filterValidMasterDataRows(rows: any[]): any[] {
  return rows
    .filter(r => r.batch && r.batch.trim() !== '' && r.stock_code && r.stock_code.trim() !== '')
    .map(r => ({
      batch:      r.batch.trim(),
      stock_code: r.stock_code.trim(),
      qty:        r.qty || 0,
      warehouse:  r.warehouse ? r.warehouse.trim() : '',
      create_date: r.create_date ? r.create_date.trim() : ''
    }));
}
