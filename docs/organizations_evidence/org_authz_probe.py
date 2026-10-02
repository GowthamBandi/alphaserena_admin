"""Backend authorization probe for the Organizations section — REAL tokens against the
emulator's rules + callables. Three principals: founder (super admin), an organization
owner (org-zen-yoga), and anonymous. Direct Firestore REST reads/writes use the SDK-style
endpoint WITHOUT the owner bearer so the rules apply."""
import json, urllib.request, urllib.error
P = "trainershq-f5ded"
FS = f"http://127.0.0.1:8080/v1/projects/{P}/databases/(default)/documents"
FN = f"http://127.0.0.1:5001/{P}/us-central1"
AUTH = "http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts"

def post(url, body, headers=None):
    req = urllib.request.Request(url, data=json.dumps(body).encode(), headers={"Content-Type": "application/json", **(headers or {})}, method="POST")
    try:
        with urllib.request.urlopen(req) as r: return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read() or b"{}")

def req(method, url, body=None, token=None):
    h = {"Content-Type": "application/json"}
    if token: h["Authorization"] = f"Bearer {token}"
    r = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None, headers=h, method=method)
    try:
        with urllib.request.urlopen(r) as x: return x.status
    except urllib.error.HTTPError as e: return e.code

def token(email, pw):
    s, j = post(f"{AUTH}:signInWithPassword?key=fake", {"email": email, "password": pw, "returnSecureToken": True})
    return j.get("idToken")

def call(fn, tok, data):
    s, j = post(f"{FN}/{fn}", {"data": data}, {"Authorization": f"Bearer {tok}"} if tok else {})
    err = (j.get("error") or {}).get("status") or (j.get("error") or {}).get("message")
    return f"{s} {err or 'OK'}"

founder = token("founder@emulator.test", "emu-pass-123456")
owner = token("owner.zen@emulator.test", "emulator-only-3971")      # org-zen-yoga's owner
assert founder and owner, "tokens"
ZEN, IRON, BLOCKED, PEND = "org-zen-yoga", "org-iron-temple", "org-blocked-gym", "org-pending-gym"
P_ = {"founder": founder, "owner(zen)": owner, "anonymous": None}

def q(coll, field, value):  # runQuery via REST, rules-enforced
    return {"structuredQuery": {"from": [{"collectionId": coll}], "where": {"fieldFilter": {"field": {"fieldPath": field}, "op": "EQUAL", "value": {"stringValue": value}}}, "limit": 5}}

print("== READS (rules) ==")
reads = [
  ("GET admins/ZEN", lambda t: req("GET", f"{FS}/admins/{ZEN}", token=t)),
  ("GET admins/IRON (another org)", lambda t: req("GET", f"{FS}/admins/{IRON}", token=t)),
  ("LIST admins", lambda t: req("GET", f"{FS}/admins?pageSize=3", token=t)),
  ("QUERY trainers assignedBy=IRON", lambda t: req("POST", f"{FS}:runQuery", q("trainers", "assignedBy", IRON), t)),
  ("QUERY clients adminId=IRON", lambda t: req("POST", f"{FS}:runQuery", q("clients", "adminId", IRON), t)),
  ("QUERY receipts adminUid=IRON", lambda t: req("POST", f"{FS}:runQuery", q("admin_payments_history", "adminUid", IRON), t)),
  ("QUERY audit_logs targetId=IRON", lambda t: req("POST", f"{FS}:runQuery", q("audit_logs", "targetId", IRON), t)),
  ("QUERY access_requests provisionedOrgUid=IRON", lambda t: req("POST", f"{FS}:runQuery", q("access_requests", "provisionedOrgUid", IRON), t)),
  ("GET quotaAlerts/org-big-gym", lambda t: req("GET", f"{FS}/quotaAlerts/org-big-gym", token=t)),
  ("QUERY ops_incidents correlationId=org-nosub-gym", lambda t: req("POST", f"{FS}:runQuery", q("ops_incidents", "correlationId", "org-nosub-gym"), t)),
  ("GET organizationProfiles/IRON", lambda t: req("GET", f"{FS}/organizationProfiles/{IRON}", token=t)),
]
for name, f in reads:
    print(f"{name:48}", "  ".join(f"{p}={f(t)}" for p, t in P_.items()))

