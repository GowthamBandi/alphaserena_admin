"""Independent recomputation of what the Organizations screen must show, from the raw
emulator documents (REST, owner bearer). Mirrors organization_language.dart's rules by
hand — a second implementation, not a call into the first."""
import json, sys, urllib.request, datetime as dt
P = "trainershq-f5ded"
FS = f"http://127.0.0.1:8080/v1/projects/{P}/databases/(default)/documents"
H = {"Authorization": "Bearer owner"}
NOW = dt.datetime.now(dt.timezone.utc)

def dec(f):
    (t, v), = f.items()
    if t in ("integerValue", "doubleValue"): return float(v)
    if t == "booleanValue": return v
    if t == "nullValue": return None
    if t == "timestampValue": return dt.datetime.fromisoformat(v.replace("Z", "+00:00"))
    if t == "arrayValue": return [dec(x) for x in v.get("values", [])]
    if t == "mapValue": return {k: dec(x) for k, x in v.get("fields", {}).items()}
    return v

def coll(name):
    out, tok = [], None
    while True:
        url = f"{FS}/{name}?pageSize=300" + (f"&pageToken={tok}" if tok else "")
        j = json.load(urllib.request.urlopen(urllib.request.Request(url, headers=H)))
        for d in j.get("documents", []):
            out.append({"id": d["name"].split("/")[-1], **{k: dec(v) for k, v in d.get("fields", {}).items()}})
        tok = j.get("nextPageToken")
        if not tok: return out

def date(v):
    if v is None: return None
    if isinstance(v, dt.datetime): return v
    try: return dt.datetime.fromisoformat(str(v).replace("Z", "+00:00"))
    except Exception: return None

def cal_days(a, b):
    return (b.date() - a.date()).days

admins = coll("admins"); trainers = coll("trainers"); clients = coll("clients")
receipts = coll("admin_payments_history"); requests = coll("access_requests")
quotas = {q["id"]: q for q in coll("quotaAlerts")}; incidents = coll("ops_incidents")
storefronts = {s["id"]: s for s in coll("organizationProfiles")}

def standing(a):
    s = (a.get("status") or "pending").lower()
    return {"pending": "awaiting", "active": "approved", "approved": "approved", "warning": "warning", "blocked": "blocked"}.get(s, "unknown")

def sub_state(a):
    if a.get("isSubscriptionActive") is not True: return "none", None
    end = date(a.get("planExpiry")) or date((a.get("subscription") or {}).get("expiry"))
    if end is None: return "activeNoEndDate", None
    days = cal_days(NOW, end)
    if days < 0: return "activePastEnd", days
    if days <= 7: return "expiringSoon", days
    return "active", days

def record_issues(a):
    st, (ss, days) = standing(a), sub_state(a)
    out = []
    if st == "unknown": out.append(("unknown_status", "critical"))
    if st == "awaiting": out.append(("awaiting_approval", "attention"))
    if ss == "activePastEnd": out.append(("active_past_end", "critical"))
    if ss == "activeNoEndDate": out.append(("active_no_end_date", "attention"))
    if ss == "expiringSoon": out.append(("expiring_soon", "attention"))
    if st in ("approved", "warning") and a.get("isSubscriptionActive") is not True: out.append(("approved_no_subscription", "attention"))
    if st == "blocked": out.append(("blocked", "info"))
    if st == "warning": out.append(("warning_on_file", "info"))
    if not (a.get("email") or "").strip(): out.append(("no_owner_email", "attention"))
    if not (a.get("organizationName") or "").strip(): out.append(("no_org_name", "info"))
    if date(a.get("createdAt")) is None: out.append(("no_created_at", "info"))
    return out

def needs_attention(a): return any(sev != "info" for _, sev in record_issues(a))
def can_operate(a): return standing(a) in ("approved", "warning") and a.get("isSubscriptionActive") is True
def recent(a):
    c = date(a.get("createdAt")); return c is not None and cal_days(c, NOW) <= 30

keys = {
  "all": lambda a: True, "attention": needs_attention, "pending": lambda a: standing(a) == "awaiting",
  "noSubscription": lambda a: a.get("isSubscriptionActive") is not True and standing(a) not in ("blocked", "awaiting"),
  "expiring": lambda a: sub_state(a)[0] == "expiringSoon", "blocked": lambda a: standing(a) == "blocked", "recent": recent,
  "active": lambda a: (a.get("status") or "").lower() == "active", "warning": lambda a: standing(a) == "warning", "operating": can_operate,
}
print("== TILE COUNTS ==")
for k, f in keys.items(): print(f"{k:16} {sum(1 for a in admins if f(a))}")
print(f"total {len(admins)}")

print("\n== PER ORG ==")
for a in sorted(admins, key=lambda x: x.get("organizationName") or x.get("name") or ""):
    uid = a["id"]
    tr = [t for t in trainers if t.get("assignedBy") == uid]
    live = [t for t in tr if not (t.get("isDeleted") or t.get("status") == "removed")]
    mem = [m for m in clients if m.get("adminId") == uid]
    rc = [r for r in receipts if r.get("adminUid") == uid]
    rq = [r for r in requests if r.get("provisionedOrgUid") == uid]
    rel = []
    seats = set(a.get("trainerIds") or []); liveids = {t["id"] for t in live}
    if seats != liveids: rel.append("trainer_roster_mismatch")
    op = can_operate(a)
    if any(t.get("orgActive") is not None and t.get("orgActive") != op for t in live): rel.append("trainer_access_stale")
    tids = {t["id"] for t in tr}
    if any((m.get("trainerId") or "") and m["trainerId"] not in tids and m["trainerId"] != uid for m in mem): rel.append("member_coach_outside_org")
    sf = storefronts.get(uid)
    if sf is None: rel.append("no_storefront(info)")
    elif isinstance(sf.get("orgActive"), bool) and sf["orgActive"] != op: rel.append("storefront_stale")
    if a.get("isSubscriptionActive") is True and not rc: rel.append("no_receipt_for_subscription(info)")
    if len(rq) > 1: rel.append("multiple_access_requests")
    q = quotas.get(uid)
    if q and q.get("status", "open") == "open": rel.append("over_plan_limits")
    if any(i.get("correlationId") == uid and i.get("status", "open") == "open" for i in incidents): rel.append("failed_backend_operation(critical)")
    ss, days = sub_state(a)
    print(f"{a.get('organizationName') or a.get('name') or '?':22} {uid:30} standing={standing(a):9} sub={ss:15} days={days} "
          f"operating={op} trainers_live={len(live)}/{len(tr)} members={len(mem)} receipts={len(rc)} requests={len(rq)}")
    print(f"   record={[c for c,_ in record_issues(a)]} related={rel} attention={needs_attention(a)}")
