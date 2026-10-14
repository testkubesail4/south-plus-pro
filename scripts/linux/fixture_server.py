"""Loopback-only synthetic forum for desktop integration tests."""
import argparse
import json
import re
import struct
import threading
import zlib
from functools import lru_cache
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

def home():
    lists = []
    for group, title in enumerate(['最新讨论', '最新回复', '热门主题', '求物区']):
        links = []
        for row in range(3):
            label = 'Fixture thread' if group == row == 0 else f'Fixture topic {group + 1}.{row + 1}'
            links.append(f'<a href="/read.php?tid-{900001 + group * 5 + row}.html">'
                         f'<b><font color="#FF00FF">{label}</font></b></a><br>')
        active = ' active' if group == 0 else ''
        lists.append(f'<div class="carousel-item{active}"><div>{title}</div>'
                     + ''.join(links) + '</div>')
    sections = []
    for section in range(3):
        rows = []
        for board in range(3):
            fid = 900 + section * 10 + board
            name = 'Fixture board' if section == board == 0 else f'Fixture board {section + 1}.{board + 1}'
            rows.append(f'''<tr><th><h3><a href="/thread.php?fid-{fid}.html">{name}</a></h3>
(2) Fixture board description 子版：<h3>
<a href="/thread.php?fid-{fid + 100}.html">Fixture child A</a>
<a href="/thread.php?fid-{fid + 200}.html">Fixture child B</a></h3></th>
<td>12 / 34</td><td>2026-01-01 12:00</td></tr>''')
        sections.append(f'<table><tr><th><h2>Fixture section {section + 1}</h2></th></tr>'
                        + ''.join(rows) + '</table>')
    return ('<!doctype html><html><head><meta charset="utf-8"></head><body>'
            + ''.join(lists + sections) + '</body></html>').encode('utf-8')


HOME = home()
THREAD = b'''<!doctype html><html><head><meta charset="utf-8"></head><body>
<h1 id="subject_tpc">Fixture thread</h1><div class="pages">Pages: 1/1</div>
<table class="js-post"><tr><th class="r_two"><a href="/u.php?action-show-uid-900001.html"><strong>Fixture author</strong></a></th>
<th class="r_one"><div class="tpc_content" id="read_900001">Fixture post body<br><img src="/fixture.png"></div></th></tr></table>
</body></html>'''


BOARD = '''<!doctype html><html><body>
<div id="breadcrumbs"><a href="/thread.php?fid-900.html">Fixture board</a></div>
<ul class="stream"><li class="dcsns-li">
<div class="section-title"><a href="/read.php?tid-900002.html"><b><font color="#FF00FF">Fixture highlighted title</font></b></a></div>
<div class="section-intro">Fixture author 2026-01-01</div>
<p>回复 / 人气: 1 / 20</p></li></ul><div class="pages">Pages: 1/1</div>
</body></html>'''.encode('utf-8')
COMPOSE = b'''<html><body><form method="post" action="/message.php">
<input name="action" value="write"><input name="step" value="2">
<input name="verify" value="synthetic123"><input name="touidmsg" value="900001">
<input name="msg_title" value="Fixture message"><textarea name="atc_content">Fixture message body</textarea>
</form></body></html>'''


@lru_cache(maxsize=42)
def image(width=320, height=180, color=b'\x36\x85\xb5'):
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', width, height, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress((b'\x00' + color * width) * height)) + chunk(b'IEND', b''))


PERF_DIMENSIONS = [(1600, 4000)] * 10 + [(1200, 900)] * 20 + [(300, 200)] * 10
PERF_REQUESTS = {}
PERF_LOCK = threading.Lock()


def performance_thread(page):
    posts = []
    for post in range((page - 1) * 17, min(page * 17, 50)):
        number = post if post < 40 else 0
        posts.append(f'''<table class="js-post"><tr>
<th class="r_two"><a href="/u.php?action-show-uid-900004.html"><strong>Fixture author</strong></a></th>
<th class="r_one"><div class="tpc_content" id="read_{910000 + post}">
Fixture performance page {page} post {post}<br><img src="/perf/image/{number}.png"></div></th>
</tr></table>''')
    return (f'''<html><body><h1 id="subject_tpc">Fixture performance thread</h1>
<div class="pages">Pages: {page}/3
<a href="/read.php?tid-900004-page-1.html">1</a>
<a href="/read.php?tid-900004-page-2.html">2</a>
<a href="/read.php?tid-900004-page-3.html">3</a></div>'''
            + ''.join(posts) + '</body></html>').encode('utf-8')


class FixtureHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlsplit(self.path).path
        if path == '/perf/stats':
            with PERF_LOCK:
                payload = json.dumps(PERF_REQUESTS).encode('utf-8')
            self.send_body(payload, 'application/json')
            return
        match = re.fullmatch(r'/perf/image/(\d+)\.png', path)
        if match and int(match[1]) < len(PERF_DIMENSIONS):
            number = int(match[1])
            width, height = PERF_DIMENSIONS[number]
            body = image(width, height, bytes((54 + number, 133, 181)))
            with PERF_LOCK:
                stats = PERF_REQUESTS.setdefault(path, {'count': 0, 'bytes': 0})
                stats['count'] += 1
                stats['bytes'] += len(body)
            self.send_body(body, 'image/png')
            return
        if path == '/read.php' and 'tid-900004' in self.path:
            match = re.search(r'-page-(\d+)', self.path)
            page = int(match[1]) if match else 1
            if 1 <= page <= 3:
                self.send_body(performance_thread(page), 'text/html; charset=utf-8')
            else:
                self.send_error(404)
            return
        routes = {'/simple/index.php': (HOME, 'text/html; charset=utf-8'),
                  '/index.php': (HOME, 'text/html; charset=utf-8'),
                  '/read.php': (THREAD, 'text/html; charset=utf-8'),
                  '/thread_new.php': (BOARD, 'text/html; charset=utf-8'),
                  '/message.php': (COMPOSE, 'text/html; charset=utf-8'),
                  '/fixture.png': (image(), 'image/png'),
                  '/portrait.png': (image(240, 480), 'image/png')}
        if path not in routes:
            self.send_error(404)
            return
        body, content_type = routes[path]
        if path == '/read.php' and '900002' in self.path:
            body = THREAD.replace(b'/fixture.png', b'/portrait.png')
        self.send_body(body, content_type)

    def send_body(self, body, content_type):
        self.send_response(200)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass  # Requests can contain private data if someone mispoints a client.


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8765)
    args = parser.parse_args()
    ThreadingHTTPServer(('127.0.0.1', args.port), FixtureHandler).serve_forever()
