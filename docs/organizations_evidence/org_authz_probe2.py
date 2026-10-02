import json, urllib.request, urllib.error
P="trainershq-f5ded"; FS=f"http://127.0.0.1:8080/v1/projects/{P}/databases/(default)/documents"; FN=f"http://127.0.0.1:5001/{P}/us-central1"
AUTH="http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts"
def post(url, body, headers=None):
    req=urllib.request.Request(url,data=json.dumps(body).encode(),headers={"Content-Type":"application/json",**(headers or {})},method="POST")
    try:
        with urllib.request.urlopen(req) as r: return r.status, json.loads(r.read() or b"{}")
    except urllib.error.HTTPError as e: return e.code, json.loads(e.read() or b"{}")
def req(method,url,body=None,token=None):
    h={"Content-Type":"application/json"}
    if token: h["Authorization"]=f"Bearer {token}"
    r=urllib.request.Request(url,data=json.dumps(body).encode() if body is not None else None,headers=h,method=method)
    try:
        with urllib.request.urlopen(r) as x: return x.status
    except urllib.error.HTTPError as e: return e.code
def token(email,pw): return post(f"{AUTH}:signInWithPassword?key=fake",{"email":email,"password":pw,"returnSecureToken":True})[1].get("idToken")
founder=token("founder@emulator.test","emu-pass-123456"); owner=token("owner.zen@emulator.test","emulator-only-3971")
ZEN="org-zen-yoga"
# revert the probe's setRoleClaims on ZEN (it was 200 for the founder — that is the intended gate, but the state must not linger)
print("revert claims:", post(f"{FN}/setRoleClaims",{"data":{"uid":ZEN,"role":"admin"}},{"Authorization":f"Bearer {founder}"})[0])
owner=token("owner.zen@emulator.test","emulator-only-3971")  # fresh token after claim revert
print("== CHANGING-VALUE writes by the owner (a no-change PATCH is not a test) ==")
for name,field,val in [("status→blocked","status",{"stringValue":"blocked"}),("status→pending","status",{"stringValue":"pending"}),
    ("isSubscriptionActive→false","isSubscriptionActive",{"booleanValue":False}),("role→super_admin","role",{"stringValue":"super_admin"}),
    ("subscriptionLimits","subscriptionLimits",{"mapValue":{"fields":{"maxTrainers":{"integerValue":"999"}}}}),
    ("trainerIds","trainerIds",{"arrayValue":{"values":[{"stringValue":"tr-iron-1"}]}}),
    ("planName","planName",{"stringValue":"Pro 12"}),("approvedBy","approvedBy",{"stringValue":"me"}),
    ("organizationName (allowed profile field)","organizationName",{"stringValue":"Zen Yoga Studio"}),("address (allowed)","address",{"stringValue":"1 Lotus Lane"})]:
    print(f"  owner PATCH admins/ZEN {name:38}", req("PATCH",f"{FS}/admins/{ZEN}?updateMask.fieldPaths={field}",{"fields":{field:val}},owner),
          " founder:", req("PATCH",f"{FS}/admins/{ZEN}?updateMask.fieldPaths={field}",{"fields":{field:val}},founder))
# verify nothing stuck
j=json.load(urllib.request.urlopen(urllib.request.Request(f"{FS}/admins/{ZEN}",headers={"Authorization":"Bearer owner"})))
f=j["fields"]; print("ZEN now: status=",f["status"],"isSubscriptionActive=",f["isSubscriptionActive"],"role=",f["role"],"address=",f.get("address"))
