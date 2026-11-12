"""Public work indexing and the existing community_search RPC response adapter."""
import base64
import json
import logging
import os
from pathlib import Path
import ssl
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent
CONFIG = json.loads(Path(os.environ['COMMUNITY_CONFIG']).read_text())
API = CONFIG['origin'] + '/rest/v1'
ANON_KEY = CONFIG['anonKey']
ENGINE = 'https://127.0.0.1:19200'
ORIGINAL_RPC = 'http://127.0.0.1:19202/rest/v1/rpc/community_search'
INDEX = 'public-works-v1'
PASSWORD = (ROOT / 'engine-password').read_text().strip()
ENGINE_AUTH = 'Basic ' + base64.b64encode(('admin:' + PASSWORD).encode()).decode()
TLS = ssl.create_default_context(cafile=str(ROOT / 'engine-root-ca.pem'))
READY = threading.Event()


def request_json(url, data=None, authorization=None, engine=False, method=None):
    headers = {'Content-Type': 'application/json'}
    if authorization:
        headers['Authorization'] = authorization
    if engine:
        headers['Authorization'] = ENGINE_AUTH
    else:
        headers['apikey'] = ANON_KEY
    payload = None if data is None else json.dumps(data, ensure_ascii=False).encode()
    request = Request(url, data=payload, headers=headers, method=method)
    with urlopen(request, timeout=8, context=TLS if engine else None) as response:
        return json.load(response)


def public_works():
    rows = []
    while True:
        query = urlencode({
            'select': 'id,title,description', 'visibility': 'eq.public',
            'moderation_status': 'eq.ok', 'deleted_at': 'is.null',
            'published_at': 'not.is.null', 'order': 'id.asc',
            'limit': '100', 'offset': str(len(rows)),
        })
        page = request_json(API + '/works?' + query, authorization='Bearer ' + ANON_KEY)
        if not isinstance(page, list):
            raise ValueError('Invalid public works response')
        rows.extend(page)
        if len(page) < 100:
            return rows


def synchronize():
    mappings = json.loads((ROOT / 'index-settings.json').read_text())
    try:
        request_json(ENGINE + '/' + INDEX, mappings, engine=True, method='PUT')
    except HTTPError as error:
        if error.code != 400:
            raise
        existing = request_json(ENGINE + '/' + INDEX, engine=True)
        if INDEX not in existing:
            raise
        request_json(ENGINE + '/' + INDEX + '/_delete_by_query?refresh=true',
                     {'query': {'match_all': {}}}, engine=True)
    previous = {}
    while True:
        try:
            current = {row['id']: row for row in public_works()}
            operations = []
            for work_id, row in current.items():
                if row == previous.get(work_id):
                    continue
                operations.append({'index': {'_index': INDEX, '_id': work_id}})
                operations.append({
                    'title': row['title'], 'description': row.get('description') or '',
                    'suggest': {'input': [row['title']]},
                })
            for work_id in previous.keys() - current.keys():
                operations.append({'delete': {'_index': INDEX, '_id': work_id}})
            if operations:
                payload = ''.join(json.dumps(row, ensure_ascii=False) + '\n' for row in operations).encode()
                request = Request(ENGINE + '/_bulk?refresh=wait_for', data=payload, headers={
                    'Content-Type': 'application/x-ndjson', 'Authorization': ENGINE_AUTH,
                })
                with urlopen(request, timeout=15, context=TLS) as response:
                    result = json.load(response)
                if result.get('errors'):
                    raise ValueError('Public index update failed')
                logging.info('Public index synchronized, documents=%s', len(current))
            previous = current
            READY.set()
        except Exception as error:
            logging.error('Public index synchronization failed: %s', type(error).__name__)
        time.sleep(10)


def query_engine(action, query):
    if action == 'suggest':
        body = {'size': 0, '_source': False, 'suggest': {'titles': {
            'prefix': query,
            'completion': {'field': 'suggest', 'size': 100, 'skip_duplicates': False,
                           'fuzzy': {'fuzziness': 'AUTO', 'unicode_aware': True}},
        }}}
        result = request_json(ENGINE + '/' + INDEX + '/_search', body, engine=True)
        return [option['_id'] for row in result['suggest']['titles'] for option in row['options']]
    body = {'size': 100, '_source': False, 'query': {'bool': {'should': [
        {'multi_match': {'query': query, 'fields': ['title', 'description', 'title.pinyin'],
                         'fuzziness': 'AUTO'}},
        {'match_bool_prefix': {'title.pinyin': {'query': query}}},
    ], 'minimum_should_match': 1}}}
    result = request_json(ENGINE + '/' + INDEX + '/_search', body, engine=True)
    return [row['_id'] for row in result['hits']['hits']]


class Handler(BaseHTTPRequestHandler):
    def respond(self, code, value):
        payload = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_POST(self):
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if length < 1 or length > 4096:
                self.respond(400, {'error': 'invalid_query'})
                return
            body = json.loads(self.rfile.read(length))
            action, query = body.get('p_action'), body.get('p_query')
            if action not in ('suggest', 'search') or not isinstance(query, str) or not 1 <= len(query.strip()) <= 128:
                self.respond(400, {'error': 'invalid_query'})
                return
            if not READY.is_set():
                self.respond(503, {'error': 'search_initializing'})
                return
            ids = list(dict.fromkeys(query_engine(action, query.strip())))
            # Final authorization uses the current database RPC and caller JWT.
            visible = request_json(ORIGINAL_RPC, {'p_action': 'visible', 'p_query': json.dumps(ids)},
                                   authorization=self.headers.get('Authorization', 'Bearer ' + ANON_KEY))
            by_id = {row['id']: row for row in visible['works']}
            rows = [by_id[work_id] for work_id in ids if work_id in by_id]
            if action == 'suggest':
                self.respond(200, {'suggestions': list(dict.fromkeys(row['title'] for row in rows))[:10]})
            else:
                self.respond(200, {'works': [{'id': row['id']} for row in rows[:20]]})
        except HTTPError as error:
            self.respond(error.code if error.code in (401, 403) else 503, {'error': 'search_unavailable'})
        except Exception as error:
            logging.error('Search request failed: %s', type(error).__name__)
            self.respond(503, {'error': 'search_unavailable'})

    def log_message(self, format, *args):
        logging.info('Search HTTP response %s', args[1] if len(args) > 1 else '')


if __name__ == '__main__':
    logging.basicConfig(level=logging.INFO, format='%(asctime)s %(levelname)s %(message)s')
    threading.Thread(target=synchronize, daemon=True).start()
    ThreadingHTTPServer(('127.0.0.1', 19201), Handler).serve_forever()
