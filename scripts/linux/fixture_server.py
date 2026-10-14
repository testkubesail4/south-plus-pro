"""Loopback-only synthetic forum for desktop integration tests."""
import argparse
import struct
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

HOME = b'''<!doctype html><html><head><meta charset="utf-8"></head><body>
<div class="carousel-item active"><a href="/read.php?tid-900001.html">Fixture thread</a></div>
<table><tr><th><h2>Fixture section</h2></th></tr>
<tr><th><h3><a href="/thread.php?fid-900.html">Fixture board</a></h3></th><td>1 / 1</td></tr></table>
</body></html>'''
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


def image(width=320, height=180):
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', width, height, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress((b'\x00' + b'\x36\x85\xb5' * width) * height)) + chunk(b'IEND', b''))


class FixtureHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlsplit(self.path).path
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
