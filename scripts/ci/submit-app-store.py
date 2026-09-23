import base64
import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request

APP_ID = '6808947599'

if len(sys.argv) != 3:
    raise SystemExit('Usage: submit-app-store.py MARKETING_VERSION BUILD_NUMBER')

version, build_number = sys.argv[1:]
credentials = {
    'key_id': os.environ['ASC_KEY_ID'],
    'issuer_id': os.environ['ASC_ISSUER_ID'],
    'private_key': os.environ['ASC_PRIVATE_KEY'],
}
if len(credentials['private_key']) > 1 and credentials['private_key'][0] == credentials['private_key'][-1] and credentials['private_key'][0] in "'\"":
    credentials['private_key'] = credentials['private_key'][1:-1]


def b64(value):
    return base64.urlsafe_b64encode(value).rstrip(b'=')


header = b64(json.dumps({'alg': 'ES256', 'kid': credentials['key_id'], 'typ': 'JWT'}).encode())
payload = b64(json.dumps({'iss': credentials['issuer_id'], 'iat': int(time.time()), 'exp': int(time.time()) + 1200, 'aud': 'appstoreconnect-v1'}).encode())
message = header + b'.' + payload
descriptor, key_path = tempfile.mkstemp(suffix='.p8')
try:
    with os.fdopen(descriptor, 'w') as key_file:
        key_file.write(credentials['private_key'])
    signature = subprocess.check_output(['openssl', 'dgst', '-sha256', '-sign', key_path], input=message)
finally:
    os.unlink(key_path)

index = 2
assert signature[index] == 2
length = signature[index + 1]
r = int.from_bytes(signature[index + 2:index + 2 + length], 'big')
index += 2 + length
assert signature[index] == 2
length = signature[index + 1]
s = int.from_bytes(signature[index + 2:index + 2 + length], 'big')
token = (message + b'.' + b64(r.to_bytes(32, 'big') + s.to_bytes(32, 'big'))).decode()


def request(method, path, body=None):
    url = path if path.startswith('https://') else 'https://api.appstoreconnect.apple.com/v1/' + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={'Authorization': 'Bearer ' + token, 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req) as response:
            return None if response.status == 204 else json.load(response)
    except urllib.error.HTTPError as error:
        try:
            payload = json.load(error)
            details = '; '.join(item.get('detail') or item.get('title') or item.get('code', 'unknown error') for item in payload.get('errors', []))
        except (json.JSONDecodeError, UnicodeDecodeError):
            details = 'no response details'
        raise SystemExit('App Store Connect API ' + method + ' failed (' + str(error.code) + '): ' + details)


query = urllib.parse.urlencode({'filter[app]': APP_ID, 'filter[version]': build_number, 'include': 'preReleaseVersion', 'limit': 10})
build_response = request('GET', 'builds?' + query)
builds = build_response['data']
matching_builds = [build for build in builds if build['attributes']['processingState'] == 'VALID']
if len(matching_builds) != 1:
    raise SystemExit('Expected one valid App Store Connect build numbered ' + build_number + ', found ' + str(len(matching_builds)) + '.')
build = matching_builds[0]
pre_release_version_id = build['relationships']['preReleaseVersion']['data']['id']
pre_release_versions = {item['id']: item for item in build_response.get('included', []) if item['type'] == 'preReleaseVersions'}
build_version = pre_release_versions[pre_release_version_id]['attributes']['version']
if build_version != version:
    raise SystemExit('Build ' + build_number + ' belongs to version ' + build_version + ', not ' + version + '.')

query = urllib.parse.urlencode({'filter[app]': APP_ID, 'filter[platform]': 'IOS', 'filter[versionString]': version, 'limit': 10})
versions = request('GET', 'appStoreVersions?' + query)['data']
if len(versions) != 1:
    raise SystemExit('Prepare App Store version ' + version + ' and its metadata before creating the stable release tag.')
app_store_version = versions[0]
state = app_store_version['attributes']['appStoreState']
if state not in ('PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED', 'REJECTED', 'METADATA_REJECTED'):
    raise SystemExit('App Store version ' + version + ' cannot accept a build while it is ' + state + '.')

request('PATCH', 'appStoreVersions/' + app_store_version['id'] + '/relationships/build', {
    'data': {'type': 'builds', 'id': build['id']},
})
submission = request('POST', 'appStoreVersionSubmissions', {
    'data': {
        'type': 'appStoreVersionSubmissions',
        'relationships': {
            'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': app_store_version['id']}},
        },
    },
})
submission_id = submission['data']['id']
summary = 'Build ' + build_number + ' was attached to App Store version ' + version + ' and submitted for App Review (' + submission_id + ').'
print(summary)
with open(os.environ['GITHUB_STEP_SUMMARY'], 'a') as summary_file:
    summary_file.write(summary + '\n')
