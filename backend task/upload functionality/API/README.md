# API - Upload Functionality

## Overview

The Upload API handles file ingestion from three stakeholder systems (PSP, Cashier/Internal, ERP), parses the files, maps columns to standardized fields, and returns structured transaction data. Since we don't have a database yet, all test data is stored as JSON files in this folder.

**Key behavior:** The AI mapping only happens **the first time** we see a new column format. After the user confirms, the mapping is **saved to memory**. Next time the same format is uploaded, the saved mapping is applied **automatically** — no AI call, no user review.

---

## How the Upload Flow Works

```
User uploads a file
    |
    v
1. Parse file → extract column headers
    |
    v
2. Check mapping memory → have we seen these headers before?
    |
    |--- YES (remembered) ─────────────────────────────┐
    |    Apply saved mapping instantly                  |
    |    mappingSource = "remembered"                   |
    |    confidence = 1.0, confirmed = true             |
    |    No user review needed                          |
    |                                                   |
    |--- NO (first time) ──────────────┐                |
    |    Call Claude Sonnet AI          |                |
    |    mappingSource = "llm"          |                |
    |    confidence = varies            |                |
    |    Show dialog for user review    |                |
    |        |                          |                |
    |        v                          |                |
    |    User confirms → save mapping   |                |
    |    to memory for next time        |                |
    |                                   |                |
    v                                   v                v
3. Normalize rows into Transaction objects using the mapping
    |
    v
4. Return UploadResponse
```

---

## Endpoints

### 1. `POST /api/upload`

**Purpose:** Accept a file upload, parse it, resolve column mapping (from memory, AI, or regex fallback), return standardized transactions + field mappings.

**Request:** `multipart/form-data`
- `file` (File) - CSV or JSON file, max 10 MB
- `stakeholder` (string) - `"Payment Service Providers"` | `"Cashier"` | `"ERP System"`

**Response shape:**
```json
{
  "uploadId": "uuid-v4",
  "stakeholder": "Payment Service Providers",
  "systemKey": "PSP",
  "result": {
    "transactions": [],
    "format": "csv",
    "detectedColumns": ["psp_txn_id", "merchant_ref", ...],
    "rowCount": 10,
    "errors": []
  },
  "mappings": [
    {
      "detectedColumn": "psp_txn_id",
      "mapsTo": "System ID",
      "confidence": 0.98,
      "confirmed": false
    }
  ],
  "mappingSource": "remembered | llm | regex_fallback",
  "createdAt": "2026-02-13T10:00:00.000Z"
}
```

**The `mappingSource` field tells the frontend what happened:**

| Value | What Happened | Frontend Action |
|-------|--------------|-----------------|
| `"remembered"` | Same format seen before, saved mapping applied instantly | No dialog, no review. Just show success toast. |
| `"llm"` | New format, AI mapped columns (first time) | Show MappingConfig dialog for user to review & confirm |
| `"regex_fallback"` | AI failed, regex patterns used | Show MappingConfig dialog for user to review & confirm |

**How it works internally:**
1. Receive file via multer
2. Parse CSV (using `csv-parse`) or JSON
3. Extract column headers + first 3-5 sample rows
4. **Check mapping memory** — if we've seen these exact headers before, use saved mapping (skip AI)
5. **If new format** — call Claude Sonnet AI for column mapping
6. **If AI fails** — fall back to regex pattern matching
7. Normalize rows into standardized `Transaction` objects using the mapping
8. Return `UploadResponse` with transactions, mappings, and `mappingSource`

### 2. `POST /api/upload/:uploadId/confirm`

**Purpose:** User confirms (or edits) the column mappings after reviewing them. This endpoint also **saves the mapping to memory** so it's auto-applied next time.

**Request:** `application/json`
```json
{
  "mappings": [
    { "detectedColumn": "psp_txn_id", "mapsTo": "System ID", "confidence": 0.98, "confirmed": true }
  ]
}
```

