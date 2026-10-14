import json
import struct
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import urlopen
from http.server import ThreadingHTTPServer

from fixture_server import FixtureHandler


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


if __name__ == '__main__':
    unittest.main()
