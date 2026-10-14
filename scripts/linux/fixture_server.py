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


def image():
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))
    width, height = 320, 180
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', width, height, 8, 2, 0, 0, 0))
            + chunk(b'IDAT', zlib.compress((b'\x00' + b'\x36\x85\xb5' * width) * height)) + chunk(b'IEND', b''))


class FixtureHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        path = urlsplit(self.path).path
        routes = {'/simple/index.php': (HOME, 'text/html; charset=utf-8'),
                  '/index.php': (HOME, 'text/html; charset=utf-8'),
                  '/read.php': (THREAD, 'text/html; charset=utf-8'),
                  '/fixture.png': (image(), 'image/png')}
        if path not in routes:
            self.send_error(404)
            return
        body, content_type = routes[path]
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
