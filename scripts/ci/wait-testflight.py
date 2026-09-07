import base64, json, os, subprocess, sys, tempfile, time, urllib.error, urllib.request
from decimal import Decimal, InvalidOperation, ROUND_FLOOR

APP_ID = '6808947599'
INTERNAL_GROUP_ID = 'd92cb5bc-beac-44bd-8982-02b018381214'
EXTERNAL_GROUP_ID = 'dda2338b-79c5-45bf-bd8a-4fea9705e911'
WHAT_TO_TEST = 'Please test habit tracking, widgets, Shortcuts, and iCloud sync in this build.'
f = {'key_id': os.environ['ASC_KEY_ID'], 'issuer_id': os.environ['ASC_ISSUER_ID'], 'private_key': os.environ['ASC_PRIVATE_KEY']}
if len(f['private_key']) > 1 and f['private_key'][0] == f['private_key'][-1] and f['private_key'][0] in "'\"":
    f['private_key'] = f['private_key'][1:-1]
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
def request(method, path, body=None):
 url = path if path.startswith('https://') else 'https://api.appstoreconnect.apple.com/v1/' + path
 data = json.dumps(body).encode() if body is not None else None
 req=urllib.request.Request(url,data=data,method=method,headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
 try:
  with urllib.request.urlopen(req) as res:
   return None if res.status == 204 else json.load(res)
 except urllib.error.HTTPError as error:
  try:
   payload = json.load(error)
   details = '; '.join(item.get('detail') or item.get('title') or item.get('code', 'unknown error') for item in payload.get('errors', []))
  except (json.JSONDecodeError, UnicodeDecodeError):
   details = 'no response details'
  raise SystemExit('App Store Connect API ' + method + ' failed (' + str(error.code) + '): ' + details)

def get(path): return request('GET', path)

def distribute_externally(build):
 build_id = build['id']
 localizations = get('betaBuildLocalizations?filter[build]=' + build_id)['data']
 if localizations:
  localization = localizations[0]
  request('PATCH', 'betaBuildLocalizations/' + localization['id'], {'data': {'type': 'betaBuildLocalizations', 'id': localization['id'], 'attributes': {'whatsNew': WHAT_TO_TEST}}})
 else:
  request('POST', 'betaBuildLocalizations', {'data': {'type': 'betaBuildLocalizations', 'attributes': {'locale': 'en-US', 'whatsNew': WHAT_TO_TEST}, 'relationships': {'build': {'data': {'type': 'builds', 'id': build_id}}}}})

 request('PATCH', 'buildBetaDetails/' + build_id, {'data': {'type': 'buildBetaDetails', 'id': build_id, 'attributes': {'autoNotifyEnabled': True}}})
 group_ids = [group['id'] for group in build['relationships']['betaGroups']['data']]
 if EXTERNAL_GROUP_ID not in group_ids:
  request('POST', 'builds/' + build_id + '/relationships/betaGroups', {'data': [{'type': 'betaGroups', 'id': EXTERNAL_GROUP_ID}]})

 detail = get('builds/' + build_id + '/buildBetaDetail')['data']['attributes']
 state = detail['externalBuildState']
 if state == 'READY_FOR_BETA_SUBMISSION':
  submission = request('POST', 'betaAppReviewSubmissions', {'data': {'type': 'betaAppReviewSubmissions', 'relationships': {'build': {'data': {'type': 'builds', 'id': build_id}}}}})
  state = submission['data']['attributes']['betaReviewState']
  message = 'Build ' + build['attributes']['version'] + ' was added to the external group and submitted for Beta App Review (' + state + ').'
 elif state in ('WAITING_FOR_BETA_REVIEW', 'IN_BETA_REVIEW', 'BETA_APPROVED', 'READY_FOR_BETA_TESTING', 'IN_BETA_TESTING'):
  message = 'Build ' + build['attributes']['version'] + ' is assigned to the external group (' + state + ').'
 else:
  raise SystemExit('Build ' + build['attributes']['version'] + ' cannot be distributed externally from state ' + state + '.')
 print(message)
 with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
  summary.write(message + '\n')

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

distribute_external = '--distribute-external' in sys.argv[2:]
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
            if detail['internalBuildState'] == 'IN_BETA_TESTING' and any(g['id'] == INTERNAL_GROUP_ID for g in groups):
                message = 'Build ' + sys.argv[1] + ' is available to Internal Testers.'
                print(message)
                with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary:
                    summary.write(message + '\n')
                if distribute_external:
                    distribute_externally(build)
                raise SystemExit(0)
    time.sleep(15)
raise SystemExit('Timed out waiting for Internal TestFlight availability; check App Store Connect before retrying.')
