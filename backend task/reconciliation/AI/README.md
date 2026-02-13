# AI — Reconciliation

# TLDR:

Reconciliation engine kita pakai 5-step pipeline (reference match → fuzzy → verify → report). Tu semua rule-based, tak perlu AI pun.

AI masuk kat **2 tempat je**:

1. **AI Matching (Step 3.5)** — Bila transaction tak jumpa match guna reference dan fuzzy, kita bagi AI list candidates, dia pilih yang paling likely sama. Macam tinder tapi untuk transaction.

2. **AI Discrepancy Analysis (Step 4.5)** — Bila dah jumpa discrepancy (amount tak sama, missing record, FX rate lain), AI analyze root cause dan suggest resolution. Frontend dah siap render analysis ni dalam modal dialog.

**Phase 1 (Hackathon):** Buat pipeline tanpa AI dulu. Frontend dah hardcode AI analysis, so backend just return the same shape. Takde AI call pun takpe — guna hardcoded responses.

**Phase 2:** Ganti hardcoded responses dengan real AI calls (OpenAI GPT-4o). Tambah AI matching step untuk unmatched transactions.

Please refer this link: [Klik sini](https://deriv-hackathon-tideline.vercel.app/reconciliation)

      14 -┌─────────────────────────────────────────────────────────────────────┐                                                                                                                                                      
      15 -│                     RECONCILIATION PIPELINE                        │                                                                                                                                                       
      16 -├─────────────────────────────────────────────────────────────────────┤                                                                                                                                                      
      17 -│                                                                     │                                                                                                                                                      
      18 -│  Step 1: DUPLICATE DETECTION                                        │                                                                                                                                                      
      19 -│  ┌──────────────────────────────────┐                               │                                                                                                                                                      
      20 -│  │ Group by (reference + amount +   │──→ Flag duplicates            │                                                                                                                                                      
      21 -│  │ date) within each system         │    (e.g. INT-0007-DUP)       │                                                                                                                                                       
      22 -│  └──────────────────────────────────┘                               │                                                                                                                                                      
      23 -│                    │                                                 │                                                                                                                                                     
      24 -│                    ▼                                                 │                                                                                                                                                     
      25 -│  Step 2: REFERENCE MATCH                                            │                                                                                                                                                      
      26 -│  ┌──────────────────────────────────┐                               │                                                                                                                                                      
      27 -│  │ Match PSP ↔ Internal ↔ ERP      │──→ ~90% matched               │                                                                                                                                                       
      28 -│  │ by `reference` field             │                               │                                                                                                                                                      
      29 -│  └──────────────────────────────────┘                               │                                                                                                                                                      
      30 -│                    │                                                 │                                                                                                                                                     
      31 -│                    ▼                                                 │                                                                                                                                                     
      32 -│  Step 3: FUZZY FALLBACK                                             │                                                                                                                                                      
      33 -│  ┌──────────────────────────────────┐                               │                                                                                                                                                      
      34 -│  │ For unmatched: try matching by   │──→ Catches remaining ~8%      │                                                                                                                                                      
      35 -│  │ (amount ± tolerance) +           │                               │                                                                                                                                                      
      36 -│  │ (date ± 5 days) + client_id      │                               │                                                                                                                                                      
      37 -│  └──────────────────────────────────┘                               │                                                                                                                                                      
      38 -│                    │                                                 │                                                                                                                                                     
      39 -│                    ▼                                                 │                                                                                                                                                     
      40 -│  Step 4: THREE-WAY VERIFY                                           │                                                                                                                                                      
      41 -│  ┌──────────────────────────────────┐                               │                                                                                                                                                      
      42 -│  │ For all matched triplets, check: │──→ Generate discrepancy       │                                                                                                                                                      
      43 -│  │ - Amount consistency             │    records for mismatches     │                                                                                                                                                      
      44 -│  │ - Date consistency (±5 days)     │                               │                                                                                                                                                      
      45 -│  │ - Fee consistency                │                               │                                                                                                                                                      
      46 -│  └──────────────────────────────────┘                               │                                                                                                                                                      
      47 -│                    │                                                 │                                                                                                                                                     
      48 -│                    ▼                                                 │                                                                                                                                                     
      49 -│  Step 5: GENERATE REPORT                                            │                                                                                                                                                      
      50 -│  ┌──────────────────────────────────┐                               │                                                                                                                                                      
      51 -│  │ Compile summary stats +          │──→ Return ReconciliationResult│                                                                                                                                                      
      52 -│  │ record-level details             │                               │                                                                                                                                                      
      53 -│  └──────────────────────────────────┘                               │                                                                                                                                                      
      54 -│                                                                     │     

---

## The Problem

After the reconciliation pipeline runs, we get 3 types of results that need intelligence:

| Problem | What Happens Today (Phase 1) | What AI Solves (Phase 2) |
|---------|------------------------------|--------------------------|
| **Unmatched transactions** | Stays unmatched forever | AI finds the best match from candidates |
| **Discrepancies flagged** | Analyst manually investigates each one | AI explains root cause + suggests resolution |
| **Record detail modal** | Frontend shows hardcoded AI analysis text | Backend returns real AI-generated analysis |

The frontend **already renders** all the AI features. Click any non-matched row in the reconciliation table — you'll see AI root cause analysis, confidence scores, timeline, and recommendations. Right now it's all fake/hardcoded. The backend needs to make it real.

---

## Where AI Fits in the Pipeline

```
RECONCILIATION PIPELINE (5 steps from API README)
    |
Step 1: Duplicate Detection ── rule-based
Step 2: Reference Match ────── rule-based (~90% matched)
Step 3: Fuzzy Fallback ──────── rule-based (~8% more matched)
    |
    |─── ~2% still UNMATCHED after Steps 2 + 3
    |
    v
Step 3.5: AI MATCHING (Phase 2) ◄──── NEW — AI picks best match from candidates
    |
    v
Step 4: Three-Way Verify ──── rule-based (generates discrepancies)
    |
    |─── Discrepancies found (amount, timing, FX, fee, missing, duplicate)
    |
    v
Step 4.5: AI DISCREPANCY ANALYSIS (Phase 2) ◄──── NEW — AI explains root cause
    |
    v
Step 5: Generate Report ──── compile everything into ReconciliationResult
```

**Phase 1 builds Steps 1-5 (no AI). Phase 2 adds Steps 3.5 and 4.5.**

---

## AI Feature 1: Smart Transaction Matching (Step 3.5)

### What It Does

When a transaction from PSP can't be matched to Internal/ERP by reference OR fuzzy logic, we ask AI to pick the best match from a shortlist of candidates.

### When It Runs

Only for transactions that are still `unmatched` after Step 3 (fuzzy). This is ~2-5% of transactions.

### Model: OpenAI GPT-4o

- **Model ID:** `gpt-4o`
- **SDK:** `openai` (official Python SDK)
- **API Key:** Set as environment variable `OPENAI_API_KEY`
- **Cost:** ~$0.01 per matching call
- **Latency:** ~1-2 seconds per call
- **Only called for genuinely unmatched transactions** — so ~5 calls per 100 transactions

### How It Works

```
Unmatched PSP transaction (no reference match, no fuzzy match)
    |
    v
1. Find top 5 candidates from Internal/ERP
   (by amount proximity + date proximity + same client)
    |
    v
2. Send to GPT-4o: "Here's the unmatched txn + 5 candidates. Which one matches?"
    |
    v
3. GPT-4o returns: { bestMatch: "Candidate A", confidence: 0.87, reasoning: "..." }
    |
    |--- confidence >= 0.7 → Treat as matched (but flag for review)
    |--- confidence < 0.7  → Stay unmatched
    |
    v
4. Continue to Step 4 (verify the matched triplet)
```

### Implementation

**File: `server/services/ai_matcher.py`**

```python
import json
import os
from openai import OpenAI

client = OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))

SYSTEM_PROMPT = """You are a financial reconciliation engine. You match payment transactions
across PSP, Cashier, and ERP systems.

You will receive:
1. An unmatched transaction from one system
2. A list of 3-5 candidate matches from other systems

Your job: determine which candidate (if any) is the same underlying transaction.

Assessment criteria:
- Amount similarity: exact match, rounding difference (<$1), or FX conversion
- Date proximity: same day = strong, within 5 days = acceptable, >5 days = weak
- Client match: same client_id is strong evidence
- Description overlap: shared keywords, invoice numbers, payment references
- Payment method match: same method is supporting evidence

Rules:
- Confidence 0.90-1.00: Very likely the same transaction
- Confidence 0.70-0.89: Probably the same, but needs human review
- Confidence 0.50-0.69: Ambiguous — don't match
- Confidence < 0.50: Not a match

Return ONLY a JSON object. No markdown, no explanation outside JSON.

Response format:
{
  "bestMatchIndex": 0,        // index of best candidate, or -1 if no match
  "confidence": 0.87,         // 0.0 to 1.0
  "reasoning": "Same client (CLI-042), exact amount (1500.00), 1-day date gap consistent with batch processing.",
  "matchType": "ai_match"     // always "ai_match"
}"""


def find_candidates(unmatched_txn: dict, pool: list[dict], limit: int = 5) -> list[dict]:
    """
    Find top N candidate matches from the other system's transaction pool.
    Pre-filter by: amount within 10% + date within 10 days + same currency.
    Sort by combined amount + date proximity score.
    """
    candidates = []
    for txn in pool:
        # Basic pre-filters
        if txn.get("currency") != unmatched_txn.get("currency"):
            continue

        amount_diff = abs(txn["grossAmount"] - unmatched_txn["grossAmount"])
        amount_pct = amount_diff / max(unmatched_txn["grossAmount"], 0.01)
        if amount_pct > 0.10:  # skip if amount differs by more than 10%
            continue

        # Date proximity (days)
        from datetime import datetime
        try:
            d1 = datetime.fromisoformat(unmatched_txn["transactionDate"][:10])
            d2 = datetime.fromisoformat(txn["transactionDate"][:10])
            date_gap = abs((d1 - d2).days)
        except (ValueError, KeyError):
            date_gap = 999

        if date_gap > 10:
            continue

        # Score: lower = better
        score = amount_pct * 100 + date_gap
        if txn.get("clientId") == unmatched_txn.get("clientId"):
            score -= 50  # bonus for same client

        candidates.append({"txn": txn, "score": score})

    candidates.sort(key=lambda x: x["score"])
    return [c["txn"] for c in candidates[:limit]]


async def ai_match_transaction(
    unmatched_txn: dict,
    candidates: list[dict],
) -> dict:
    """
    Call GPT-4o to match an unmatched transaction against candidates.
    Returns: { bestMatchIndex, confidence, reasoning, matchType }
    """
    user_prompt = f"""UNMATCHED TRANSACTION:
{json.dumps(unmatched_txn, indent=2, default=str)}

CANDIDATE MATCHES (indexed 0 to {len(candidates) - 1}):
{json.dumps([{"index": i, **c} for i, c in enumerate(candidates)], indent=2, default=str)}

Which candidate is the best match? Return JSON only."""

    response = client.chat.completions.create(
        model="gpt-4o",
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
        response_format={"type": "json_object"},
        max_tokens=256,
        temperature=0,
    )

    text = response.choices[0].message.content.strip()
    result = json.loads(text)

    # Validate
    if result.get("bestMatchIndex", -1) >= len(candidates):
        result["bestMatchIndex"] = -1
        result["confidence"] = 0

    return result
```

### Wiring It Into the Pipeline

```python
# In reconciliation_service.py — after Step 3 (fuzzy), before Step 4 (verify)

from server.services.ai_matcher import find_candidates, ai_match_transaction

async def step_3_5_ai_matching(unmatched_refs: list[str], matched_triplets: dict,
                                psp_pool: list, internal_pool: list, erp_pool: list):
    """
    Phase 2: For remaining unmatched transactions, try AI matching.
    Only runs for transactions that failed both reference and fuzzy matching.
    """
    for ref in unmatched_refs:
        triplet = matched_triplets[ref]

        # Find which system is missing
        if triplet["psp"] and not triplet["internal"]:
            candidates = find_candidates(triplet["psp"], internal_pool)
            if candidates:
                result = await ai_match_transaction(triplet["psp"], candidates)
                if result["confidence"] >= 0.7:
                    triplet["internal"] = candidates[result["bestMatchIndex"]]
                    triplet["_ai_matched"] = True

        # Similar logic for missing ERP...
```

---

## AI Feature 2: Discrepancy Analysis (Step 4.5)

### What It Does

After the pipeline finds discrepancies (Step 4), AI analyzes each one and returns:
- **Root cause** — why this discrepancy happened
- **Confidence score** — how sure is the AI
- **Recommendation** — auto-resolve, assisted review, or manual
- **Timeline** — step-by-step event flow with AI annotations
- **Agentic insights** — pattern recognition, historical success rate, anomaly detection

### This Is What the Frontend Already Renders

Go to the [Reconciliation page](https://deriv-hackathon-tideline.vercel.app/reconciliation), click any non-matched row. You'll see:

1. **"AI-Powered Discrepancy Analysis"** card — root cause + confidence %
2. **"Intelligent Recommendations"** — green/amber/red banner based on score
3. **"AI-Generated Timeline"** — collapsible event flow (for scores 70-89)
4. **"Agentic AI Insights"** — 3 insight cards (pattern, success rate, anomaly)

All of this is hardcoded in `ReconciliationTable.tsx` lines 561-663. The backend needs to return data in the same shape.

### Phase 1: Return Hardcoded Responses (No AI Call Needed)

For the hackathon, **don't call OpenAI**. Just return the same hardcoded analysis the frontend uses. This way the modal works correctly without AI cost.

**File: `server/services/hardcoded_analysis.py`**

```python
"""
Phase 1: Hardcoded AI analysis responses.
These match exactly what the frontend renders in ReconciliationTable.tsx lines 586-592.
Phase 2 replaces this with real GPT-4o calls.
"""

HARDCODED_ANALYSIS = {
    "amount-mismatch": {
        "rootCause": {
            "primaryCause": "Amount mismatch — cashier system rounding or manual entry error",
            "confidence": 87,
            "confidenceLabel": "warning",
            "historicalPatternCount": 43,
            "historicalNote": "Similar discrepancies found in 43 transactions this month"
        },
    },
    "timing": {
        "rootCause": {
            "primaryCause": "Timing mismatch — transaction recorded at different times across systems",
            "confidence": 94,
            "confidenceLabel": "success",
            "historicalPatternCount": 127,
            "historicalNote": "Pattern matched with 127 similar historical cases"
        },
    },
    "missing": {
        "rootCause": {
            "primaryCause": "Network timeout during system sync (API error detected)",
            "confidence": 85,
            "confidenceLabel": "warning",
            "historicalPatternCount": None,
            "historicalNote": "Retry mechanism available — auto-sync scheduled in 5 minutes"
        },
    },
    "fx-rate": {
        "rootCause": {
            "primaryCause": "FX rate difference between settlement and booking time",
            "confidence": 91,
            "confidenceLabel": "success",
            "historicalPatternCount": None,
            "historicalNote": "Rate differential within acceptable tolerance band"
        },
    },
    "fee": {
        "rootCause": {
            "primaryCause": "Processing fee not reflected in ERP ledger entry",
            "confidence": 96,
            "confidenceLabel": "success",
            "historicalPatternCount": None,
            "historicalNote": "Fee amount matches PSP fee schedule — auto-adjustment recommended"
        },
    },
    "duplicate": {
        "rootCause": {
            "primaryCause": "Duplicate entry detected in cashier system",
            "confidence": 99,
            "confidenceLabel": "success",
            "historicalPatternCount": None,
            "historicalNote": "Duplicate flagged — recommend voiding second entry"
        },
    },
}


def get_recommendation(match_score: int) -> dict:
    """Determine recommendation tier based on match score."""
    if match_score >= 90:
        return {
            "tier": "auto-reconcile",
            "title": "Auto-reconciliation available",
            "description": "High confidence match. AI agent can automatically resolve with approval.",
            "actions": []
        }
    elif match_score >= 70:
        return {
            "tier": "assisted",
            "title": "Assisted resolution suggested",
            "description": "AI agent recommends reviewing system logs before auto-reconciliation.",
            "actions": []
        }
    else:
        return {
            "tier": "manual-review",
            "title": "Manual review required",
            "description": "Significant discrepancy detected. AI has flagged for human verification.",
            "actions": ["Escalate to Finance Team", "Create Jira Ticket"]
        }


def get_agentic_insights(match_score: int, status: str) -> dict:
    """Generate agentic insight cards based on score tier."""
    if match_score >= 90:
        rate = "98.5%"
    elif match_score >= 70:
        rate = "92.3%"
    else:
        rate = "76.8%"

    return {
        "patternRecognition": {
            "label": "Pattern Recognition",
            "detail": f"AI detected similar patterns in {20 + hash(str(match_score)) % 50} recent transactions"
        },
        "historicalSuccessRate": {
            "label": "Historical Success Rate",
            "rate": rate,
            "detail": f"{rate} of similar cases were resolved automatically"
        },
        "anomalyDetection": {
            "label": "Anomaly Detection",
            "detail": "Unusual variance detected — outside normal distribution"
                if status == "discrepancy"
                else "Transaction within expected variance range"
        }
    }


def build_timeline(record: dict) -> list[dict]:
    """Build the AI-generated timeline for a record."""
    timestamp = record.get("timestamp", "09:30:00")
    time_part = timestamp.split(" ")[1] if " " in timestamp else timestamp

    return [
        {
            "system": "PSP",
            "icon": "CreditCard",
            "color": "blue",
            "title": "PSP Transaction Initiated",
            "timestamp": time_part,
            "description": "Payment processed successfully via payment gateway",
            "aiInsight": "AI: Normal processing time detected",
            "aiInsightType": "success"
        },
        {
            "system": "Cashier",
            "icon": "Building2",
            "color": "green",
            "title": "Cashier System Updated",
            "timestamp": time_part,
            "description": "Amount recorded in cashier system",
            "aiInsight": "AI: Entry pattern detected",
            "aiInsightType": "warning" if record.get("cashierAmount") != record.get("pspAmount") else "success"
        },
        {
            "system": "ERP",
            "icon": "Database",
            "color": "purple",
            "title": "ERP System Synchronized",
            "timestamp": time_part,
            "description": "Amount recorded from PSP feed",
            "aiInsight": "AI: Direct API sync verified" if record.get("erpAmount") != "-" else "AI: Sync failed — timeout",
            "aiInsightType": "success" if record.get("erpAmount") != "-" else "error"
        },
        {
            "system": "AI",
            "icon": "TrendingUp",
            "color": "gradient",
            "title": "AI Agent Analysis Complete",
            "timestamp": time_part,
            "description": "Root cause identified",
            "summary": {
                "matchConfidence": f"{record.get('matchScore', 0)}%",
                "similarPatterns": "127 cases",
                "recommendedAction": get_recommendation(record.get("matchScore", 0))["tier"].replace("-", " ").title()
            }
        },
        {
            "system": "Summary",
            "icon": "Clock",
            "color": "muted",
            "title": "Timeline Summary",
            "totalDuration": "7 seconds",
            "systemsInvolved": "3 platforms"
        }
    ]


def get_analysis_for_record(record: dict) -> dict | None:
    """
    Main entry point: given a ReconciliationRecord, return the full AI analysis.
    Returns None for matched records (frontend hides the section).

    Phase 1: returns hardcoded data.
    Phase 2: replace this with real AI calls.
    """
    if record.get("status") == "matched":
        return None

    disc_type = record.get("discrepancySubType")
    if not disc_type or disc_type not in HARDCODED_ANALYSIS:
        # Fallback for unknown types
        return None

    analysis = HARDCODED_ANALYSIS[disc_type]
    match_score = record.get("matchScore", 0)

    return {
        "rootCause": analysis["rootCause"],
        "recommendation": get_recommendation(match_score),
        "timeline": build_timeline(record),
        "agenticInsights": get_agentic_insights(match_score, record.get("status", "")),
        "modelVersion": "v2.4.1"
    }
```

### Phase 2: Replace with Real AI Calls

**File: `server/services/ai_analyzer.py`**

```python
import json
import os
from openai import OpenAI

client = OpenAI(api_key=os.environ.get("OPENAI_API_KEY"))

SYSTEM_PROMPT = """You are a financial reconciliation analyst for a 3-way payment matching system
(PSP, Cashier, ERP). You analyze discrepancies between these systems and provide root cause
analysis.

You will receive:
1. A reconciliation record with amounts from all 3 systems
2. The discrepancy type (missing, timing, amount-mismatch, duplicate, fx-rate, fee)
3. Historical context (if available)

Your job:
- Determine the most likely root cause
- Provide a confidence score (0.0-1.0)
- Recommend an action (auto-resolve, assisted-review, manual-review)
- Reference historical patterns if relevant

Confidence scoring rules:
- 0.95-1.00: You are very certain about the root cause (e.g. duplicate with same timestamp)
- 0.85-0.94: Strong evidence supports your analysis
- 0.70-0.84: Reasonable but could be wrong
- Below 0.70: Unsure — recommend manual review

Return ONLY a JSON object. No markdown, no explanation outside JSON.

Response format:
{
  "primaryCause": "Description of the root cause",
  "confidence": 0.91,
  "confidenceLabel": "success",
  "historicalPatternCount": 43,
  "historicalNote": "Similar discrepancies found in 43 transactions this month",
  "suggestedAction": "auto-resolve"
}"""


async def analyze_discrepancy(record: dict, discrepancy: dict, history: list[dict] | None = None) -> dict:
    """
    Call GPT-4o to analyze a discrepancy and return root cause analysis.

    Args:
        record: The ReconciliationRecord (id, transactionRef, amounts, matchScore, etc.)
        discrepancy: The Discrepancy object (type, severity, pspValue, cashierValue, erpValue)
        history: Optional list of previous discrepancies for this client/type

    Returns: Root cause analysis dict matching the frontend shape
    """
    user_prompt = f"""RECONCILIATION RECORD:
{json.dumps(record, indent=2, default=str)}

DISCREPANCY:
{json.dumps(discrepancy, indent=2, default=str)}

HISTORICAL CONTEXT:
{json.dumps(history or [], indent=2, default=str)}

Analyze this discrepancy. What caused it? How confident are you? What should we do?"""

    response = client.chat.completions.create(
        model="gpt-4o",
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": user_prompt},
        ],
        response_format={"type": "json_object"},
        max_tokens=512,
        temperature=0,
    )

    text = response.choices[0].message.content.strip()
    result = json.loads(text)

    # Normalize confidence label
    conf = result.get("confidence", 0)
    if conf >= 0.90:
        result["confidenceLabel"] = "success"
    elif conf >= 0.70:
        result["confidenceLabel"] = "warning"
    else:
        result["confidenceLabel"] = "error"

    # Convert confidence to percentage for frontend
    result["confidence"] = int(conf * 100) if conf <= 1 else conf

    return result
```

### Switching from Phase 1 to Phase 2

When you're ready to use real AI:

```python
# In the record detail endpoint handler:

from server.services.hardcoded_analysis import get_analysis_for_record
from server.services.ai_analyzer import analyze_discrepancy

USE_REAL_AI = os.environ.get("USE_AI_ANALYSIS", "false").lower() == "true"

async def get_record_detail(reconciliation_id: str, record_id: str):
    record = get_record(reconciliation_id, record_id)
    discrepancy = get_discrepancy_for_record(record_id)

    if USE_REAL_AI and record["status"] != "matched":
        # Phase 2: real AI analysis
        history = get_history_for_client(record.get("clientId"), record.get("discrepancySubType"))
        root_cause = await analyze_discrepancy(record, discrepancy, history)
        ai_analysis = {
            "rootCause": root_cause,
            "recommendation": get_recommendation(record["matchScore"]),
            "timeline": build_timeline(record),  # Still hardcoded — could also be AI-generated
            "agenticInsights": get_agentic_insights(record["matchScore"], record["status"]),
            "modelVersion": "v2.4.1"
        }
    else:
        # Phase 1: hardcoded responses
        ai_analysis = get_analysis_for_record(record)

    return {
        "record": record,
        "systemComparison": build_system_comparison(record),
        "fieldComparison": build_field_comparison(record),
        "discrepancy": build_discrepancy_info(record) if record["status"] != "matched" else None,
        "aiAnalysis": ai_analysis
    }
```

---

## What the Frontend Expects (The API Contract)

This is the **exact shape** the frontend renders. Every field name and type must match.

### Record Detail Response

```
GET /api/reconciliation/{reconciliationId}/records/{recordId}
```

```typescript
// ── This is what the frontend renders in the modal ──

interface RecordDetailResponse {
  // The core record (same fields as the table row)
  record: {
    id: string;
    transactionRef: string;
    pspAmount: string;              // "$12,450.00" or "-"
    cashierAmount: string;
    erpAmount: string;
    matchScore: number;             // 0-100
    status: "matched" | "partial" | "unmatched" | "discrepancy";
    matchType: "exact" | "unmatched" | "discrepancy";
    discrepancySubType?: "missing" | "timing" | "amount-mismatch" | "duplicate" | "fx-rate" | "fee";
    timestamp: string;
  };

  // 3 system comparison cards (always present)
  systemComparison: [
    { system: "PSP",     icon: "CreditCard", color: "blue",   amount: string, timestamp: string, status: "Processed" },
    { system: "Cashier", icon: "Building2",  color: "green",  amount: string, timestamp: string, status: "Recorded" | "Not Found" },
    { system: "ERP",     icon: "Database",   color: "purple", amount: string, timestamp: string, status: "Verified" | "Not Found" }
  ];

  // Field-by-field comparison table
  fieldComparison: [
    { field: "Amount",    psp: string, cashier: string, erp: string, variance: string | null },
    { field: "Timestamp", psp: string, cashier: string, erp: string, variance: string | null },
    { field: "Status",    psp: string, cashier: string, erp: string, variance: string | null }
  ];

  // Discrepancy info (null for matched records)
  discrepancy: {
    type: string;                   // The discrepancy sub-type
    detectedIssues: string[];       // ["PSP and Cashier amounts differ", "Missing cashier record"]
  } | null;

  // AI analysis (null for matched records)
  aiAnalysis: {
    rootCause: {
      primaryCause: string;         // "Amount mismatch — cashier system rounding..."
      confidence: number;           // 85-99 (percentage, NOT 0-1)
      confidenceLabel: "success" | "warning" | "error";
      historicalPatternCount: number | null;
      historicalNote: string;
    };
    recommendation: {
      tier: "auto-reconcile" | "assisted" | "manual-review";
      title: string;
      description: string;
      actions: string[];            // [] for auto/assisted, ["Escalate...", "Create Jira..."] for manual
    };
    timeline: AiTimelineEvent[];    // 5 events (see below)
    agenticInsights: {
      patternRecognition: { label: string; detail: string };
      historicalSuccessRate: { label: string; rate: string; detail: string };
      anomalyDetection: { label: string; detail: string };
    };
    modelVersion: string;           // "v2.4.1"
  } | null;
}
```

### Recommendation Tiers (The Rules)

The frontend uses `matchScore` to decide which banner to show:

| matchScore | Tier | What the User Sees |
|------------|------|-------------------|
| `>= 90` | `auto-reconcile` | **Green banner:** "Auto-reconciliation available" — one click to resolve |
| `70–89` | `assisted` | **Amber banner:** "Assisted resolution suggested" + expandable AI timeline |
| `< 70` | `manual-review` | **Red banner:** "Manual review required" + "Escalate" and "Create Jira" buttons |

### AI Root Cause by Discrepancy Type

The frontend has **6 hardcoded root causes** (one per type). Phase 1 backend should return these exact strings:

| Type | Primary Cause | Confidence | Label |
|------|--------------|------------|-------|
| `amount-mismatch` | Amount mismatch — cashier system rounding or manual entry error | 87 | warning |
| `timing` | Timing mismatch — transaction recorded at different times across systems | 94 | success |
| `missing` | Network timeout during system sync (API error detected) | 85 | warning |
| `fx-rate` | FX rate difference between settlement and booking time | 91 | success |
| `fee` | Processing fee not reflected in ERP ledger entry | 96 | success |
| `duplicate` | Duplicate entry detected in cashier system | 99 | success |

### Timeline Shape (5 Events)

The timeline is a collapsible section that shows how the transaction flowed through each system:

```python
# Standard 5-event timeline
[
    # 1. PSP leg
    {"system": "PSP", "icon": "CreditCard", "color": "blue",
     "title": "PSP Transaction Initiated", "timestamp": "09:30:02",
     "description": "Payment processed successfully via payment gateway",
     "aiInsight": "AI: Normal processing time detected", "aiInsightType": "success"},

    # 2. Cashier leg
    {"system": "Cashier", "icon": "Building2", "color": "green",
     "title": "Cashier System Updated", "timestamp": "09:30:05",
     "description": "Amount recorded in cashier system",
     "aiInsight": "AI: Rounding pattern detected (3 sec delay)", "aiInsightType": "warning"},

    # 3. ERP leg
    {"system": "ERP", "icon": "Database", "color": "purple",
     "title": "ERP System Synchronized", "timestamp": "09:30:08",
     "description": "Amount recorded from PSP feed",
     "aiInsight": "AI: Direct API sync verified", "aiInsightType": "success"},

    # 4. AI analysis summary (this one has a special "summary" field)
    {"system": "AI", "icon": "TrendingUp", "color": "gradient",
     "title": "AI Agent Analysis Complete", "timestamp": "09:30:09",
     "description": "Root cause identified",
     "summary": {"matchConfidence": "95%", "similarPatterns": "127 cases",
                  "recommendedAction": "Assisted resolution"}},

    # 5. Overall summary
    {"system": "Summary", "icon": "Clock", "color": "muted",
     "title": "Timeline Summary",
     "totalDuration": "7 seconds", "systemsInvolved": "3 platforms"}
]
```

---

## Audit Trail: Where AI Events Go

The audit trail records all AI actions. These are the **5 AI-generated audit events** from the sample:

| Event | Action | Target | What Happened |
|-------|--------|--------|---------------|
| AUD-002 | Pattern Analysis | BATCH-2024-0115 | AI analyzed 1,788 transactions, found 1,245 exact + 432 partial |
| AUD-003 | Anomaly Detected | TXN-2024-003 | AI flagged $300 variance as Amount Mismatch |
| AUD-007 | Auto-Resolved | TXN-2024-006 | AI resolved $0.75 fee discrepancy (96% confidence) |
| AUD-008 | Auto-Resolved | TXN-2024-012 | AI resolved $1.50 fee discrepancy (94% confidence) |
| AUD-014 | FX Rate Alert | TXN-2024-008 | AI flagged 0.44% FX rate differential |
| AUD-017 | Risk Assessment | BATCH-2024-0115 | AI calculated batch risk score: 12/100 (Low) |

**Backend must:** create audit events for every AI action (analysis, auto-resolve, alert).

**Audit event shape:**
```python
{
    "id": "AUD-002",
    "timestamp": "2024-01-15 20:00:15",
    "actor": "AI Agent v2.4.1",      # always this string
    "actorType": "ai",                # always "ai"
    "action": "Pattern Analysis",     # action name
    "target": "BATCH-2024-0115",      # batch or transaction ref
    "details": "Analyzed transaction patterns — identified 1,245 exact matches, 432 partial matches",
    "category": "reconciliation"      # or "resolution" for auto-resolved
}
```

---

## Auto-Resolution: When AI Can Resolve Without Human

The matching_config table has an `auto_resolve_confidence` setting (default: 92%). When AI confidence exceeds this:

```
AI analyzes fee discrepancy for TXN-2024-006
    |
    v
Confidence = 96% → exceeds threshold (92%)
    |
    v
Auto-resolve: mark discrepancy as resolved
    |
    v
Create audit event: "Auto-Resolved" + "matched against PSP fee schedule with 96% confidence"
    |
    v
Create notification for assigned analyst: "AI auto-resolved fee discrepancy for TXN-2024-006"
```

**When NOT to auto-resolve:**
- `missing` type — always needs human verification (record doesn't exist)
- Confidence below threshold
- Amount variance exceeds $100 (configurable)
- High-value transactions (>$10,000) — always manual review

---

## Estimated Cost

| AI Feature | When It Runs | Calls per 100 txns | Cost per Call | Total |
|-----------|-------------|---------------------|---------------|-------|
| Smart Matching (Step 3.5) | After fuzzy, for unmatched only | ~5 | ~$0.01 | $0.05 |
| Discrepancy Analysis (Step 4.5) | For each discrepancy | ~10 | ~$0.01 | $0.10 |
| **Total per reconciliation run** | | ~15 | | **$0.15** |

Phase 1 cost: **$0** (hardcoded responses, no AI calls).

---

## Implementation Checklist

### Phase 1 (Hackathon) — No AI Calls

- [ ] Create `hardcoded_analysis.py` with the 6 root cause mappings (copy from above)
- [ ] Create `get_recommendation(match_score)` function (3 tiers)
- [ ] Create `get_agentic_insights(match_score, status)` function
- [ ] Create `build_timeline(record)` function
- [ ] Create `get_analysis_for_record(record)` entry point
- [ ] Wire into `GET /api/reconciliation/{id}/records/{recordId}` endpoint
- [ ] Return `aiAnalysis: null` for matched records
- [ ] Return full `aiAnalysis` object for non-matched records
- [ ] Create AI-type audit events when batch runs
- [ ] Test: click row in frontend → modal shows AI analysis section

### Phase 2 (Post-Hackathon) — Real AI

- [ ] Install `openai` Python package
- [ ] Set `OPENAI_API_KEY` environment variable
- [ ] Create `ai_matcher.py` (Smart Matching)
- [ ] Create `ai_analyzer.py` (Discrepancy Analysis)
- [ ] Add `USE_AI_ANALYSIS` env toggle
- [ ] Add `ai_analysis` JSONB column to `discrepancies` table for caching
- [ ] Wire AI matcher into pipeline between Step 3 and Step 4
- [ ] Wire AI analyzer into pipeline after Step 4
- [ ] Implement auto-resolution logic (confidence > threshold)
- [ ] Add audit events for AI actions
- [ ] Test: run reconciliation → AI matches unmatched → AI analyzes discrepancies
- [ ] Test: click row → modal shows real AI analysis (not hardcoded)

---

## Summary

| What | Phase 1 | Phase 2 |
|------|---------|---------|
| **Pipeline Steps 1-5** | Rule-based (build this) | Same |
| **Step 3.5 AI Matching** | Skip — stays unmatched | GPT-4o matches from candidates |
| **Step 4.5 AI Analysis** | Hardcoded responses from `hardcoded_analysis.py` | GPT-4o real analysis |
| **Record Detail Endpoint** | Returns hardcoded `aiAnalysis` | Returns real `aiAnalysis` |
| **Auto-Resolution** | Manual only | AI auto-resolves if confidence > 92% |
| **Audit Trail** | Create AI events with hardcoded data | Create AI events with real analysis |
| **Cost** | $0 | ~$0.15 per 100 transactions |
| **Frontend Changes** | None — frontend already renders everything | None — same API shape |
