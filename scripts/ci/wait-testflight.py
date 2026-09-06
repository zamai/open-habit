import base64, json, os, subprocess, sys, tempfile, time, urllib.request
from decimal import Decimal, InvalidOperation, ROUND_FLOOR

APP_ID = '6808947599'
f = {'key_id': os.environ['ASC_KEY_ID'], 'issuer_id': os.environ['ASC_ISSUER_ID'], 'private_key': os.environ['ASC_PRIVATE_KEY']}
def b64(x): return base64.urlsafe_b64encode(x).rstrip(b'=')
h=b64(json.dumps({'alg':'ES256','kid':f['key_id'],'typ':'JWT'}).encode())
p=b64(json.dumps({'iss':f['issuer_id'],'iat':int(time.time()),'exp':int(time.time())+1200,'aud':'appstoreconnect-v1'}).encode())
msg=h+b'.'+p
fd,path=tempfile.mkstemp(suffix='.p8')
try:
 with os.fdopen(fd,'w') as out: out.write(f['private_key'])
 sig=subprocess.check_output(['openssl','dgst','-sha256','-sign',path],input=msg)
finally: os.unlink(path)
i=2
assert sig[i]==2
n=sig[i+1];r=int.from_bytes(sig[i+2:i+2+n],'big');i+=2+n
assert sig[i]==2
n=sig[i+1];s=int.from_bytes(sig[i+2:i+2+n],'big')
token=(msg+b'.'+b64(r.to_bytes(32,'big')+s.to_bytes(32,'big'))).decode()
def get(path):
 url = path if path.startswith('https://') else 'https://api.appstoreconnect.apple.com/v1/' + path
 req=urllib.request.Request(url,headers={'Authorization':'Bearer '+token})
 with urllib.request.urlopen(req) as res:return json.load(res)

if sys.argv[1] == '--next-build-number':
    versions = []
    path = 'builds?filter[app]=' + APP_ID + '&limit=200'
    while path:
        page = get(path)
        for build in page['data']:
            try:
                versions.append(Decimal(build['attributes']['version']))
            except InvalidOperation:
                pass
        path = page.get('links', {}).get('next')
    highest = max(versions, default=Decimal(0))
    print(int(highest.to_integral_value(rounding=ROUND_FLOOR)) + 1)
    raise SystemExit(0)

for attempt in range(60):
    builds = get('builds?filter[app]=' + APP_ID + '&filter[version]=' + sys.argv[1] + '&include=betaGroups')
    for build in builds['data']:
        state = build['attributes']['processingState']
        print('Build', sys.argv[1], state, flush=True)
        if state in ('FAILED', 'INVALID'):
            raise SystemExit('Apple rejected processing; inspect App Store Connect.')
        if state == 'VALID':
            detail = get('builds/' + build['id'] + '/buildBetaDetail')['data']['attributes']
            groups = build['relationships']['betaGroups']['data']
            if detail['internalBuildState'] == 'IN_BETA_TESTING' and any(g['id'] == 'd92cb5bc-beac-44bd-8982-02b018381214' for g in groups):
                message = 'Build ' + sys.argv[1] + ' is available to Internal Testers.'
                print(message)
                with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
                    summary.write(message + '\n')
                raise SystemExit(0)
    time.sleep(15)
raise SystemExit('Timed out waiting for Internal TestFlight availability; check App Store Connect before retrying.')
