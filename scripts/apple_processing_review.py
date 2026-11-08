"""Disabled-path Apple build processing check; no network is run by tests."""
import base64
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.parse

APP_ID = '6832293368'


def _b64(b): return base64.urlsafe_b64encode(b).rstrip(b'=').decode('ascii')


def _ecdsa_raw(der):
    # OpenSSL returns DER ECDSA; ES256 JWT requires 32-byte R || 32-byte S.
    if len(der) < 8 or der[0] != 0x30 or der[1] != len(der) - 2: raise ValueError('signature')
    p = 2; result = []
    for _ in range(2):
        if p + 2 > len(der) or der[p] != 2: raise ValueError('signature')
        n = der[p + 1]; p += 2
        if n < 1 or n > 33 or p + n > len(der): raise ValueError('signature')
        v = der[p:p+n]; p += n
        if v[0] & 0x80 or (n > 1 and v[0] == 0 and not v[1] & 0x80): raise ValueError('signature')
        if n == 33:
            if v[0] != 0: raise ValueError('signature')
            v = v[1:]
        result.append(v.rjust(32, b'\0'))
    if p != len(der): raise ValueError('signature')
    return b''.join(result)


def token(key_path, key_id, issuer, *, now=None, signer=None):
    now = int(time.time() if now is None else now)
    header = {'alg': 'ES256', 'kid': key_id, 'typ': 'JWT'}
    claims = {'iat': now, 'exp': now + 300, 'aud': 'appstoreconnect-v1'}
    if issuer: claims['iss'] = issuer
    else: claims['sub'] = 'user'
    body = '.'.join(_b64(json.dumps(x, separators=(',', ':')).encode()) for x in (header, claims)).encode()
    if signer is None:
        def signer(data):
            p = subprocess.run(['/usr/bin/openssl', 'dgst', '-sha256', '-sign', str(key_path)],
                               input=data, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                               timeout=10, check=True)
            return p.stdout
    return body.decode() + '.' + _b64(_ecdsa_raw(signer(body)))


def interpret(raw, version, build):
    def unique(pairs):
        d = {}
        for k, v in pairs:
            if k in d: raise ValueError('duplicate')
            d[k] = v
        return d
    if not isinstance(raw, bytes) or len(raw) > 1048576: return 'unknown'
    try:
        d = json.loads(raw, object_pairs_hook=unique)
        if not isinstance(d['data'], list) or d['links']['next'] is not None: return 'unknown'
        matches = [x for x in d['data'] if x['attributes']['cfBundleShortVersionString'] == version
                   and x['attributes']['cfBundleVersion'] == build and x['attributes']['platform'] == 'IOS']
        if len(matches) != 1: return 'pending' if not matches else 'unknown'
        ref = matches[0]['relationships']['build']['data']
        if ref is None: return 'pending'
        if ref['type'] != 'builds': return 'unknown'
        builds = [x for x in d.get('included', []) if x.get('type') == 'builds' and x.get('id') == ref['id']]
        if len(builds) != 1: return 'unknown'
        state = builds[0]['attributes']['processingState']
        return {'VALID': 'valid', 'PROCESSING': 'pending', 'FAILED': 'failed', 'INVALID': 'failed'}.get(state, 'unknown')
    except (ValueError, KeyError, TypeError, UnicodeError): return 'unknown'


_WORKER = r'''import json,sys,urllib.request,urllib.error
payload=json.load(sys.stdin)
class NoRedirect(urllib.request.HTTPRedirectHandler):
 def redirect_request(self,*args,**kwargs): return None
try:
 req=urllib.request.Request(payload['url'],headers={'Authorization':'Bearer '+payload['token'],'Accept':'application/json'})
 with urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect).open(req,timeout=5) as response:
  if response.status != 200: raise ValueError()
  data=response.read(1048577)
  if len(data)>1048576: raise ValueError()
  sys.stdout.buffer.write(data)
except Exception: sys.exit(1)
'''


def fetch(jwt, version, build):
    query = urllib.parse.urlencode({'filter[cfBundleShortVersionString]': version,
                                   'filter[cfBundleVersion]': build, 'filter[platform]': 'IOS',
                                   'include': 'build', 'limit': '200'})
    url = 'https://api.appstoreconnect.apple.com/v1/apps/' + APP_ID + '/buildUploads?' + query
    payload = json.dumps({'url': url, 'token': jwt}).encode()
    try:
        r = subprocess.run([sys.executable, '-c', _WORKER], input=payload, stdout=subprocess.PIPE,
                           stderr=subprocess.DEVNULL, timeout=8, check=True)
        return r.stdout if len(r.stdout) <= 1048576 else b''
    except (OSError, subprocess.SubprocessError): return b''


def wait_for_processing(jwt, version, build, *, reader=fetch, clock=time.monotonic, sleeper=time.sleep):
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){1,2}', version) or not re.fullmatch(r'[1-9][0-9]*', build):
        return 'unknown'
    deadline = clock() + 120
    for _ in range(12):
        if clock() >= deadline: return 'unknown'
        state = interpret(reader(jwt, version, build), version, build)
        if state in ('valid', 'failed', 'unknown'): return state
        if deadline - clock() <= 10: return 'unknown'
        sleeper(10)
    return 'unknown'
