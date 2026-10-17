from contextlib import contextmanager
from http.client import HTTPConnection
import json
import socket
import struct
import threading
import unittest
from urllib.error import HTTPError
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from http.server import ThreadingHTTPServer

from fixture_server import APPENDFIX_COOKIE, FixtureHandler


@contextmanager
def appendfix_server():
    server = ThreadingHTTPServer(('127.0.0.1', 0), FixtureHandler)
    worker = threading.Thread(target=server.serve_forever)
    worker.start()
    base = f'http://127.0.0.1:{server.server_port}'

    def request(path, data=None, content_type='application/x-www-form-urlencoded', cookie=APPENDFIX_COOKIE):
        headers = {'Content-Type': content_type, 'Cookie': cookie}
        with urlopen(Request(base + path, data=data, headers=headers), timeout=5) as response:
            return response.read()

    try:
        request('/appendfix/reset', b'fixture-only')
        yield request, server.server_port
    finally:
        server.shutdown()
        worker.join()
        server.server_close()


class FixtureServerTest(unittest.TestCase):
    def test_serves_synthetic_pages_and_rejects_unknown_routes(self):
        server = ThreadingHTTPServer(('127.0.0.1', 0), FixtureHandler)
        worker = threading.Thread(target=server.serve_forever)
        worker.start()
        base = f'http://127.0.0.1:{server.server_port}'
        try:
            for path, expected in [('/simple/index.php', b'Fixture thread'),
                                   ('/index.php', b'Fixture board'),
                                   ('/read.php?tid-900001.html', b'Fixture post body'),
                                   ('/thread_new.php?fid-900.html', b'#FF00FF'),
                                   ('/message.php?action-write.html', b'Fixture message'),
                                   ('/fixture.png', b'\x89PNG\r\n\x1a\n')]:
                with urlopen(base + path) as response:
                    self.assertEqual(response.status, 200)
                    self.assertIn(expected, response.read())
            with urlopen(base + '/perf/stats') as response:
                before = json.load(response).get('/perf/image/0.png', {'count': 0, 'bytes': 0})
            for _ in range(2):
                with urlopen(base + '/perf/image/0.png') as response:
                    png = response.read()
                    self.assertEqual(struct.unpack('!2I', png[16:24]), (1600, 4000))
            with urlopen(base + '/perf/stats') as response:
                after = json.load(response)['/perf/image/0.png']
            self.assertEqual(after['count'] - before['count'], 2)
            self.assertEqual(after['bytes'] - before['bytes'], 2 * len(png))
            for page, count in [(1, 17), (2, 17), (3, 16)]:
                with urlopen(base + f'/read.php?tid-900004-page-{page}.html') as response:
                    self.assertEqual(response.read().count(b'class="js-post"'), count)
            with self.assertRaises(HTTPError) as error:
                urlopen(base + '/unknown')
            self.assertEqual(error.exception.code, 404)
        finally:
            server.shutdown()
            worker.join()
            server.server_close()

    def test_appendfix_purchase_requires_exact_local_contract_and_cannot_repeat(self):
        with appendfix_server() as (request, _):
            before = request('/read.php?tid-930001.html')
            self.assertIn(b'type="button"', before)
            path = '/job.php?action=buytopic&tid=930001&pid=tpc&verify=fixture-only'
            for invalid in [path.replace('fixture-only', 'wrong'), path + '&tid=930002']:
                with self.assertRaises(HTTPError) as error:
                    request(invalid)
                self.assertEqual(error.exception.code, 400)
            self.assertEqual(json.loads(request('/appendfix/stats'))['purchases'], 0)
            self.assertIn('购买成功'.encode(), request(path))
            after = request('/read.php?tid-930001.html')
            self.assertNotIn(b'type="button"', after)
            for marker in ['已解锁的阅读笔记', '嵌套引用仍可阅读', 'local_example = 42', '表格里的阅读记录']:
                self.assertIn(marker.encode(), after)
            with self.assertRaises(HTTPError) as error:
                request(path)
            self.assertEqual(error.exception.code, 409)
            self.assertEqual(json.loads(request('/appendfix/stats'))['purchases'], 1)
            request('/thread_new.php?fid-930-page-2.html')
            self.assertEqual(json.loads(request('/appendfix/stats'))['board_pages'], [2])

    def test_appendfix_forms_validate_then_persist_for_readback_without_fake_ack(self):
        with appendfix_server() as (request, _):
            fields = [('verify', 'fixture-only'), ('step', '2'), ('msggroups[]', '6'),
                      ('msggroups[]', '7'), ('banidinfo', '930003, 930004')]
            payload = urlencode(fields).encode()
            for invalid, cookie in [(payload, ''), (payload.replace(b'fixture-only', b'wrong'), APPENDFIX_COOKIE)]:
                with self.assertRaises(HTTPError):
                    request('/profile.php?action=bbsset', invalid, cookie=cookie)
            self.assertEqual(json.loads(request('/appendfix/stats'))['writes'], [])
            response = request('/profile.php?action=bbsset', payload)
            self.assertEqual(response, b'<html><body>Fixture received</body></html>')
            self.assertIn(b'930003, 930004', request('/profile.php?action-bbsset-info_type-msg.html'))
            parts = []
            for name, value in [('verify', 'fixture-only'), ('step', '2'), ('field_1', '林间读者'),
                                ('proemail', 'local@example.invalid'), ('prosign', 'preserved footer')]:
                parts.append(f'--fixture-boundary\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n')
            multipart = (''.join(parts) + '--fixture-boundary--\r\n').encode()
            request('/profile.php?action=modify&', multipart, 'multipart/form-data; boundary=fixture-boundary')
            self.assertIn('林间读者'.encode(), request('/profile.php?action-modify.html'))
            stats = json.loads(request('/appendfix/stats'))
            self.assertEqual(stats['writes'], ['bbsset', 'modify'])
            self.assertNotIn('930003', json.dumps(stats), 'artifact stats contain actions, never form values')

    def test_appendfix_post_accepts_chunked_and_eof_bodies_without_content_length(self):
        with appendfix_server() as (request, port):
            payload = urlencode([('verify', 'fixture-only'), ('step', '2'),
                                 ('msggroups[]', '6'), ('msggroups[]', '7'),
                                 ('banidinfo', '930007')]).encode()
            headers = {'Content-Type': 'application/x-www-form-urlencoded',
                       'Cookie': APPENDFIX_COOKIE, 'Connection': 'close'}
            for chunked in (True, False):
                with self.subTest(framing='chunked' if chunked else 'eof'):
                    request('/appendfix/reset', b'fixture-only')
                    connection = HTTPConnection('127.0.0.1', port, timeout=5)
                    try:
                        if chunked:
                            connection.request('POST', '/profile.php?action=bbsset',
                                               body=iter([payload[:11], payload[11:]]),
                                               headers=headers, encode_chunked=True)
                        else:
                            connection.putrequest('POST', '/profile.php?action=bbsset')
                            for key, value in headers.items():
                                connection.putheader(key, value)
                            connection.endheaders(payload)
                            connection.sock.shutdown(socket.SHUT_WR)
                        with connection.getresponse() as response:
                            self.assertEqual(response.status, 200)
                            response.read()
                    finally:
                        connection.close()
                    self.assertIn(b'930007', request('/profile.php?action-bbsset-info_type-msg.html'))
                    self.assertEqual(json.loads(request('/appendfix/stats'))['writes'], ['bbsset'])

            request('/appendfix/reset', b'fixture-only')
            for raw, expected in [(b'invalid\r\n', 400), (b'100001\r\n', 413), (b'3\r\nx', 400)]:
                with self.subTest(chunk=raw):
                    connection = HTTPConnection('127.0.0.1', port, timeout=5)
                    try:
                        connection.putrequest('POST', '/profile.php?action=bbsset')
                        for key, value in headers.items():
                            connection.putheader(key, value)
                        connection.putheader('Transfer-Encoding', 'chunked')
                        connection.endheaders(raw)
                        connection.sock.shutdown(socket.SHUT_WR)
                        with connection.getresponse() as response:
                            self.assertEqual(response.status, expected)
                            response.read()
                    finally:
                        connection.close()
            self.assertEqual(json.loads(request('/appendfix/stats'))['writes'], [])


if __name__ == '__main__':
    unittest.main()
