# Reconciliation Engine — API Documentation

## TLDR

Kita ada 3 file yang dah di-upload (PSP, Cashier, ERP). Sekarang kena match 3 file tu — cari mana transaction yang sama, mana yang tak sama, mana yang missing.

Pipeline dia 5 step je:
1. **Duplicate detection** — check kat dalam satu system ada duplicate tak
2. **Reference match** — match guna transaction reference (~90% match)
3. **Fuzzy fallback** — kalau reference tak jumpa, try match guna amount + date + client (~8% more)
4. **Three-way verify** — dah match tu, check betul ke amount sama? Date sama? Fee sama?
5. **Generate report** — compile semua result + stats

Frontend dah siap render everything. Backend just kena return data dalam shape yang betul.

**6 endpoints** kena buat:
1. `POST /api/reconciliation/run` — trigger the pipeline
2. `GET /api/reconciliation/{id}` — fetch result
3. `POST /api/reconciliation/{id}/resolve` — manually resolve discrepancy
4. `GET /api/reconciliation/{id}/records/{recordId}` — individual record detail (for modal)
5. `GET /api/reconciliation/{id}/audit` — audit trail
6. `GET /api/reconciliation/{id}/discrepancies` — list discrepancies

Please refer this link: [Klik sini](https://deriv-hackathon-tideline.vercel.app/reconciliation)

---

## How the Reconciliation Flow Works

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        RECONCILIATION FLOW                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Frontend sends 3 upload IDs (PSP + Cashier + ERP)                          │
│                    │                                                        │
│                    ▼                                                        │
│  ┌──────────────────────────────────────────────┐                           │
│  │ 1. LOAD TRANSACTIONS                         │                           │
│  │    From each upload (already normalized)      │                           │
│  └──────────────────────────────────────────────┘                           │
│                    │                                                        │
│                    ▼                                                        │
│  ┌──────────────────────────────────────────────────────────────────────┐   │
│  │ 2. RUN 5-STEP PIPELINE                                              │   │
│  │                                                                      │   │
│  │  Step 1: DUPLICATE DETECTION                                         │   │
│  │  ┌──────────────────────────────────┐                                │   │
│  │  │ Group by (reference + amount +   │──→ Flag duplicates             │   │
│  │  │ date) within each system         │    (e.g. INT-0007-DUP)        │   │
│  │  └──────────────────────────────────┘                                │   │
│  │                    │                                                  │   │
│  │                    ▼                                                  │   │
│  │  Step 2: REFERENCE MATCH                                             │   │
│  │  ┌──────────────────────────────────┐                                │   │
│  │  │ Match PSP ↔ Internal ↔ ERP      │──→ ~90% matched                │   │
│  │  │ by `reference` field             │                                │   │
│  │  └──────────────────────────────────┘                                │   │
│  │                    │                                                  │   │
│  │                    ▼                                                  │   │
│  │  Step 3: FUZZY FALLBACK                                              │   │
│  │  ┌──────────────────────────────────┐                                │   │
│  │  │ For unmatched: try matching by   │──→ Catches remaining ~8%       │   │
│  │  │ (amount ± $0.01) + (date ±       │                                │   │
│  │  │ 5 days) + same client_id         │                                │   │
│  │  └──────────────────────────────────┘                                │   │
│  │                    │                                                  │   │
│  │                    ▼                                                  │   │
│  │  Step 4: THREE-WAY VERIFY                                            │   │
│  │  ┌──────────────────────────────────┐                                │   │
│  │  │ For all matched triplets, check: │──→ Generate discrepancy        │   │
│  │  │ - Amount consistency (gross/net) │    records for mismatches      │   │
│  │  │ - Date consistency (±5 days)     │                                │   │
│  │  │ - Fee consistency                │                                │   │
│  │  │ - FX rate consistency            │                                │   │
│  │  │ - Missing legs                   │                                │   │
│  │  └──────────────────────────────────┘                                │   │
│  │                    │                                                  │   │
│  │                    ▼                                                  │   │
│  │  Step 5: GENERATE REPORT                                             │   │
│  │  ┌──────────────────────────────────┐                                │   │
│  │  │ Compile summary stats +          │──→ Return ReconciliationResult │   │
│  │  │ record-level details + legs      │                                │   │
│  │  └──────────────────────────────────┘                                │   │
│  └──────────────────────────────────────────────────────────────────────┘   │
│                    │                                                        │
│                    ▼                                                        │
│  ┌──────────────────────────────────────────────┐                           │
│  │ 3. STORE RESULT                              │                           │
│  │    reconciliation_runs + records + legs +     │                           │
│  │    discrepancies                              │                           │
│  └──────────────────────────────────────────────┘                           │
│                    │                                                        │
│                    ▼                                                        │
│  ┌──────────────────────────────────────────────┐                           │
│  │ 4. CREATE AUDIT EVENTS                       │                           │
│  │    Batch Started → Pattern Analysis →         │                           │
│  │    Anomaly Detected → Batch Completed         │                           │
│  └──────────────────────────────────────────────┘                           │
│                    │                                                        │
│                    ▼                                                        │
│  ┌──────────────────────────────────────────────┐                           │
│  │ 5. RETURN ReconciliationResult to frontend   │                           │
│  └──────────────────────────────────────────────┘                           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

**After the pipeline runs**, the frontend displays:
- **Summary cards** — total, matched, partial, unmatched, discrepancies, match rate
- **Records table** — paginated list of all 15+ records with status badges
- **Record detail modal** — click any row → shows 3-way comparison + AI analysis
- **Discrepancy tab** — filtered list of discrepancies with severity
- **Audit trail tab** — timeline of all events (system, AI, user actions)

---

## Endpoints (6 Total)

### 1. `POST /api/reconciliation/run`

**Purpose:** Run the full reconciliation pipeline on 3 uploaded datasets.

**Request:**
```json
{
  "pspUploadId": "upload_psp_abc123",
  "internalUploadId": "upload_int_def456",
  "erpUploadId": "upload_erp_ghi789"
}
```

All 3 upload IDs must reference completed, validated uploads from the upload API. Each upload contains an array of standardized `Transaction` objects (16 fields — see field reference below).

**Response:** `ReconciliationResult` — see [Response Shapes](#response-shapes) and `sample_reconciliation_result.json`.

**Status codes:**
| Code | Meaning |
|------|---------|
| 200  | Reconciliation completed successfully |
| 400  | Missing or invalid upload IDs |
| 404  | One or more uploads not found |
| 422  | Upload data not yet validated / field mapping incomplete |

**How it works internally:**
1. Load transactions from 3 uploads (from upload store or DB)
2. Run `detect_duplicates()` on each system's transactions (Step 1)
3. Run `reference_match()` across all 3 systems (Step 2)
4. For unmatched transactions, run `fuzzy_match()` (Step 3)
5. For all matched triplets, run `verify_triplet()` (Step 4)
6. Run `generate_report()` to compile the final result (Step 5)
7. Save to DB: create `reconciliation_run`, insert `reconciliation_records`, insert `transaction_legs` (3 per record), insert `discrepancies`
8. Create audit events: "Batch Started", "Pattern Analysis", "Anomaly Detected" (per discrepancy), "Batch Completed"
9. Return `ReconciliationResult`

---

### 2. `GET /api/reconciliation/{reconciliationId}`

**Purpose:** Fetch a previously run reconciliation result by its ID.

**Response:** Same `ReconciliationResult` shape as the run endpoint.

**Query parameters:**
| Param    | Type   | Default | Description |
|----------|--------|---------|-------------|
| `status` | string | all     | Filter records: `matched`, `partial`, `unmatched`, `discrepancy` |
| `page`   | int    | 1       | Pagination page number |
| `limit`  | int    | 50      | Records per page |

**How it works internally:**
1. Look up `reconciliation_runs` by ID
2. Load `reconciliation_records` with pagination + optional status filter
3. For each record, load its 3 `transaction_legs`
4. Load summary stats from the run
5. Return `ReconciliationResult` with nested records + legs

---

### 3. `GET /api/reconciliation/{reconciliationId}/records/{recordId}`

**Purpose:** Get full detail for a single record. This is what the frontend renders in the **detail modal** when user clicks a row.

**Response:** See [`sample_record_detail.json`](./sample_record_detail.json) for 3 example responses (matched, partial, unmatched).

```json
{
  "record": { ... },
  "systemComparison": [ ... ],
  "fieldComparison": [ ... ],
  "discrepancy": { ... } | null,
  "aiAnalysis": { ... } | null
}
```

**How it works internally:**
1. Load `reconciliation_record` by ID
2. Load 3 `transaction_legs` for this record
3. Build `systemComparison` from the 3 legs:
   ```python
   system_comparison = [
       {
           "system": "PSP",
           "icon": "CreditCard",
           "color": "blue",
           "amount": leg_psp.amount,        # "$12,450.00" or "-"
           "timestamp": leg_psp.timestamp,   # "2024-01-15 09:30:02" or "-"
           "status": leg_psp.status          # "Processed" or "Missing"
       },
       {
           "system": "Cashier",
           "icon": "Building2",
           "color": "green",
           "amount": leg_cashier.amount,
           "timestamp": leg_cashier.timestamp,
           "status": leg_cashier.status      # "Recorded" or "Not Found"
       },
       {
           "system": "ERP",
           "icon": "Database",
           "color": "purple",
           "amount": leg_erp.amount,
           "timestamp": leg_erp.timestamp,
           "status": leg_erp.status          # "Verified" or "Not Found"
       }
   ]
   ```
4. Build `fieldComparison` — compare Amount, Timestamp, Status across 3 systems:
   ```python
   field_comparison = [
       {
           "field": "Amount",
           "psp": leg_psp.amount,
           "cashier": leg_cashier.amount,
           "erp": leg_erp.amount,
           "variance": calculate_variance(leg_psp.amount, leg_cashier.amount, leg_erp.amount)
           # "$30.00" if different, null if all same, "N/A" if a system is missing
       },
       { "field": "Timestamp", ... },
       { "field": "Status", ... }
   ]
   ```
5. Build `discrepancy` from `discrepancies` table (null if matched):
   ```python
   discrepancy = {
       "type": "timing",
       "detectedIssues": ["PSP and ERP amounts differ"]
   }
   ```
6. Build `aiAnalysis` — see `../AI/README.md` for full spec. Phase 1: use `hardcoded_analysis.py`. Phase 2: use real AI calls.
   - Return `null` for matched records
   - Return full analysis for partial/unmatched/discrepancy records

---

### 4. `POST /api/reconciliation/{reconciliationId}/resolve`

**Purpose:** Mark a specific discrepancy as manually resolved.

**Request:**
```json
{
  "recordId": "rec_004",
  "resolution": "Confirmed duplicate — original is rec_001",
  "resolvedBy": "analyst@company.com"
}
```

**Response:**
```json
{
  "success": true,
  "recordId": "rec_004",
  "previousStatus": "discrepancy",
  "newStatus": "matched",
  "resolvedAt": "2025-01-15T14:30:00Z"
}
```

**How it works internally:**
1. Look up the `discrepancy` for this record
2. Update `discrepancies.resolved = true`, `resolved_at = now()`, `resolved_by = user`
3. Update `reconciliation_records.status` to `matched` (or keep `partial` if other discrepancies remain)
4. Recalculate summary stats on the parent `reconciliation_run`
5. Create audit event: actor = user, action = "Marked Resolved", target = transaction ref

---

### 5. `GET /api/reconciliation/{reconciliationId}/audit`

**Purpose:** Get the audit trail for a reconciliation run. Frontend renders this in the "Audit Trail" tab.

**Query parameters:**
| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `actorType` | string | `all` | Filter by actor: `system`, `user`, `ai` |
| `category` | string | `all` | Filter by category: `reconciliation`, `resolution`, `config`, `review`, `export` |
| `page` | int | 1 | Pagination page number |
| `limit` | int | 50 | Events per page |

**Response:** Array of `AuditEvent` objects. See [`sample_audit_trail.json`](./sample_audit_trail.json) for the full 18-event sample.

```typescript
interface AuditEvent {
  id: string;                // "AUD-001"
  timestamp: string;         // "2024-01-15 20:00:02"
  actor: string;             // "Reconciliation Engine" | "AI Agent v2.4.1" | "Sarah Chen"
  actorType: "system" | "user" | "ai";
  action: string;            // "Batch Started" | "Pattern Analysis" | "Viewed Details"
  target: string;            // "BATCH-2024-0115" | "TXN-2024-003"
  details: string;           // Human-readable description
  category: "reconciliation" | "resolution" | "config" | "review" | "export";
}
```

**How it works internally:**
1. Query `audit_events` table filtered by `reconciliation_id`
2. Apply optional filters (`actorType`, `category`)
3. Paginate and return

**When to create audit events (backend must do this automatically):**

| When | Actor | Action | Category |
|------|-------|--------|----------|
| Pipeline starts | Reconciliation Engine (system) | Batch Started | reconciliation |
| After Step 2+3 matching | AI Agent v2.4.1 (ai) | Pattern Analysis | reconciliation |
| Discrepancy found | AI Agent v2.4.1 (ai) | Anomaly Detected | reconciliation |
| Pipeline completes | Reconciliation Engine (system) | Batch Completed | reconciliation |
| AI auto-resolves | AI Agent v2.4.1 (ai) | Auto-Resolved | resolution |
| AI flags FX issue | AI Agent v2.4.1 (ai) | FX Rate Alert | reconciliation |
| End of batch | AI Agent v2.4.1 (ai) | Risk Assessment | reconciliation |
| User clicks row | User name (user) | Viewed Details | review |
| User adds note | User name (user) | Added Note | review |
| User resolves | User name (user) | Marked Resolved | resolution |
| User escalates | User name (user) | Escalated | review |
| User downloads | User name (user) | Downloaded Report | export |
| Retry sync | System Scheduler (system) | Retry Sync | reconciliation |
| Config change | Admin Config (system) | Threshold Updated | config |

---

### 6. `GET /api/reconciliation/{reconciliationId}/discrepancies`

**Purpose:** Get all discrepancies for a reconciliation run. Frontend renders this in the "Discrepancies" tab.

**Query parameters:**
| Param | Type | Default | Description |
|-------|------|---------|-------------|
| `type` | string | `all` | Filter: `missing`, `timing`, `amount-mismatch`, `duplicate`, `fx-rate`, `fee` |
| `severity` | string | `all` | Filter: `low`, `medium`, `high`, `critical` |
| `resolved` | boolean | `all` | Filter: `true` or `false` |
| `page` | int | 1 | Pagination page number |
| `limit` | int | 50 | Records per page |

**Response:** Array of `Discrepancy` objects. See [`sample_discrepancies.json`](./sample_discrepancies.json) for 11 example records.

```typescript
interface Discrepancy {
  id: string;                // "disc_001"
  reconciliationId: string;
  recordId: string;          // FK to reconciliation_records
  transactionRef: string;
  type: "missing" | "timing" | "amount-mismatch" | "duplicate" | "fx-rate" | "fee";
  severity: "low" | "medium" | "high" | "critical";
  description: string;       // Human-readable explanation
  variance: string;          // "$30.00" or "N/A" for missing
  pspValue: { amount: string; description: string; status: string; timestamp: string; fxRate?: number } | null;
  cashierValue: { amount: string; description: string; status: string; timestamp: string; fxRate?: number } | null;
  erpValue: { amount: string; description: string; status: string; timestamp: string; fxRate?: number } | null;
  suggestedResolution: string;
  resolved: boolean;
  resolvedAt: string | null;
  resolvedBy: string | null;
}
```

---

## Response Shapes

### `ReconciliationResult`

Top-level response returned by the run and get endpoints.

```typescript
interface ReconciliationResult {
  reconciliationId: string;
  runAt: string;                    // ISO 8601 timestamp
  pspUploadId: string;
  internalUploadId: string;
  erpUploadId: string;
  summary: {
    totalTransactions: number;      // Total unique transactions across all 3 systems
    matched: number;                // Fully matched across all 3 systems
    partial: number;                // Matched but with discrepancies (timing, amount, fee)
    unmatched: number;              // Present in one system but missing from others
    discrepancies: number;          // Total discrepancy count (including duplicates)
    matchRate: number;              // Percentage: (matched + partial) / total * 100
  };
  records: ReconciliationRecord[];
}
```

### `ReconciliationRecord`

Each record represents one transaction across the three systems.

```typescript
type DiscrepancySubType = "missing" | "timing" | "amount-mismatch" | "duplicate" | "fx-rate" | "fee";

interface ReconciliationRecord {
  id: string;                       // Unique record ID (e.g. "rec_001")
  transactionRef: string;           // The `reference` field used to match
  pspAmount: string;                // Gross amount from PSP (display string, e.g. "$12,450.00")
  cashierAmount: string;            // Total amount from Internal/Cashier
  erpAmount: string;                // Posted amount from ERP (NOTE: this is NET)
  matchScore: number;               // 0-100 confidence score
  status: "matched" | "partial" | "unmatched" | "discrepancy";
  matchType: "exact" | "unmatched" | "discrepancy";
  discrepancySubType?: DiscrepancySubType;
  timestamp: string;                // Transaction date (ISO 8601)
  legs: TransactionLeg[];           // Always 3 legs: PSP, Cashier, ERP
}

interface TransactionLeg {
  system: "PSP" | "Cashier" | "ERP";
  amount: string;          // "$12,450.00" or "-" if missing
  description: string;     // "Visa deposit processed by PSP"
  status: "Processed" | "Recorded" | "Verified" | "Missing";
  timestamp: string;       // "2024-01-15 09:30:02" or "-" if missing
}
```

**Important:** The frontend renders these fields directly. The field names and types above must match exactly.

---

## Matching Algorithm (Full Implementation)

Copy these functions into your `reconciliation_service.py`.

### Step 1: Duplicate Detection

```python
from collections import defaultdict

def detect_duplicates(transactions: list[dict], system: str) -> list[dict]:
    """
    Group transactions by (reference, grossAmount, transactionDate).
    If a group has more than one record, flag all but the first as duplicates.
    """
    groups = defaultdict(list)
    for txn in transactions:
        key = (txn["reference"], txn["grossAmount"], txn["transactionDate"])
        groups[key].append(txn)

    duplicates = []
    for key, group in groups.items():
        if len(group) > 1:
            for dup in group[1:]:
                dup["is_duplicate"] = True
                duplicates.append(dup)

    return duplicates
```

### Step 2: Reference Match

```python
def reference_match(psp: list, internal: list, erp: list) -> dict:
    """
    Build lookup dicts by `reference` field, then match across all 3 systems.
    Returns dict of { reference: { psp: txn, internal: txn, erp: txn } }
    """
    psp_by_ref = {t["reference"]: t for t in psp if not t.get("is_duplicate")}
    int_by_ref = {t["reference"]: t for t in internal if not t.get("is_duplicate")}
    erp_by_ref = {t["reference"]: t for t in erp if not t.get("is_duplicate")}

    all_refs = set(psp_by_ref) | set(int_by_ref) | set(erp_by_ref)

    matched = {}
    for ref in all_refs:
        matched[ref] = {
            "psp": psp_by_ref.get(ref),
            "internal": int_by_ref.get(ref),
            "erp": erp_by_ref.get(ref),
        }
    return matched
```

### Step 3: Fuzzy Fallback

```python
from datetime import datetime

AMOUNT_TOLERANCE = 0.01     # 1 cent tolerance for rounding
DATE_TOLERANCE_DAYS = 5     # 5-day window (test data shows 4-10 day gaps)

def fuzzy_match(unmatched_txn: dict, candidates: list[dict]) -> dict | None:
    """
    For a transaction that didn't match by reference, try to find a match
    using (amount ± tolerance) + (date ± 5 days) + client_id.
    """
    for candidate in candidates:
        amount_match = abs(unmatched_txn["grossAmount"] - candidate["grossAmount"]) <= AMOUNT_TOLERANCE

        try:
            d1 = datetime.fromisoformat(unmatched_txn["transactionDate"][:10])
            d2 = datetime.fromisoformat(candidate["transactionDate"][:10])
            date_match = abs((d1 - d2).days) <= DATE_TOLERANCE_DAYS
        except (ValueError, KeyError):
            date_match = False

        client_match = unmatched_txn.get("clientId") == candidate.get("clientId")

        if amount_match and date_match and client_match:
            return candidate

    return None
```

### Step 4: Three-Way Verify

```python
def verify_triplet(psp_txn: dict | None, int_txn: dict | None, erp_txn: dict | None) -> list[dict]:
    """
    For a matched triplet, verify consistency and generate discrepancies.

    CRITICAL AMOUNT RULES:
    - PSP `grossAmount` = GROSS (before fees)
    - Internal `grossAmount` = GROSS (total_amount from source)
    - ERP `grossAmount` = NET (posted_amount from source — already fee-deducted)
    - To compare: PSP.grossAmount should ≈ Internal.grossAmount
    - To compare: PSP.netAmount should ≈ ERP.grossAmount (ERP stores NET as posted_amount)
    """
    discrepancies = []

    # Amount mismatch: compare gross amounts (PSP vs Internal)
    if psp_txn and int_txn:
        if abs(psp_txn["grossAmount"] - int_txn["grossAmount"]) > AMOUNT_TOLERANCE:
            discrepancies.append({
                "type": "amount-mismatch",
                "severity": "high",
                "description": f"PSP gross ({psp_txn['grossAmount']}) != Internal gross ({int_txn['grossAmount']})",
                "psp_value": psp_txn["grossAmount"],
                "internal_value": int_txn["grossAmount"],
            })

    # Amount mismatch: compare net amounts (PSP net vs ERP posted)
    if psp_txn and erp_txn:
        psp_net = psp_txn.get("netAmount", psp_txn["grossAmount"])
        if abs(psp_net - erp_txn["grossAmount"]) > AMOUNT_TOLERANCE:
            discrepancies.append({
                "type": "amount-mismatch",
                "severity": "high",
                "description": f"PSP net ({psp_net}) != ERP posted ({erp_txn['grossAmount']})",
                "psp_value": psp_net,
                "erp_value": erp_txn["grossAmount"],
            })

    # Fee discrepancy: compare fee fields
    if psp_txn and int_txn:
        psp_fee = psp_txn.get("fee", 0)
        int_fee = int_txn.get("fee", 0)
        if abs(psp_fee - int_fee) > AMOUNT_TOLERANCE:
            discrepancies.append({
                "type": "fee",
                "severity": "medium",
                "description": f"Fee mismatch: PSP ({psp_fee}) vs Internal ({int_fee})",
            })

    # FX rate discrepancy
    if psp_txn and erp_txn:
        psp_fx = psp_txn.get("fxRate")
        erp_fx = erp_txn.get("fxRate")
        if psp_fx and erp_fx and psp_fx != erp_fx:
            diff_pct = abs(psp_fx - erp_fx) / max(psp_fx, 0.0001) * 100
            discrepancies.append({
                "type": "fx-rate",
                "severity": "high" if diff_pct > 1.0 else "medium",
                "description": f"FX rate: PSP ({psp_fx}) vs ERP ({erp_fx}), {diff_pct:.2f}% diff",
            })

    # Timing discrepancy: check date gaps
    if psp_txn and erp_txn:
        try:
            d1 = datetime.fromisoformat(psp_txn["transactionDate"][:10])
            d2 = datetime.fromisoformat(erp_txn["transactionDate"][:10])
            gap = abs((d1 - d2).days)
            if gap > DATE_TOLERANCE_DAYS:
                discrepancies.append({
                    "type": "timing",
                    "severity": "medium",
                    "description": f"Date gap of {gap} days between PSP and ERP",
                })
        except (ValueError, KeyError):
            pass

    # Missing: check if any system is absent
    systems = {"PSP": psp_txn, "Cashier": int_txn, "ERP": erp_txn}
    missing = [name for name, txn in systems.items() if txn is None]
    if missing:
        discrepancies.append({
            "type": "missing",
            "severity": "critical",
            "description": f"Transaction missing from: {', '.join(missing)}",
        })

    return discrepancies
```

### Step 5: Generate Report

```python
import uuid

def generate_report(matched_triplets: dict, duplicates: list) -> dict:
    """Compile all results into the final ReconciliationResult."""
    records = []
    summary = {"matched": 0, "partial": 0, "unmatched": 0, "discrepancies": 0}

    for ref, triplet in matched_triplets.items():
        psp = triplet["psp"]
        internal = triplet["internal"]
        erp = triplet["erp"]

        # Run verification
        disc = verify_triplet(psp, internal, erp)

        # Determine status
        all_present = all([psp, internal, erp])
        if all_present and len(disc) == 0:
            status = "matched"
            match_type = "exact"
            match_score = 100
            summary["matched"] += 1
        elif all_present and len(disc) > 0:
            status = "partial"
            match_type = "discrepancy"
            match_score = max(60, 100 - len(disc) * 10)
            summary["partial"] += 1
            summary["discrepancies"] += len(disc)
        else:
            status = "unmatched"
            match_type = "unmatched"
            match_score = 0
            summary["unmatched"] += 1
            summary["discrepancies"] += 1

        # Build 3 legs (always 3 — even for missing systems)
        legs = [
            {
                "system": "PSP",
                "amount": f"${psp['grossAmount']:,.2f}" if psp else "-",
                "description": psp.get("description", "PSP transaction") if psp else "-",
                "status": "Processed" if psp else "Missing",
                "timestamp": psp["transactionDate"] if psp else "-",
            },
            {
                "system": "Cashier",
                "amount": f"${internal['grossAmount']:,.2f}" if internal else "-",
                "description": internal.get("description", "Cashier entry") if internal else "-",
                "status": "Recorded" if internal else "Missing",
                "timestamp": internal["transactionDate"] if internal else "-",
            },
            {
                "system": "ERP",
                "amount": f"${erp['grossAmount']:,.2f}" if erp else "-",
                "description": erp.get("description", "ERP posting") if erp else "-",
                "status": "Verified" if erp else "Missing",
                "timestamp": erp["transactionDate"] if erp else "-",
            },
        ]

        records.append({
            "id": f"rec_{str(uuid.uuid4())[:8]}",
            "transactionRef": ref,
            "pspAmount": legs[0]["amount"],
            "cashierAmount": legs[1]["amount"],
            "erpAmount": legs[2]["amount"],
            "matchScore": match_score,
            "status": status,
            "matchType": match_type,
            "discrepancySubType": disc[0]["type"] if disc else None,
            "timestamp": (psp or internal or erp)["transactionDate"],
            "legs": legs,
        })

    # Add duplicate records
    for dup in duplicates:
        records.append({
            "id": f"rec_{str(uuid.uuid4())[:8]}",
            "transactionRef": dup["reference"],
            "pspAmount": f"${dup['grossAmount']:,.2f}" if dup.get("_system") == "psp" else "-",
            "cashierAmount": f"${dup['grossAmount']:,.2f}" if dup.get("_system") == "internal" else "-",
            "erpAmount": f"${dup['grossAmount']:,.2f}" if dup.get("_system") == "erp" else "-",
            "matchScore": 0,
            "status": "discrepancy",
            "matchType": "discrepancy",
            "discrepancySubType": "duplicate",
            "timestamp": dup["transactionDate"],
            "legs": [],
        })
        summary["discrepancies"] += 1

    total = summary["matched"] + summary["partial"] + summary["unmatched"] + len(duplicates)
    match_rate = ((summary["matched"] + summary["partial"]) / total * 100) if total > 0 else 0

    return {
        "summary": {
            "totalTransactions": total,
            "matched": summary["matched"],
            "partial": summary["partial"],
            "unmatched": summary["unmatched"],
            "discrepancies": summary["discrepancies"],
            "matchRate": round(match_rate, 1),
        },
        "records": records,
    }
```

---

## Amount Comparison Rules

This is the most critical part of the matching engine. Each system stores amounts differently:

| System | Source Column | Standardized Field | What It Represents |
|--------|--------------|-------------------|-------------------|
| PSP | `gross_amount` | `grossAmount` | GROSS (before fees) |
| PSP | `net_payout` | `netAmount` | NET (after fees) |
| PSP | `processing_fee` | `fee` | Fee deducted |
| Internal | `total_amount` | `grossAmount` | GROSS (before fees) |
| Internal | `net_amount` | `netAmount` | NET (after fees) |
| Internal | `fee_amount` | `fee` | Fee deducted |
| ERP | `posted_amount` | `grossAmount` | **NET** (already fee-deducted!) |
| ERP | `net_amount` | `netAmount` | NET (same as posted) |
| ERP | `fee_amount` | `fee` | Fee (for reference only) |

**Comparison logic:**
- `PSP.grossAmount` should equal `Internal.grossAmount` (both GROSS)
- `PSP.netAmount` should equal `ERP.grossAmount` (both NET — ERP posts the net amount)
- `PSP.grossAmount - PSP.fee` should equal `PSP.netAmount` (internal consistency)

> **Why?** The ERP system records the `posted_amount` as the actual settlement amount (net of fees). The PSP and Internal systems track both gross and net. Comparing PSP gross to ERP posted would always show a discrepancy equal to the fee.

---

## Discrepancy Types (6 Total)

| Type | Severity Range | When Triggered | Example |
|------|---------------|----------------|---------|
| `missing` | critical | Record exists in one system but not others | Cashier offline during PSP transaction |
| `amount-mismatch` | low → high | Amounts don't match across systems | Cashier recorded $5,500 instead of $5,200 |
| `fee` | low → medium | Fee amounts differ between systems | ERP added $0.75 gateway fee |
| `timing` | medium | Date gap exceeds 5-day tolerance | ERP posted next-day settlement value |
| `fx-rate` | medium → high | FX rates differ between systems | PSP used spot rate, ERP used closing rate |
| `duplicate` | medium | Same transaction appears multiple times | Same (reference + amount + date) in one system |

**Severity rules:**
- `critical` — always for missing records (human must verify)
- `high` — amount mismatch > $100, FX variance > 1%
- `medium` — amount mismatch $10-$100, FX variance 0.5-1%, timing > 5 days
- `low` — rounding errors < $1, small fee differences

---

## Date Tolerance

Based on real test data analysis (`data-by-faiz/`):
- PSP `transaction_date` to ERP `posting_date` gap: **4-10 days** typical
- PSP `transaction_date` to Internal `booking_date` gap: **0-2 days** typical
- Default tolerance: **5 days** for flagging timing discrepancies

---

## CSV Column Headers Per System

For reference when building field mappings (already handled by upload API):

**PSP columns:** `psp_txn_id`, `merchant_ref`, `gross_amount`, `currency`, `processing_fee`, `net_payout`, `transaction_date`, `settlement_date`, `client_id`, `client_name`, `description`, `status`, `payment_method`, `settlement_bank`, `bank_country`, `fx_rate`

**Internal (Cashier) columns:** `internal_id`, `ext_reference`, `total_amount`, `currency`, `fee_amount`, `net_amount`, `booking_date`, `value_date`, `client_id`, `client_name`, `description`, `status`, `payment_method`, `settlement_bank`, `bank_country`, `fx_rate`

**ERP columns:** `erp_doc_number`, `reference`, `posted_amount`, `currency`, `fee_amount`, `net_amount`, `posting_date`, `clearing_date`, `client_id`, `client_name`, `description`, `status`, `payment_method`, `settlement_bank`, `bank_country`, `fx_rate`

**Reference field mapping** (used in Step 2):
| System | Source Column | Standardized Field |
|--------|-------------|-------------------|
| PSP | `merchant_ref` | `reference` |
| Internal | `ext_reference` | `reference` |
| ERP | `reference` | `reference` |

---

## Standardized Transaction Fields (16 Total)

All transactions are normalized to these fields by the upload API:

| # | Field | Type | Description |
|---|-------|------|-------------|
| 1 | `systemId` | string | Original system ID (psp_txn_id / internal_id / erp_doc_number) |
| 2 | `reference` | string | **Primary match key** across all 3 systems |
| 3 | `grossAmount` | number | Gross/total amount (NOTE: ERP stores NET here) |
| 4 | `netAmount` | number | Net amount after fees |
| 5 | `fee` | number | Processing/fee amount |
| 6 | `currency` | string | Currency code (e.g. USD) |
| 7 | `transactionDate` | string | Transaction/booking/posting date (ISO 8601) |
| 8 | `settlementDate` | string | Settlement/value/clearing date (ISO 8601) |
| 9 | `clientId` | string | Client identifier |
| 10 | `clientName` | string | Client display name |
| 11 | `description` | string | Transaction description |
| 12 | `status` | string | Processing status |
| 13 | `paymentMethod` | string | Payment method used |
| 14 | `settlementBank` | string | Bank used for settlement |
| 15 | `bankCountry` | string | Country of settlement bank |
| 16 | `fxRate` | number/null | Foreign exchange rate (if applicable) |

---

## Implementation Steps (Python / FastAPI)

### Phase 1: Build the pipeline + all 6 endpoints

```
server/
├── main.py                              # FastAPI app + CORS
├── routers/
│   └── reconciliation.py                # 6 API endpoints
├── services/
│   ├── reconciliation_service.py        # 5-step pipeline (copy code from above)
│   ├── hardcoded_analysis.py            # Phase 1 AI analysis (copy from AI/README.md)
│   └── audit_service.py                 # Creates audit events
├── models/
│   └── reconciliation.py                # Pydantic models for all response shapes
└── store/
    └── reconciliation_store.py          # In-memory dict (or PostgreSQL later)
```

### Step-by-step:

1. **Create Pydantic models** — `models/reconciliation.py`
   - `ReconciliationRecord`, `TransactionLeg`, `ReconciliationResult`, `Discrepancy`, `AuditEvent`
   - These must match the TypeScript interfaces above exactly

2. **Create the pipeline service** — `services/reconciliation_service.py`
   - Copy the 5 functions from the [Matching Algorithm](#matching-algorithm-full-implementation) section above
   - Add a main `run_reconciliation(psp_upload_id, int_upload_id, erp_upload_id)` function that chains them

3. **Create the hardcoded AI analysis** — `services/hardcoded_analysis.py`
   - Copy from `../AI/README.md` — this returns the same AI data the frontend already renders
   - Wire into the record detail endpoint

4. **Create the audit service** — `services/audit_service.py`
   - Function to create audit events and store them
   - Called by the pipeline at each stage (batch start, analysis, anomaly, complete)

5. **Create the store** — `store/reconciliation_store.py`
   - Phase 1: in-memory dict (same pattern as upload functionality)
   - Phase 2: PostgreSQL using `database_schema.sql`
   ```python
   # In-memory store
   runs: dict[str, dict] = {}       # reconciliation_id -> ReconciliationResult
   records: dict[str, dict] = {}    # record_id -> ReconciliationRecord (with legs)
   discrepancies: dict[str, list] = {}  # reconciliation_id -> [Discrepancy]
   audit_events: dict[str, list] = {}   # reconciliation_id -> [AuditEvent]
   ```

6. **Create the router** — `routers/reconciliation.py`
   - Wire up all 6 endpoints
   - POST run: load uploads → run pipeline → store result → create audit events → return
   - GET result: load from store → apply filters → paginate → return
   - GET record detail: load record + legs → build systemComparison + fieldComparison → attach aiAnalysis → return
   - POST resolve: update discrepancy → update record status → recalculate summary → create audit event → return
   - GET audit: load events → filter → paginate → return
   - GET discrepancies: load discrepancies → filter → paginate → return

7. **Test with frontend**
   - Upload 3 files via upload API (PSP, Cashier, ERP)
   - Hit `POST /api/reconciliation/run` with the 3 upload IDs
   - Check: summary card shows correct numbers
   - Check: records table shows all records with correct status badges
   - Check: click a row → modal shows systemComparison + fieldComparison + aiAnalysis
   - Check: Audit Trail tab shows events
   - Check: Discrepancies tab shows all discrepancies

### Without a database (Phase 1):

```python
# Same pattern as upload functionality — store everything in Python dicts
# Mapping:
#   reconciliation_runs   → runs: dict[str, dict]
#   reconciliation_records → stored inside runs[id]["records"]
#   transaction_legs      → stored inside each record["legs"]
#   discrepancies         → discrepancies: dict[str, list]
#   audit_events          → audit_events: dict[str, list]
```

---

## Database Schema (Phase 2)

The full PostgreSQL schema is defined in [`database_schema.sql`](./database_schema.sql). It contains **12 tables** with ENUMs, indexes, foreign keys, and seed data.

### Entity Relationship Diagram

```
  users ──────────────< uploads
    │                     │
    │                     ├── field_mappings
    │                     │
    │                     └──< transactions
    │
    ├──< audit_events
    │
    ├──< notification_preferences
    │
    └──< notifications

  reconciliation_runs ──< reconciliation_records ──< transaction_legs
         │                       │
         │                       └──< discrepancies
         │
         └── references 3 uploads (psp, cashier, erp)

  matching_config (singleton / global settings)
```

### Table Summary

| # | Table | Description |
|---|-------|-------------|
| 1 | `users` | Actors: Sarah Chen, James Lee, Reconciliation Engine, AI Agent |
| 2 | `uploads` | File upload records per stakeholder |
| 3 | `field_mappings` | Column-to-field mappings per upload |
| 4 | `transactions` | Normalized transaction records (16 fields) |
| 5 | `reconciliation_runs` | Each run referencing 3 uploads + summary stats |
| 6 | `reconciliation_records` | Per-transaction match result = frontend `ReconciliationRecord` |
| 7 | `transaction_legs` | 3 rows per record: PSP, Cashier, ERP leg |
| 8 | `discrepancies` | Detailed discrepancy with JSONB per-system values |
| 9 | `audit_events` | Full audit trail (system/user/AI events) |
| 10 | `notifications` | User-facing notifications |
| 11 | `matching_config` | Global settings (fuzzy threshold, tolerances) |
| 12 | `notification_preferences` | Per-user notification channel settings |

### ENUMs

- `actor_type`: `system`, `user`, `ai`
- `record_status`: `matched`, `partial`, `unmatched`, `discrepancy`
- `match_type`: `exact`, `unmatched`, `discrepancy`
- `discrepancy_sub_type`: `missing`, `timing`, `amount-mismatch`, `duplicate`, `fx-rate`, `fee`
- `discrepancy_severity`: `low`, `medium`, `high`, `critical`
- `leg_status`: `Processed`, `Recorded`, `Verified`, `Missing`
- `audit_category`: `reconciliation`, `resolution`, `config`, `review`, `export`
- `stakeholder_system`: `psp`, `cashier`, `erp`

---

## Test Data Reference

The `data-by-faiz/` directory contains test scenarios:

| Scenario | Key Characteristics |
|----------|-------------------|
| Root CSVs | Full 16-column format, ~50 transactions each |
| Scenario 1 | Includes duplicate (INT-0007-DUP), 1-2 missing records |
| Scenario 2 | Minimal columns in Internal/ERP (only 5 fields each) |
| Scenario 3 | Additional edge cases |

---

## Sample Data Files

| File | Description | Records |
|------|-------------|---------|
| [`sample_reconciliation_result.json`](./sample_reconciliation_result.json) | Full reconciliation result with 15 transactions x 3 legs | 15 records, 45 legs |
| [`sample_discrepancies.json`](./sample_discrepancies.json) | All discrepancies across 5 types + severity levels | 11 records |
| [`sample_record_detail.json`](./sample_record_detail.json) | Individual record detail (matched, partial, unmatched) | 3 examples |
| [`sample_audit_trail.json`](./sample_audit_trail.json) | Complete audit trail for a reconciliation run | 18 events |
| [`database_schema.sql`](./database_schema.sql) | PostgreSQL CREATE TABLE statements | 12 tables |

### Discrepancy Type Coverage in Sample Data

| Type | Count | Severity Levels | Records |
|------|-------|----------------|---------|
| `missing` | 3 | critical | disc_003, disc_005, disc_010 |
| `amount-mismatch` | 3 | low, high, medium | disc_001, disc_002, disc_011 |
| `fee` | 2 | low | disc_004, disc_008 |
| `timing` | 1 | medium | disc_007 |
| `fx-rate` | 2 | medium, high | disc_006, disc_009 |

> **Note:** The `duplicate` type is not in the current sample because no duplicates were detected. The type is fully supported in the schema and pipeline code.

---

## Summary: What Backend Developer Needs to Build

| What | Priority | Effort | Notes |
|------|----------|--------|-------|
| 5-step pipeline | **P0** | Medium | Core matching logic — code is above, just wire it up |
| `POST /api/reconciliation/run` | **P0** | Medium | Calls pipeline + stores result + creates audit events |
| `GET /api/reconciliation/{id}` | **P0** | Easy | Fetch stored result with pagination |
| `GET /api/reconciliation/{id}/records/{recordId}` | **P0** | Medium | Build systemComparison + fieldComparison + aiAnalysis |
| `GET /api/reconciliation/{id}/discrepancies` | **P1** | Easy | Filter + paginate stored discrepancies |
| `GET /api/reconciliation/{id}/audit` | **P1** | Easy | Filter + paginate stored audit events |
| `POST /api/reconciliation/{id}/resolve` | **P1** | Easy | Update status + create audit event |
| Hardcoded AI analysis | **P0** | Easy | Copy `hardcoded_analysis.py` from AI/README.md |
| In-memory store | **P0** | Easy | Python dicts — same as upload functionality |
| PostgreSQL migration | **P2** | Medium | Run `database_schema.sql` when ready |
| Real AI integration | **P2** | Medium | See AI/README.md for full spec |