**Response:**
```json
{
  "uploadId": "uuid-v4",
  "status": "confirmed",
  "confirmedAt": "2026-02-13T10:05:00.000Z",
  "result": {
    "transactions": [],
    "format": "csv",
    "detectedColumns": [],
    "rowCount": 10,
    "errors": []
  }
}
```

**How it works internally:**
1. Look up the upload by ID
2. Re-parse the original file content using the **confirmed** mappings (user may have edited)
3. **Save the confirmed mapping to `mapping_memory.json`** — this is the key step that enables "remember forever"
4. Return re-normalized transactions

---

## Stakeholder-to-SystemKey Mapping

| Stakeholder Label | System Key |
|-------------------|------------|
| Payment Service Providers | PSP |
| Cashier | Cashier |
| ERP System | ERP |

---

## Standardized Fields (16 total)

These are the target fields every uploaded file gets mapped to:

| # | Field Display Name | Internal Key | Description |
|---|-------------------|--------------|-------------|
| 1 | System ID | systemId | Unique ID per source system |
| 2 | Transaction Ref | reference | Shared key for 3-way matching |
| 3 | Gross Amount | grossAmount | Amount before fees |
| 4 | Net Amount | netAmount | Amount after fees |
| 5 | Processing Fee | fee | Fee charged |
| 6 | Currency | currency | ISO 4217 code |
| 7 | Transaction Date | transactionDate | Primary date |
| 8 | Settlement Date | settlementDate | Secondary/clearing date |
| 9 | Client ID | clientId | Client identifier |
| 10 | Client Name | clientName | Client display name |
| 11 | Description | description | Transaction description |
| 12 | Status | status | Processing status |
| 13 | Payment Method | paymentMethod | Card, wire, etc. |
| 14 | Settlement Bank | settlementBank | Bank name |
| 15 | Bank Country | bankCountry | ISO country code |
| 16 | FX Rate | fxRate | Exchange rate (nullable) |

---

## JSON Data Files

Since we don't have a database yet, use these JSON files as mock data and test fixtures:

| File | Description |
|------|-------------|
| `psp_transactions.json` | 10 PSP transactions (from scenario1) |
| `internal_transactions.json` | 10 Internal/Cashier transactions (from scenario1) |
| `erp_transactions.json` | 9 ERP transactions (from scenario1, REF-0010 missing) |
| `sample_upload_response.json` | Example full API response for PSP upload |
| `sample_field_mappings.json` | Example FieldMapping[] for all 3 systems |

These files were converted from the CSV data in `data-by-faiz/scenario1/`.

---

## Implementation Steps

1. **Set up FastAPI server** with CORS for frontend (`pip install fastapi uvicorn python-multipart`)
2. **Create file parser** — use Python `csv.reader` for CSV, `json.loads` for JSON
3. **Create mapping memory store** — `mapping_memory.json` file (see `../AI/` folder for full implementation)
4. **Create AI column mapper** — calls OpenAI GPT-4o (see `../AI/` folder for prompts and code)
5. **Create regex fallback** — port patterns from `src/lib/fileProcessor.ts` to Python
6. **Wire up `resolve_mapping()` logic** — check memory first → then OpenAI → then regex
7. **Save mapping on confirm** — when user confirms, write to `mapping_memory.json`
8. **Create transaction normalizer** — maps raw rows to `Transaction` dicts
9. **Wire up endpoints** — `/api/upload` and `/api/upload/{uploadId}/confirm`
10. **Test** — upload same file twice, second time should be `mappingSource: "remembered"`

### Without a database:
- Store uploads in memory (Python `dict`)
- Store mapping memory in `mapping_memory.json` (persists across server restarts)
- The JSON files here serve as reference data for testing

```python
# In-memory store for active uploads
uploads: dict[str, dict] = {}

# Each entry looks like:
# uploads["uuid-here"] = {
#     "id": "uuid-here",
#     "raw_content": "csv content...",
#     "file_name": "psp_10_rows.csv",
#     "headers": ["psp_txn_id", "merchant_ref", ...],
#     "stakeholder": "Payment Service Providers",
#     "mappings": [...],
#     "result": {...},
# }
```
