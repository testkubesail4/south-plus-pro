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

from fixture_server import APPENDFIX_COOKIE, FixtureHandler, image


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


def multipart(fields, upload=None):
    parts = []
    for name, value in fields:
        parts.append(f'--fixture-boundary\r\nContent-Disposition: form-data; name="{name}"\r\n\r\n{value}\r\n'.encode())
    if upload is not None:
        parts.append(b'--fixture-boundary\r\nContent-Disposition: form-data; name="upload"; filename="crop.png"\r\nContent-Type: image/png\r\n\r\n'
                     + upload + b'\r\n')
    return b''.join(parts) + b'--fixture-boundary--\r\n'


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

    def test_round_edit_requires_modify_and_preserves_settings_without_adding_posts(self):
        from fixture_server import round_edit_fields
        with appendfix_server() as (request, _):
            request('/round/reset', b'fixture-only')
            page = request('/read.php?tid-950001-page-1.html').decode()
            self.assertIn('<a name="tpc"></a><div class="t5 t2"><table', page)
            page2 = request('/read.php?tid-950001-page-2.html').decode()
            self.assertEqual(page2.count('action-modify-'), 1)
            self.assertEqual(page2.count('class="js-post"'), 2)
            self.assertIn('<i>Reply original</i>', page2)
            self.assertNotIn('[i]Reply original[/i]', page2)
            edit = '/post.php?action-modify-fid-950-tid-950001-pid-950102-article-2.html'
            form = request(edit)
            self.assertIn(b'[i]Reply original[/i] [s:716]', form)
            self.assertNotIn(b'[s:716]', page2.encode())
            fields = dict(round_edit_fields('950102'), atc_title='Synthetic title', atc_content='Edited body')
            for invalid in [dict(fields, action='reply'), dict(fields, atc_money='0')]:
                with self.assertRaises(HTTPError) as error:
                    request('/post.php?', urlencode(invalid).encode())
                self.assertEqual(error.exception.code, 400)
            self.assertEqual(json.loads(request('/round/stats'))['edits'], [])
            ack = request('/post.php?', urlencode(fields).encode()).decode()
            self.assertIn('发帖完毕', ack)
            self.assertIn('http-equiv="refresh"', ack)
            self.assertIn('read.php?tid=950001&amp;page=2&amp;toread=1#950102', ack)
            self.assertNotIn('编辑成功', ack)
            refreshed = request('/read.php?tid-950001-page-2.html').decode()
            self.assertIn('Edited body', refreshed)
            self.assertNotIn('Reply original', refreshed)
            self.assertEqual(refreshed.count('class="js-post"'), 2)
            self.assertEqual(len(json.loads(request('/round/stats'))['edits']), 1)

    def test_round_edit_negative_feedback_keeps_original_body_and_next_submit_is_explicit(self):
        from fixture_server import round_edit_fields
        with appendfix_server() as (request, _):
            for feedback, marker in [('ambiguous', '提示信息'), ('rejected', '修改失败'),
                                     ('wrong-target', 'tid=950099'), ('external', 'https://example.invalid/')]:
                with self.subTest(feedback=feedback):
                    request('/round/reset', b'fixture-only')
                    request(f'/round/edit-{feedback}-next', b'fixture-only')
                    fields = dict(round_edit_fields('950102'), atc_title='Synthetic title', atc_content='Unsaved edit')
                    response = request('/post.php?', urlencode(fields).encode()).decode()
                    self.assertIn(marker, response)
                    if feedback in ('ambiguous', 'rejected'):
                        self.assertNotIn('http-equiv="refresh"', response)
                    state = json.loads(request('/round/stats'))
                    self.assertEqual(len(state['edit_attempts']), 1)
                    self.assertEqual(state['edits'], [])
                    self.assertEqual(state['post_bodies']['950102'], '[i]Reply original[/i] [s:716]')
                    request('/post.php?', urlencode(fields).encode())
                    state = json.loads(request('/round/stats'))
                    self.assertEqual(len(state['edit_attempts']), 2)
                    self.assertEqual(len(state['edits']), 1)
                    self.assertEqual(state['post_bodies']['950102'], 'Unsaved edit')

    def test_round_native_metadata_cells_and_explicit_truncated_list_variant(self):
        truncated = b'<html><body><div id="main">'
        with appendfix_server() as (request, _):
            request('/round/reset', b'fixture-only')
            for action in ('topic', 'post', 'favor', 'friend'):
                self.assertEqual(request(f'/u.php?action={action}.html'), truncated)
            path = '/u.php?action-topic-uid-950002.html'
            native = request(path).decode()
            self.assertIn('<span class="gray f9">[2025-01-02]</span></th><td>回复:0<br>浏览:0</td>', native)
            self.assertIn('Known low [1999-01-01] 浏览:999 回复:999</a>', native)
            request('/round/truncate-list-next', b'fixture-only')
            self.assertEqual(request(path), truncated)
            self.assertIn(b'class="u-table"', request(path))

    def test_round_scan_returns_requested_pages_with_mixed_known_unknown_metrics(self):
        from fixture_server import ROUND_SCAN_GATE
        with appendfix_server() as (request, _):
            request('/round/reset', b'fixture-only')
            first = request('/u.php?action-topic-uid-950002.html').decode()
            self.assertIn('Unknown metrics', first)
            self.assertIn('回复:0<br>浏览:0', first)
            self.assertNotIn('Unloaded maximum', first)
            result = []
            pending = threading.Thread(target=lambda: result.append(
                request('/u.php?action-topic-uid-950002-page-2.html')))
            pending.start()
            try:
                request('/round/release-scan', b'fixture-only')
                pending.join(timeout=5)
                self.assertFalse(pending.is_alive())
                self.assertIn(b'Unloaded maximum', result[0])
                self.assertEqual(json.loads(request('/round/stats'))['topic_pages'], [1, 2])
            finally:
                ROUND_SCAN_GATE.set()
                pending.join(timeout=5)

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

    def test_redesign_native_same_row_controls_and_complete_preferences(self):
        with appendfix_server() as (request, _):
            request('/account-redesign/reset', b'fixture-only')
            profile = request('/profile.php?action-modify.html').decode()
            avatar_row = next(row for row in profile.split('<tr>') if 'id="openchang"' in row).split('</tr>')[0]
            first_cell, panels = avatar_row.split('</td>', 1)
            self.assertIn('name="useravatars"', first_cell)
            self.assertNotIn('头像', first_cell)
            for panel in ('face1', 'face2', 'face3'):
                self.assertIn(f'id="{panel}"', panels)
            for field in ('facetype', 'proicon', 'httpurl[0]', 'httpurl[1]', 'httpurl[2]', 'upload', 'uploadurl[1]', 'uploadurl[2]'):
                self.assertIn(f'name="{field}"', panels)
            self.assertNotIn('accept=', panels)
            self.assertNotIn('MAX_FILE_SIZE', profile)
            self.assertIn('1 -- 150', panels)
            self.assertIn('1 -- 270', panels)
            preferences = request('/profile.php?action-bbsset-info_type-msg.html').decode()
            date_row = next(row for row in preferences.split('<tr>') if 'name="d_type"' in row).split('</tr>')[0]
            for field in ('d_type', 'date_f', 'time_f'):
                self.assertIn(f'name="{field}"', date_row)
            self.assertIn('dd:有前导零01-31', date_row)
            home = request('/index.php').decode()
            self.assertIn('fid-229.html">CM108', home)
            self.assertIn('fid-226.html">CM107', home)
            for child in ('230', '227'):
                self.assertIn(f'fid-{child}.html">同人志&amp;CG', home)

    def test_redesign_preferences_preserve_unedited_native_controls_by_fresh_readback(self):
        with appendfix_server() as (request, _):
            request('/account-redesign/reset', b'fixture-only')
            before = json.loads(request('/appendfix/stats'))['preferences']
            changed = dict(before, d_type='1', date_f='yy-m-d', time_f='12', banidinfo='930004')
            fields = [('verify', 'fixture-only'), ('step', '2'), ('msggroups[]', '6'), ('msggroups[]', '7')] + list(changed.items())
            response = request('/profile.php?action=bbsset', urlencode(fields).encode())
            self.assertEqual(response, b'<html><body>Fixture received</body></html>')
            fresh = request('/profile.php?action-bbsset-info_type-msg.html').decode()
            self.assertIn('name="date_f" value="yy-m-d"', fresh)
            self.assertIn('name="time_f" value="12" checked', fresh)
            stats = json.loads(request('/appendfix/stats'))
            self.assertEqual(stats['preferences'], changed)
            self.assertEqual(stats['writes'], ['bbsset'])
            self.assertEqual(len(stats['attempts']), 1)
            self.assertTrue(any(read['path'] == '/profile.php' for read in stats['reads']))

    def test_redesign_avatar_requires_upload_callback_before_final_icon_and_keeps_uploaded_bytes(self):
        with appendfix_server() as (request, _):
            request('/account-redesign/reset', b'fixture-only')
            fields = [('verify', 'fixture-only'), ('step', '2'), ('field_1', '本地读者'),
                      ('proemail', 'local@example.invalid'), ('prosign', 'preserved footer'),
                      ('facetype', '3'), ('proicon', 'none.gif'), ('uploadurl[1]', '150'), ('uploadurl[2]', '')]
            content_type = 'multipart/form-data; boundary=fixture-boundary'
            with self.assertRaises(HTTPError):
                request('/profile.php?action=ajaxface', multipart(fields), content_type)
            png = image(512, 512)
            callback = request('/profile.php?action=ajaxface', multipart(fields, png), content_type)
            self.assertEqual(callback, b'<script>parent.facepath("/images/", "upload/930001.png", "success");</script>')
            self.assertEqual(request('/account-redesign/upload'), png)
            self.assertEqual(json.loads(request('/appendfix/stats'))['writes'], [])
            final = [(key, 'upload/930001.png' if key == 'proicon' else value) for key, value in fields]
            request('/profile.php?action=modify&', multipart(final), content_type)
            stats = json.loads(request('/appendfix/stats'))
            self.assertEqual(stats['profile']['proicon'], 'upload/930001.png')
            self.assertEqual(stats['upload_metadata']['width'], 512, 'native width parameter is not a raster pixel cap')
            self.assertEqual(stats['profile']['uploadurl[2]'], '')
            self.assertEqual(stats['writes'], ['modify'])
            self.assertEqual([attempt['action'] for attempt in stats['attempts']], ['ajaxface', 'ajaxface', 'modify'])
            self.assertIn(b'upload/930001.png', request('/profile.php?action-modify.html'))
            request('/account-redesign/reject-upload')
            failed = request('/profile.php?action=ajaxface', multipart(final, image(120, 120)), content_type).decode()
            self.assertEqual(failed.count('<script>'), 13)
            self.assertIn("parent.facepath('','','上传附件失败，造成的原因可能有:附件目录不可写(777)、空间在安全模式下、空间大小已不足。','','');", failed)
            self.assertEqual(request('/account-redesign/upload'), png)
            rejected = json.loads(request('/appendfix/stats'))
            self.assertEqual(rejected['profile']['proicon'], 'upload/930001.png')
            self.assertEqual(rejected['writes'], ['modify'])
            self.assertEqual(len(rejected['attempts']), 4, 'failed upload is a raw request, not a successful mutation')

    def test_redesign_favorite_menu_is_read_only_until_exact_second_stage_for_both_labels(self):
        with appendfix_server() as (request, _):
            for contains_favorite_word in (False, True):
                with self.subTest(label_contains_favorite=contains_favorite_word):
                    request('/account-redesign/reset', b'fixture-only')
                    if contains_favorite_word:
                        request('/account-redesign/menu-with-favorite-word')
                    base = '/pw_ajax.php?action=favor&tid=930002&nowtime=123456&verify=fixture-only'
                    with self.assertRaises(HTTPError):
                        request(base.replace('/pw_ajax.php', '/job.php'))
                    first = request(base).decode()
                    self.assertIn('<?xml version="1.0" encoding="utf-8"?>', first)
                    self.assertIn('<div class="bor"><table cellspacing="0" cellpadding="5" width="120">', first)
                    self.assertIn('onmousedown="read.move(event);"', first)
                    self.assertIn('onclick="closep();"', first)
                    self.assertIn('onclick="favor(\'1\');return false;" href="javascript:"', first)
                    self.assertIn('收藏测试分类' if contains_favorite_word else 'SPP-repro-10', first)
                    self.assertNotIn('帖子收藏成功!', first)
                    before = json.loads(request('/appendfix/stats'))
                    self.assertEqual(before['favorites'], {})
                    self.assertEqual(before['writes'], [])
                    self.assertEqual(len(before['attempts']), 1)
                    # Cancelling is not a request: a fresh favorites GET remains empty.
                    self.assertNotIn(b'value="930002"', request('/u.php?action-favor.html'))
                    self.assertEqual(len(json.loads(request('/appendfix/stats'))['attempts']), 1)
                    second = request(base + '&type=1')
                    self.assertEqual(second, '<?xml version="1.0" encoding="utf-8"?><ajax><![CDATA[帖子收藏成功!]]></ajax>'.encode())
                    self.assertIn(b'value="930002"', request('/u.php?action=favor&type=1'))
                    self.assertNotIn(b'value="930002"', request('/u.php?action=favor&type=0'))
                    stats = json.loads(request('/appendfix/stats'))
                    self.assertEqual(stats['favorites'], {'930002': '1'})
                    self.assertEqual(stats['writes'], ['favor'])
                    self.assertEqual(len(stats['attempts']), 2)
                    again = request(base + '&type=1')
                    self.assertIn('您已经收藏了该主题'.encode(), again)
                    repeated = json.loads(request('/appendfix/stats'))
                    self.assertEqual(len(repeated['attempts']), 3)
                    self.assertEqual(repeated['writes'], ['favor'])

    def test_collections_native_sidebar_read_only_views_direct_add_and_default_safety(self):
        with appendfix_server() as (request, _):
            request('/favorite-collections/reset', b'fixture-only')
            body = request('/u.php?action=favor').decode()
            sidebar, main = body.split('<div id="u-contentmain">', 1)
            self.assertIn('id="u-fav-cate"', sidebar)
            self.assertIn('name="job" value="addtype"', sidebar)
            self.assertNotIn('maxlength=', sidebar)
            self.assertIn('name="type" size="6"', sidebar)
            self.assertIn('id="uf_all"', sidebar)
            self.assertIn('id="uf_forum"', sidebar)
            self.assertIn('name="job" value="change"', main)
            self.assertIn('name="job" value="clear"', main)
            self.assertIn('<th><a href="read.php?tid-940001.html">', main)
            self.assertIn('<td><a href="u.php?uid-930002.html">本地作者</a></td><td></td>', main)
            empty = request('/u.php?action=favor&type=2')
            self.assertIn(b'<table class="u-table">', empty)
            self.assertNotIn(b'name="selid[]"', empty)
            pretty = request('/u.php?action-favor-uid-930001-type-2.html')
            self.assertNotIn(b'<table class="u-table">', pretty)
            self.assertEqual(json.loads(request('/appendfix/stats'))['attempts'], [])
            path = '/pw_ajax.php?action=favor&tid=930002&type=2&verify=fixture-only'
            self.assertIn('非法请求，请返回重试!'.encode(), request(path))
            self.assertNotIn(b'value="930002"', request('/u.php?action=favor'))
            self.assertIn('帖子收藏成功!'.encode(), request(path + '&nowtime=123'))
            self.assertIn(b'value="930002"', request('/u.php?action=favor&type=2'))
            self.assertNotIn(b'value="930002"', request('/u.php?action=favor&type=0'))
            self.assertIn('您已经收藏了该主题'.encode(), request(path + '&nowtime=124'))
            with self.assertRaises(HTTPError) as error:
                request('/u.php?action=favor&', urlencode({'verify': 'fixture-only', 'job': 'deltype', 'type': '0'}).encode())
            self.assertEqual(error.exception.code, 403)
            stats = json.loads(request('/appendfix/stats'))
            self.assertEqual(len(stats['attempts']), 4, 'invalid and idempotent raw attempts count too')
            self.assertEqual(stats['writes'], ['favor'])
            self.assertEqual(stats['categories'][0], {'id': '0', 'label': '默认分类'})
            self.assertIn('操作完成'.encode(), request('/u.php?action-favor-job-deltype-type-2-uid-930001-verify-fixture-only.html'))
            self.assertIn(b'value="930002"', request('/u.php?action=favor&type=0'))
            after_link = json.loads(request('/appendfix/stats'))
            self.assertEqual(after_link['attempts'][-1]['method'], 'GET')
            self.assertEqual(after_link['writes'], ['favor', 'deltype'])

    def test_collections_create_delete_renumbers_ids_and_preserves_nonempty_favorites(self):
        with appendfix_server() as (request, _):
            request('/favorite-collections/reset', b'fixture-only')
            name = '超过六个字符的收藏分类'
            created = request('/u.php?action=favor&', urlencode({'verify': 'fixture-only', 'job': 'addtype', 'type': name}).encode())
            self.assertIn('操作完成'.encode(), created)
            self.assertIn(f'id="uf_3"'.encode(), request('/u.php?action=favor'))
            self.assertIn(name.encode(), request('/u.php?action=favor'))
            request('/pw_ajax.php?action=favor&tid=930002&type=3&verify=fixture-only&nowtime=123')
            request('/favorite-collections/external-delete-first', b'fixture-only')
            shifted = request('/u.php?action=favor').decode()
            self.assertIn('type-1.html">长期收藏', shifted)
            self.assertIn(f'type-2.html">{name}', shifted)
            self.assertIn(b'value="940003"', request('/u.php?action=favor&type=0'))
            moved = request('/u.php?action=favor&', urlencode([
                ('verify', 'fixture-only'), ('job', 'change'), ('type', '1'), ('selid[]', '940001')]).encode())
            self.assertEqual(moved, created, 'same native ACK cannot identify what operation succeeded')
            self.assertIn(b'value="940001"', request('/u.php?action=favor&type=1'))
            self.assertNotIn(b'value="940001"', request('/u.php?action=favor&type=2'))
            deleted = request('/u.php?action=favor&', urlencode({'verify': 'fixture-only', 'job': 'deltype', 'type': '2'}).encode())
            self.assertEqual(deleted, created)
            self.assertIn(b'value="930002"', request('/u.php?action=favor&type=0'))
            final = json.loads(request('/appendfix/stats'))
            self.assertEqual(final['categories'], [{'id': '0', 'label': '默认分类'}, {'id': '1', 'label': '长期收藏'}])
            self.assertEqual(set(final['favorites']), {'940001', '940002', '940003', '930002'})
            self.assertEqual(final['favorites']['940001'], '1')
            self.assertEqual(final['writes'], ['addtype', 'favor', 'change', 'deltype'])
            self.assertEqual(len(final['attempts']), 4)
            self.assertEqual(final['external_events'], [{'job': 'deltype', 'label': '待整理'}])

    def test_collections_batch_partial_unknown_reply_and_loaded_page_boundaries(self):
        with appendfix_server() as (request, _):
            request('/favorite-collections/reset', b'fixture-only')
            fields = [('verify', 'fixture-only'), ('job', 'change'), ('type', '2'),
                      ('selid[]', '940001'), ('selid[]', '940002')]
            request('/favorite-collections/partial-next', b'fixture-only')
            partial = request('/u.php?action=favor&', urlencode(fields).encode())
            self.assertIn('操作完成'.encode(), partial)
            self.assertIn(b'value="940001"', request('/u.php?action=favor&type=2'))
            self.assertNotIn(b'value="940002"', request('/u.php?action=favor&type=2'))
            self.assertIn(b'value="940002"', request('/u.php?action=favor&type=0'))
            request('/favorite-collections/unknown-ack-next', b'fixture-only')
            unknown = request('/u.php?action=favor&', urlencode(fields[:3] + [('selid[]', '940002')]).encode())
            self.assertEqual(unknown, b'<html><body>Fixture received</body></html>')
            self.assertIn(b'value="940002"', request('/u.php?action=favor&type=2'))
            self.assertEqual(json.loads(request('/appendfix/stats'))['attempts'][0]['fields']['selid[]'], ['940001', '940002'])

            request('/favorite-collections/paged-reset', b'fixture-only')
            page1 = request('/u.php?action=favor&type=0')
            self.assertIn(b'Pages: 1/2', page1)
            self.assertNotIn(b'value="940005"', page1)
            self.assertIn(b'value="940005"', request('/u.php?action=favor&type=0&page=2'))
            loaded = [str(940000 + number) for number in range(1, 5)]
            request('/u.php?action=favor&', urlencode(fields[:3] + [('selid[]', tid) for tid in loaded]).encode())
            self.assertIn(b'value="940005"', request('/u.php?action=favor&type=0'))
            request('/u.php?action=favor&', urlencode([
                ('verify', 'fixture-only'), ('job', 'clear'), ('type', '0'), ('selid[]', '940005')]).encode())
            self.assertIn(b'Pages: 1/2', request('/u.php?action=favor'))
            empty = request('/u.php?action=favor&type=0')
            self.assertIn(b'Pages: 1/1', empty)
            self.assertNotIn(b'name="selid[]"', empty)
            self.assertIn(b'value="940006"', request('/u.php?action=favor&page=2'))
            final = json.loads(request('/appendfix/stats'))
            self.assertEqual(final['attempts'][0]['fields']['selid[]'], loaded)
            self.assertEqual(final['attempts'][1]['fields']['selid[]'], ['940005'])
            self.assertNotIn('940005', final['favorites'])
            self.assertEqual(final['writes'], ['change', 'clear'])

    def test_profile_board_filter_joins_flat_allowed_fids_to_home_parentage_without_writes(self):
        with appendfix_server() as (request, _):
            request('/profile-board-tree/reset', b'fixture-only')
            search = request('/search.php').decode()
            self.assertIn('<option value="8" disabled>&gt;&gt; 同人展会</option>', search)
            for fid, label in [('229', 'CM108'), ('230', '同人志&amp;CG'),
                               ('226', 'CM107'), ('227', '同人志&amp;CG')]:
                self.assertIn(f'<option value="{fid}">|- {label}</option>', search)
            self.assertNotIn('|-|-', search, 'the fixture must not fabricate already-nested search options')
            self.assertNotIn('value="239"', search)
            home = request('/index.php').decode()
            cm108 = next(row for row in home.split('<tr>') if 'fid-229.html' in row).split('</tr>')[0]
            cm107 = next(row for row in home.split('<tr>') if 'fid-226.html' in row).split('</tr>')[0]
            self.assertIn('fid-230.html', cm108)
            self.assertIn('fid-239.html', cm108, 'home-only boards are not authorized search filters')
            self.assertNotIn('fid-227.html', cm108)
            self.assertIn('fid-227.html', cm107)
            for tab, kind in [('topic', '主题'), ('post', '回复')]:
                page = request(f'/u.php?action-{tab}-uid-930002.html').decode()
                for fid, title in [('229', f'CM108 父版{kind}'), ('230', f'CM108 子版{kind}'),
                                   ('226', f'CM107 父版{kind}'), ('227', f'CM107 子版{kind}')]:
                    self.assertIn(title, page)
                    self.assertIn(f'fid-{fid}.html', page)
                self.assertNotIn('fid-239.html', page)
            stats = json.loads(request('/appendfix/stats'))
            self.assertEqual(stats['attempts'], [])
            self.assertEqual(stats['writes'], [])
            request('/account-redesign/reset', b'fixture-only')
            self.assertNotIn(b'value="229"', request('/search.php'))
            self.assertNotIn('未授权子版', request('/index.php').decode())

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
