# AI - Upload Functionality

# TLDR:

Semua file yang diupload adalah based on rules. Tapi sebab kita bagi kebebasan pada PSP, jadi kemungkinan ada
resiko file mapping entah apa-apa. Sebab itu kita buat auto-mapping bila kita mudahkan user untuk buat ETL,
guna AI (OpenAI GPT-4o) untuk detect column headers. So tak perlu gaduh-gaduh nak pastikan mapping dan format sama.

Cuma buat masa ini kita masukkan human loops dalam process dimana diaorang kena confirmkan mapping dalam tempoh
masa 2 jam (default settings), selepas 2 jam, kita akan push juga source file dalam system guna mapping sedia ada.

Kemudian sebabkan PSP bermasalah biasanya guna format yang sama (sama ada file title lebih kurang sama), so setting ini untuk kali pertama je. kali kedua system kita akan ingat dan tak perlu buat auto mapping lagi.

Please refer this link: [Klik sini](https://deriv-hackathon-tideline.vercel.app/upload)

## The Problem

When users upload transaction files (CSV/JSON), every system uses **different column names** for the same data:

| What it means | PSP calls it | Cashier calls it | ERP calls it |
|--------------|-------------|-----------------|-------------|
| Unique ID | `psp_txn_id` | `internal_id` | `erp_doc_number` |
| Reference | `merchant_ref` | `ext_reference` | `reference` |
| Amount | `gross_amount` | `total_amount` | `posted_amount` |
| Date | `transaction_date` | `booking_date` | `posting_date` |
| Settlement | `settlement_date` | `value_date` | `clearing_date` |
| Fee | `processing_fee` | `fee_amount` | `fee_amount` |

And when a **new data source** comes in with completely different headers (e.g., `txn_ts`, `ccy`, `benef_name`, `doc_id`), hardcoded regex patterns break. We need AI to figure it out.

---

## What the AI Does: Auto-Mapping (Learn Once, Remember Forever)

The core idea is simple:

> **First time** we see a column format → AI maps it + user confirms → we **save** the mapping.
> **Next time** we see the same format → we **skip AI entirely**, apply the saved mapping instantly. No permission needed.

### The 3-Step Flow

```
UPLOAD FILE
    |
    v
Step 1: Extract column headers from the file
        e.g. ["psp_txn_id", "merchant_ref", "gross_amount", ...]
    |
    v
Step 2: Check — have we seen these exact headers before?
    |
    |--- YES → Load saved mapping from memory/JSON file
    |          Apply instantly, no AI call, no user review
    |          confidence = 1.0, confirmed = true
    |          mappingSource = "remembered"
    |
    |--- NO → This is a NEW format we've never seen
    |         Call Claude Sonnet AI to auto-map
    |         Show mapping to user for review (first time only)
    |         User confirms → Save mapping for future use
    |         mappingSource = "llm"
    |
    v
Step 3: Normalize transactions using the mapping
```

### Why This is Smart

- **First upload of a PSP file:** AI analyzes headers, maps `psp_txn_id` → "System ID", user confirms. Takes ~2-3 seconds.
- **Second upload of a PSP file (same format):** System recognizes the headers, instantly applies the saved mapping. Takes ~0ms. No AI call. No user review dialog.
- **New vendor with weird headers like `txn_ts`, `ccy`:** AI figures it out, user confirms once, then it's remembered forever.

---

## What Kind of AI We Use

### Model: OpenAI GPT-4o

- **Model ID:** `gpt-4o`
- **SDK:** `openai` (official Python SDK)
- **API Key:** Set as environment variable `OPENAI_API_KEY`
- **Cost:** ~$2.50 per million input tokens, ~$10 per million output tokens
- **Latency:** ~1-3 seconds per mapping request

### Why OpenAI GPT-4o?

1. **Structured JSON output** — Returns clean JSON arrays, supports `temperature=0` for deterministic output
2. **Financial domain knowledge** — Understands terms like "posted_amount", "clearing_date", "net_payout"
3. **Handles unknown headers** — Can infer meaning from abbreviations (`ccy` = currency, `txn_ts` = transaction timestamp)
4. **Cost-effective** — Only called once per new format, then remembered. So actual cost is near-zero over time.

---

## The 16 Standard Fields

Every uploaded file gets mapped to these fields:

| Standard Field | What It Means | Example Value |
|---------------|---------------|---------------|
| System ID | Unique ID from source system | `PSP-AAA111BBB222` |
| Transaction Ref | Shared key for 3-way matching | `REF-0001` |
| Gross Amount | Amount before fees | `1000.00` |
| Net Amount | Amount after fees | `980.00` |
| Processing Fee | Fee charged | `20.00` |
| Currency | ISO 4217 code | `MYR` |
| Transaction Date | When transaction occurred | `2026-02-01T10:00:00` |
| Settlement Date | When funds settled | `2026-02-02T10:00:00` |
| Client ID | Client identifier | `CLT-1001` |
| Client Name | Client display name | `Alpha Sdn Bhd` |
| Description | Free-text description | `Payment via card` |
| Status | Transaction status | `captured` |
| Payment Method | How payment was made | `card` |
| Settlement Bank | Bank handling settlement | `Maybank` |
| Bank Country | Country of bank | `MY` |
| FX Rate | Exchange rate (nullable) | `4.5` or `null` |

---

## How to Implement

### Step 1: Create the Mapping Memory Store

Since we don't have a database yet, store remembered mappings in a JSON file.

**File: `server/mapping_memory.py`**

```python
import json
import os
from datetime import datetime

MEMORY_FILE = os.path.join(os.path.dirname(__file__), "data", "mapping_memory.json")


def _fingerprint(headers: list[str]) -> str:
    """Create a unique key from sorted, lowercased headers."""
    return "|".join(sorted(h.lower().strip() for h in headers))


def _load_memory() -> list[dict]:
    if not os.path.exists(MEMORY_FILE):
        return []
    with open(MEMORY_FILE, "r") as f:
        return json.load(f)


def _save_memory(memory: list[dict]) -> None:
    os.makedirs(os.path.dirname(MEMORY_FILE), exist_ok=True)
    with open(MEMORY_FILE, "w") as f:
        json.dump(memory, f, indent=2)


def find_saved_mapping(headers: list[str]) -> dict | None:
    """Check if we've seen these exact headers before."""
    memory = _load_memory()
    fp = _fingerprint(headers)
    for entry in memory:
        if entry["fingerprint"] == fp:
            return entry
    return None


def save_mapping(headers: list[str], mappings: list[dict], stakeholder: str) -> None:
    """Save a confirmed mapping for future reuse."""
    memory = _load_memory()
    fp = _fingerprint(headers)

    entry = {
        "fingerprint": fp,
        "headers": headers,
        "mappings": [{**m, "confirmed": True, "confidence": 1.0} for m in mappings],
        "stakeholder": stakeholder,
        "savedAt": datetime.utcnow().isoformat() + "Z",
        "usageCount": 0,
    }

    existing_idx = next((i for i, e in enumerate(memory) if e["fingerprint"] == fp), None)
    if existing_idx is not None:
        memory[existing_idx] = entry
    else:
        memory.append(entry)

    _save_memory(memory)


def increment_usage(headers: list[str]) -> None:
    """Increment usage counter when a saved mapping is reused."""
    memory = _load_memory()
    fp = _fingerprint(headers)
    for entry in memory:
        if entry["fingerprint"] == fp:
            entry["usageCount"] = entry.get("usageCount", 0) + 1
            _save_memory(memory)
            return
```

### Step 2: Create the AI Mapper

**File: `server/llm_mapper.py`**

```python
import json
import os
from openai import OpenAI

client = OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))

SYSTEM_PROMPT = """You are a financial data column mapper for a 3-way reconciliation system.
Your job is to map raw CSV/JSON column headers to standardized field names.

You will receive:
1. A list of raw column headers from an uploaded file
2. 3-5 sample data rows to provide context about the data

Map each column to exactly ONE of these standard fields (or leave unmapped):
- System ID
- Transaction Ref
- Gross Amount
- Net Amount
- Processing Fee
- Currency
- Transaction Date
- Settlement Date
- Client ID
- Client Name
- Description
- Status
- Payment Method
- Settlement Bank
- Bank Country
- FX Rate

Confidence scoring rules:
- 0.95-1.00: Exact or near-exact match (e.g. "psp_txn_id" -> "System ID")
- 0.80-0.94: Strong semantic match (e.g. "booking_date" -> "Transaction Date")
- 0.60-0.79: Ambiguous but reasonable guess (e.g. "posted_amount" -> "Gross Amount")
- Below 0.60: Weak guess - set mapsTo to "" (unmapped)

Rules:
- Each standard field can be mapped to AT MOST one column
- If a column doesn't clearly map to any standard field, set mapsTo to "" and confidence to 0
- Never map the same standard field to multiple columns
- Respond with ONLY a JSON array, no explanation or markdown"""


def map_columns_with_llm(
    headers: list[str],
    sample_rows: list[list[str]],
    stakeholder: str,
) -> list[dict]:
    """Call OpenAI GPT-4o to map column headers to standard fields."""
    sample_text = "\n".join(
        f"Row {i + 1}: {', '.join(row)}" for i, row in enumerate(sample_rows)
    )

    user_prompt = f"""Column headers: {json.dumps(headers)}

Sample data (first {len(sample_rows)} rows):
{sample_text}

Stakeholder system: {stakeholder}

Return a JSON array of objects with this exact shape:
[
  {{ "detectedColumn": "column_name", "mapsTo": "Standard Field Name", "confidence": 0.95, "confirmed": false }},
  ...
]

One object per column header. Set confirmed to false for all."""

    response = client.chat.completions.create(
        model="gpt-4o",
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
        max_tokens=1024,
        temperature=0,
    )

    text = response.choices[0].message.content.strip()

    # Strip markdown code fences if present
    if text.startswith("```"):
        text = text.split("\n", 1)[1]
        text = text.rsplit("```", 1)[0]

    mappings = json.loads(text)

    # Validate: ensure every header is represented
    mapped_headers = {m["detectedColumn"] for m in mappings}
    for h in headers:
        if h not in mapped_headers:
            mappings.append({
                "detectedColumn": h,
                "mapsTo": "",
                "confidence": 0,
                "confirmed": False,
            })

    return mappings
```

### Step 3: Wire It All Together in the Upload Handler

**The decision logic in the upload endpoint:**

```python
from server.mapping_memory import find_saved_mapping, increment_usage
from server.llm_mapper import map_columns_with_llm
from server.regex_fallback import detect_mappings_regex


def resolve_mapping(
    headers: list[str],
    sample_rows: list[list[str]],
    stakeholder: str,
) -> tuple[list[dict], str]:
    """
    Resolve column mappings using this priority:
      1. Mapping memory (saved from previous confirmed upload)
      2. OpenAI GPT-4o (first-time AI mapping)
      3. Regex fallback (if OpenAI fails)

    Returns: (mappings, source)
    """

    # ── Step 1: Check mapping memory ──
    saved = find_saved_mapping(headers)
    if saved:
        print(f"Mapping REMEMBERED for {stakeholder} (used {saved.get('usageCount', 0) + 1} times)")
        increment_usage(headers)
        return saved["mappings"], "remembered"

    # ── Step 2: New format — call OpenAI ──
    try:
        print(f"NEW format for {stakeholder} — calling OpenAI GPT-4o...")
        mappings = map_columns_with_llm(headers, sample_rows, stakeholder)
        return mappings, "llm"
    except Exception as err:
        # ── Step 3: OpenAI failed — fall back to regex ──
        print(f"OpenAI failed, using regex fallback: {err}")
        mappings = detect_mappings_regex(headers)
        return mappings, "regex_fallback"
```

### Step 4: Save Mapping When User Confirms

In the `POST /api/upload/:uploadId/confirm` handler:

```python
from server.mapping_memory import save_mapping

@app.post("/api/upload/{upload_id}/confirm")
async def confirm_upload(upload_id: str, body: dict):
    mappings = body["mappings"]

    # ... validate and re-normalize transactions ...

    # IMPORTANT: Save this mapping to memory so we never ask again
    upload = uploads.get(upload_id)
    if upload:
        save_mapping(upload["headers"], mappings, upload["stakeholder"])
        print(f"Mapping SAVED for {upload['stakeholder']} — will auto-apply next time")

    return {"uploadId": upload_id, "status": "confirmed", "confirmedAt": datetime.utcnow().isoformat() + "Z", "result": result}
```

---

## Complete Flow Diagram

```
User uploads PSP file (first time)
    |
    v
Extract headers: ["psp_txn_id", "merchant_ref", "gross_amount", ...]
    |
    v
Check mapping_memory.json → NOT FOUND (first time)
    |
    v
Call Claude Sonnet AI → returns FieldMapping[] with confidence scores
    |
    v
Return to frontend:
  mappingSource = "llm"
  confirmed = false
    |
    v
Frontend shows MappingConfig dialog → User reviews & confirms
    |
    v
POST /api/upload/:id/confirm → Backend saves mapping to mapping_memory.json
    |
    v
Done! Mapping is now REMEMBERED.

═══════════════════════════════════════════════

User uploads PSP file (second time, same format)
    |
    v
Extract headers: ["psp_txn_id", "merchant_ref", "gross_amount", ...]
    |
    v
Check mapping_memory.json → FOUND! (fingerprint matches)
    |
    v
Apply saved mapping instantly:
  confidence = 1.0
  confirmed = true
  mappingSource = "remembered"
    |
    v
Return to frontend → No dialog shown, no user review needed
    |
    v
Done! Zero AI cost, zero latency, zero friction.
```

---

## How the Fingerprint Works

We identify a "column format" by creating a **fingerprint** from the sorted, lowercased headers:

```
Input headers:  ["psp_txn_id", "merchant_ref", "gross_amount", "currency"]
Fingerprint:    "currency|gross_amount|merchant_ref|psp_txn_id"
```

**Why sorted?** Because column ORDER might change between uploads (e.g., someone rearranges columns in Excel). The fingerprint ignores order — only the column NAMES matter.

**When does the fingerprint NOT match?**
- A column is added → new fingerprint → AI is called again
- A column is removed → new fingerprint → AI is called again
- A column is renamed → new fingerprint → AI is called again
- Columns are reordered → SAME fingerprint → saved mapping is used

---

## mapping_memory.json (Example)

This file grows over time as new formats are encountered:

```json
[
  {
    "fingerprint": "bank_country|client_id|client_name|currency|description|fx_rate|gross_amount|merchant_ref|net_payout|payment_method|processing_fee|psp_txn_id|settlement_bank|settlement_date|status|transaction_date",
    "headers": ["psp_txn_id", "merchant_ref", "gross_amount", "currency", "processing_fee", "net_payout", "transaction_date", "settlement_date", "client_id", "client_name", "description", "status", "payment_method", "settlement_bank", "bank_country", "fx_rate"],
    "mappings": [
      { "detectedColumn": "psp_txn_id", "mapsTo": "System ID", "confidence": 1.0, "confirmed": true },
      { "detectedColumn": "merchant_ref", "mapsTo": "Transaction Ref", "confidence": 1.0, "confirmed": true },
      { "detectedColumn": "gross_amount", "mapsTo": "Gross Amount", "confidence": 1.0, "confirmed": true }
    ],
    "stakeholder": "Payment Service Providers",
    "savedAt": "2026-02-13T10:05:00.000Z",
    "usageCount": 14
  },
  {
    "fingerprint": "bank_country|booking_date|client_id|client_name|currency|description|ext_reference|fee_amount|fx_rate|internal_id|net_amount|payment_method|settlement_bank|status|total_amount|value_date",
    "headers": ["internal_id", "ext_reference", "total_amount", "currency", "fee_amount", "net_amount", "booking_date", "value_date", "client_id", "client_name", "description", "status", "payment_method", "settlement_bank", "bank_country", "fx_rate"],
    "mappings": [
      { "detectedColumn": "internal_id", "mapsTo": "System ID", "confidence": 1.0, "confirmed": true },
      { "detectedColumn": "ext_reference", "mapsTo": "Transaction Ref", "confidence": 1.0, "confirmed": true },
      { "detectedColumn": "total_amount", "mapsTo": "Gross Amount", "confidence": 1.0, "confirmed": true }
    ],
    "stakeholder": "Cashier",
    "savedAt": "2026-02-13T10:06:00.000Z",
    "usageCount": 8
  }
]
```

---

## Why AI Beats Regex (But We Only Pay Once)

| Scenario | Regex | AI | After Memory |
|----------|-------|-----|-------------|
| Known header `psp_txn_id` | Matches | Maps correctly | Instant (free) |
| Unknown header `txn_ts` | No match | AI infers "transaction timestamp" | Instant (free) |
| Abbreviation `ccy` | No match | AI knows "ccy" = currency | Instant (free) |
| `benef_name` | No match | AI maps to "Client Name" | Instant (free) |
| `doc_id` | No match | AI maps to "System ID" | Instant (free) |

**Key insight:** The AI cost is a one-time expense per unique format. After that, the mapping is free and instant forever.

---

## Response: mappingSource Field

The API response includes a `mappingSource` field so the frontend knows what happened:

| Value | Meaning | Frontend Behavior |
|-------|---------|-------------------|
| `"remembered"` | Saved mapping applied automatically | No dialog shown, no review needed |
| `"llm"` | AI mapped for the first time | Show MappingConfig dialog for user review |
| `"regex_fallback"` | AI failed, regex was used | Show MappingConfig dialog for user review |

Frontend logic:
```typescript
const { result, mappings, mappingSource, uploadId } = await uploadFileToBackend(file, stakeholder);

if (mappingSource === "remembered") {
  // Skip dialog — mapping was auto-applied from memory
  toast({ title: "Mapping applied automatically", description: "Using saved mapping from previous upload." });
} else {
  // First time or fallback — show review dialog
  const hasIssues = mappings.some((m) => m.confidence < 0.7 || m.mapsTo === "");
  if (hasIssues) {
    setMappingDialogOpen(true);
  }
}
```

---

## Edge Cases

1. **Same headers, different stakeholder** — The fingerprint is based on headers only, not stakeholder. But the saved mapping includes the stakeholder for reference. If two systems happen to use identical headers, the same mapping applies (which is correct — same headers = same meaning).

2. **User edits a mapping before confirming** — The edited version gets saved, not the original AI suggestion. So next time, the user's preferred mapping is applied.

3. **Columns added or removed** — New fingerprint, so AI is called again. The old mapping is not affected (it stays in memory for files with the original format).

4. **LLM returns garbage** — Falls back to regex. If user confirms the regex-based mapping, it gets saved to memory just the same.

5. **User wants to reset a saved mapping** — Could add a `DELETE /api/mappings/:fingerprint` endpoint later, or manually edit `mapping_memory.json`.

---

## Implementation Checklist

- [ ] Install `openai` Python package (`pip install openai`)
- [ ] Set `OPENAI_API_KEY` environment variable
- [ ] Create `mapping_memory.py` — fingerprint, find, save, increment
- [ ] Create `llm_mapper.py` — system prompt, user prompt, OpenAI API call
- [ ] Create `regex_fallback.py` — port patterns from `src/lib/fileProcessor.ts`
- [ ] Wire up `resolve_mapping()` in upload handler (memory → OpenAI → regex)
- [ ] Save confirmed mappings in confirm handler
- [ ] Create `data/mapping_memory.json` (starts as `[]`)
- [ ] Add `mappingSource` field to API response (`"remembered"` | `"llm"` | `"regex_fallback"`)
- [ ] Test: upload PSP file → OpenAI maps → confirm → upload same file again → should be instant
- [ ] Test: upload file with unknown headers → OpenAI maps → confirm → remembered
- [ ] Test: break API key → regex fallback → confirm → remembered