print("\n== DIRECT WRITES (rules) — every one must be 403 for everyone ==")
patch = lambda doc, field, val: {"fields": {field: {"stringValue": val}}}
writes = [
  ("PATCH admins/ZEN status=active", lambda t: req("PATCH", f"{FS}/admins/{ZEN}?updateMask.fieldPaths=status", patch(None, "status", "active"), t)),
  ("PATCH admins/ZEN isSubscriptionActive", lambda t: req("PATCH", f"{FS}/admins/{ZEN}?updateMask.fieldPaths=isSubscriptionActive", {"fields": {"isSubscriptionActive": {"booleanValue": True}}}, t)),
  ("PATCH admins/ZEN planExpiry", lambda t: req("PATCH", f"{FS}/admins/{ZEN}?updateMask.fieldPaths=planExpiry", patch(None, "planExpiry", "2099-01-01T00:00:00Z"), t)),
  ("PATCH admins/IRON status (other org)", lambda t: req("PATCH", f"{FS}/admins/{IRON}?updateMask.fieldPaths=status", patch(None, "status", "blocked"), t)),
  ("DELETE admins/ZEN", lambda t: req("DELETE", f"{FS}/admins/{ZEN}", token=t)),
  ("PATCH trainers/tr-iron-1 assignedBy=ZEN (steal)", lambda t: req("PATCH", f"{FS}/trainers/tr-iron-1?updateMask.fieldPaths=assignedBy", patch(None, "assignedBy", ZEN), t)),
  ("PATCH clients/m-iron-1 adminId=ZEN (steal)", lambda t: req("PATCH", f"{FS}/clients/m-iron-1?updateMask.fieldPaths=adminId", patch(None, "adminId", ZEN), t)),
  ("PATCH admin_payments_history/rc-zen-1 amount", lambda t: req("PATCH", f"{FS}/admin_payments_history/rc-zen-1?updateMask.fieldPaths=amount", {"fields": {"amount": {"integerValue": "1"}}}, t)),
  ("POST audit_logs (forge)", lambda t: req("POST", f"{FS}/audit_logs", {"fields": {"action": {"stringValue": "set_admin_status"}, "targetId": {"stringValue": ZEN}}}, t)),
  ("PATCH access_requests/ar-pulse provisionedOrgUid", lambda t: req("PATCH", f"{FS}/access_requests/ar-pulse?updateMask.fieldPaths=provisionedOrgUid", patch(None, "provisionedOrgUid", ZEN), t)),
  ("PATCH organizationProfiles/IRON orgActive", lambda t: req("PATCH", f"{FS}/organizationProfiles/{IRON}?updateMask.fieldPaths=orgActive", {"fields": {"orgActive": {"booleanValue": False}}}, t)),
  ("DELETE quotaAlerts/org-big-gym", lambda t: req("DELETE", f"{FS}/quotaAlerts/org-big-gym", token=t)),
]
for name, f in writes:
    print(f"{name:48}", "  ".join(f"{p}={f(t)}" for p, t in P_.items()))

print("\n== CALLABLES ==")
tests = [
  ("setAdminStatus ZEN→warning (no-op-ish)", "setAdminStatus", {"adminUid": ZEN, "status": "warning", "reason": "probe"}),
  ("setAdminStatus bogus status", "setAdminStatus", {"adminUid": ZEN, "status": "deleted"}),
  ("setAdminStatus unknown org", "setAdminStatus", {"adminUid": "no-such-org", "status": "active"}),
  ("grantSubscription reused reference", "grantSubscription", {"adminUid": IRON, "planId": "plan-growth", "months": 1, "reference": "UTR-PULSE-RENEW-1", "amount": 1}),
  ("grantSubscription blocked org", "grantSubscription", {"adminUid": BLOCKED, "planId": "plan-growth", "months": 1, "reference": "UTR-PROBE-BLK", "amount": 1}),
  ("grantSubscription archived plan", "grantSubscription", {"adminUid": IRON, "planId": "plan-archived", "months": 1, "reference": "UTR-PROBE-ARCH", "amount": 1}),
  ("grantSubscription months=0", "grantSubscription", {"adminUid": IRON, "planId": "plan-growth", "months": 0, "reference": "UTR-PROBE-M0", "amount": 1}),
  ("grantSubscription negative amount", "grantSubscription", {"adminUid": IRON, "planId": "plan-growth", "months": 1, "reference": "UTR-PROBE-NEG", "amount": -5}),
  ("refundPayment wrong historyDocId (other org's)", "refundPayment", {"paymentId": "pay_ZEN1", "historyDocId": "rc-iron-1", "amount": 1, "reason": "probe"}),
  ("refundPayment fractional amount", "refundPayment", {"paymentId": "pay_ZEN1", "historyDocId": "rc-zen-1", "amount": 0.5, "reason": "probe"}),
  ("setRoleClaims (not exposed in UI)", "setRoleClaims", {"uid": ZEN, "role": "super_admin"}),
]
for name, fn, data in tests:
    print(f"{name:48}", "  ".join(f"{p}={call(fn, t, data)}" for p, t in P_.items()))

# restore Zen's status (the founder probe above may have set warning)
print("\nrestore:", call("setAdminStatus", founder, {"adminUid": ZEN, "status": "active", "reason": "probe restore"}))
