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
                                   ('/fixture.png', b'\x89PNG\r\n\x1a\n')]:
                with urlopen(base + path) as response:
                    self.assertEqual(response.status, 200)
                    self.assertIn(expected, response.read())
            with self.assertRaises(HTTPError) as error:
                urlopen(base + '/unknown')
            self.assertEqual(error.exception.code, 404)
        finally:
            server.shutdown()
            worker.join()
            server.server_close()


if __name__ == '__main__':
    unittest.main()
