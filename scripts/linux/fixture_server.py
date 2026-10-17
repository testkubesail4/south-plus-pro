"""Loopback-only synthetic forum for desktop integration tests."""
import argparse
from email import policy
from email.parser import BytesParser
from html import escape
import json
import re
import struct
import threading
import zlib
from functools import lru_cache
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

def home(rows=3, appendfix=False):
    lists = []
    for group, title in enumerate(['最新讨论', '最新回复', '热门主题', '求物区']):
        links = []
        for row in range(rows):
            label = 'Fixture thread' if group == row == 0 else f'Fixture topic {group + 1}.{row + 1}'
            tid = 900001 + group * 5 + row
            if appendfix:
                label = '付费阅读示例' if group == row == 0 else f'本地讨论 {group + 1}.{row + 1}'
                tid = 930001 + group * 10 + row
            links.append(f'<a href="/read.php?tid-{tid}.html">'
                         f'<b><font color="#FF00FF">{label}</font></b></a><br>')
        active = ' active' if group == 0 else ''
        lists.append(f'<div class="carousel-item{active}"><div>{title}</div>'
                     + ''.join(links) + '</div>')
    sections = []
    for section in range(3):
        rows = []
        for board in range(3):
            fid = (930 if appendfix else 900) + section * 10 + board
            name = 'Fixture board' if section == board == 0 else f'Fixture board {section + 1}.{board + 1}'
            if appendfix:
                name = '本地阅读版块' if section == board == 0 else f'本地版块 {section + 1}.{board + 1}'
            rows.append(f'''<tr><th><h3><a href="/thread.php?fid-{fid}.html">{name}</a></h3>
(2) Fixture board description 子版：<h3>
<a href="/thread.php?fid-{fid + 100}.html">Fixture child A</a>
<a href="/thread.php?fid-{fid + 200}.html">Fixture child B</a></h3></th>
<td>12 / 34</td><td>2026-01-01 12:00</td></tr>''')
        section_name = f'阅读分区 {section + 1}' if appendfix else f'Fixture section {section + 1}'
        sections.append(f'<table><tr><th><h2>{section_name}</h2></th></tr>'
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


APPENDFIX_COOKIE = 'appendfix_winduser=synthetic-local-only'
APPENDFIX_LOCK = threading.Lock()
APPENDFIX = {}
PINNED_TITLE = '置顶阅读指南：本地收藏、用户备注与长标题换行的完整阅读示例'
LONG_SIGNATURE = '认真阅读每一段文字，记录值得回看的讨论，只在本机保存备注，不向论坛公开个人笔记。'
IDENTITY = '''<div id="user-login"><a href="u.php">本地读者</a></div>
<div id="menu_profile"><div class="ul2"><a href="u.php?action-show-uid-930001.html">资料</a></div></div>
<div id="user_info"><a href="u.php"><img src="/fixture.png"></a></div>'''
APPENDFIX_HOME = home(8, appendfix=True).replace(b'</body>', IDENTITY.encode() + b'</body>')


def reset_appendfix():
    APPENDFIX.clear()
    APPENDFIX.update(blacklist='', nickname='本地读者', bought=False,
                     purchases=0, writes=[], board_pages=[])


reset_appendfix()


def appendfix_board(page):
    sticky = '' if page != 1 else f'''<table id="ajaxtable"><tr class="tr3">
<td><img src="images/file/headtopic_1.gif"><h3><a id="a_ajax_930002"
href="read.php?tid-930002.html"><b><font color="#FF00FF">{PINNED_TITLE}</font></b></a></h3>
<a class="bl" href="u.php?action-show-uid-930002.html">林间书签</a> 1 / 37 2026-01-03 09:20</td>
</tr></table>'''
    rows = ''.join(f'''<li class="dcsns-li"><div class="section-title">
<a href="read.php?tid-{931000 + page * 100 + row}.html">第 {page} 页讨论 {row + 1}</a></div>
<div class="section-intro"><a class="bl" href="u.php?action-show-uid-930002.html">林间书签</a>
2026-01-03 09:20</div><p>回复 / 人气: 2 / 37</p></li>''' for row in range(9))
    return f'''<html><body><div id="breadcrumbs"><a href="thread.php?fid-930.html">本地阅读版块</a></div>
{sticky}<ul class="stream">{rows}</ul><div class="pages">Pages: {page}/2
<a href="thread_new.php?fid-930-page-1.html">1</a>
<a href="thread_new.php?fid-930-page-2.html">2</a></div></body></html>'''.encode()


def appendfix_thread(tid):
    title = '付费阅读示例' if tid == '930001' else '本地阅读笔记'
    with APPENDFIX_LOCK:
        bought = APPENDFIX['bought']
    paid = '''<h6 class="quote jumbotron"><span>此帖售价 1 SP币,已有 3 人购买</span>
<input type="button" value="购买" onclick="location.href='job.php?action=buytopic&amp;tid=930001&amp;pid=tpc&amp;verify=fixture-only'"></h6>
<blockquote class="blockquote jumbotron">请确认本地测试购买</blockquote>'''
    if bought:
        paid = '''<h6 class="quote jumbotron">此帖售价 1 SP币,已有 4 人购买</h6>
<blockquote class="blockquote jumbotron"><p>已解锁的阅读笔记</p>
<blockquote>嵌套引用仍可阅读</blockquote><ul><li>清单里的第一条笔记</li></ul>
<pre class="blockquote2">local_example = 42</pre>
<table><tr><td>表格里的阅读记录</td></tr></table>
<a href="read.php?tid-930002.html">继续阅读本地主题</a><br><img src="/fixture.png"></blockquote>'''
    content = paid if tid == '930001' else '普通主题正文'
    return f'''<html><body><div id="breadcrumbs"><a href="thread.php?fid-930.html">本地阅读版块</a></div>
<h1 id="subject_tpc">{title}</h1><div class="pages">Pages: 1/1</div>
<table class="js-post"><tr><th class="r_two"><a href="u.php?action-show-uid-930002.html"><strong>林间书签</strong></a></th>
<th class="r_one"><div class="tiptop"><span class="fl"><span class="s3">楼主</span></span>
<span class="gray" title="2026-01-03 09:20">2026-01-03 09:20</span><span class="bianji">（{LONG_SIGNATURE}）</span></div>
<div class="tpc_content"><div id="read_tpc">{content}</div></div></th></tr></table></body></html>'''.encode()


def appendfix_profile(query):
    shell = '''<div id="u-top"><h1 class="u-h1">林间书签</h1><span id="honor">慢慢阅读，认真记录</span></div>
<div id="u-portrait"><img src="/fixture.png"></div><div id="u-sidebar"><img title="在线" src="/fixture.png"></div>
<table id="u-profile"><tr><td>UID</td><td>930002</td></tr></table>'''
    if 'action-topic-' in query or 'action-post-' in query:
        shell += '''<div id="u-contentmain"><table class="u-table"><tr><td><a href="read.php?tid-930002.html">本地阅读笔记</a>
<a href="thread.php?fid-930.html">本地阅读版块</a> [2026-01-03] 回复 2 浏览 37</td></tr>
<tr><td><a href="read.php?tid-930099.html">尚未确认分类的阅读记录</a>
<a href="thread.php?fid-930.html">本地阅读版块</a> [2026-01-02]</td></tr></table><div class="pages">Pages: 1/1</div></div>'''
    return f'<html><body>{shell}</body></html>'.encode()


def appendfix_account(profile):
    with APPENDFIX_LOCK:
        value = escape(APPENDFIX['nickname' if profile else 'blacklist'], quote=True)
    if profile:
        # Native form shape observed read-only; no native save/upload ACK was observed.
        body = f'''<form method="post" action="profile.php?action=modify&amp;" enctype="multipart/form-data">
<input name="verify" type="hidden" value="fixture-only"><input name="step" type="hidden" value="2">
<input name="proemail" value="local@example.invalid"><textarea name="prosign">preserved footer</textarea>
<table><tr><td>昵称</td><td><input name="field_1" value="{value}" maxlength="20"></td></tr>
<tr><td>头像类型</td><td><label><input name="facetype" type="radio" value="1" checked>系统头像</label>
<label><input name="facetype" type="radio" value="3">上传头像</label></td></tr>
<tr><td>头像</td><td><input name="proicon" type="hidden" value="none.gif"><input name="upload" type="file" accept="image/png"></td></tr>
<tr><td>个人签名</td><td><input name="prohonor" value="本地签名"></td></tr></table></form>'''
    else:
        body = f'''<form method="post" action="profile.php?action=bbsset">
<input name="verify" type="hidden" value="fixture-only"><input name="step" type="hidden" value="2">
<table><tr><td>屏蔽用户组</td><td><label><input name="msggroups[]" type="checkbox" value="6" checked>普通会员</label>
<label><input name="msggroups[]" type="checkbox" value="7" checked>正式会员</label></td></tr>
<tr><td>短消息黑名单</td><td><textarea name="banidinfo">{value}</textarea></td></tr>
<tr><td>好友验证</td><td><label><input name="friendcheck" type="radio" value="0" checked>直接添加</label>
<label><input name="friendcheck" type="radio" value="1">需要验证</label></td></tr>
<tr><td>编辑器</td><td><label><input name="editor" type="radio" value="1" checked>可视化</label>
<label><input name="editor" type="radio" value="0">代码</label></td></tr></table></form>'''
    return f'<html><body>{body}</body></html>'.encode()


class FixtureHandler(BaseHTTPRequestHandler):
    @property
    def appendfix(self):
        return APPENDFIX_COOKIE in self.headers.get('Cookie', '').split('; ')

    def _read_post_body(self):
        limit = 1024 * 1024
        self.connection.settimeout(5)
        lengths = self.headers.get_all('Content-Length', [])
        transfers = self.headers.get_all('Transfer-Encoding', [])
        if len(lengths) > 1 or len(transfers) > 1 or lengths and transfers:
            raise ValueError('Ambiguous body framing')
        if transfers:
            if transfers[0].strip().lower() != 'chunked':
                raise ValueError('Unsupported transfer coding')
            body = bytearray()
            while True:
                line = self.rfile.readline(128)
                size = line.split(b';', 1)[0].strip()
                if not line.endswith(b'\r\n') or not re.fullmatch(rb'[0-9a-fA-F]{1,16}', size):
                    raise ValueError('Invalid chunk size')
                length = int(size, 16)
                if len(body) + length > limit:
                    raise OverflowError('Body too large')
                if length == 0:
                    trailer_bytes = 0
                    while True:
                        line = self.rfile.readline(8193)
                        trailer_bytes += len(line)
                        if trailer_bytes > 8192 or not line.endswith(b'\r\n'):
                            raise ValueError('Invalid chunk trailer')
                        if line == b'\r\n':
                            return bytes(body)
                chunk = self.rfile.read(length)
                if len(chunk) != length or self.rfile.read(2) != b'\r\n':
                    raise ValueError('Incomplete chunk')
                body.extend(chunk)
        if lengths:
            if not re.fullmatch(r'\d{1,8}', lengths[0]):
                raise ValueError('Invalid content length')
            length = int(lengths[0])
            if length > limit:
                raise OverflowError('Body too large')
            body = self.rfile.read(length)
            if len(body) != length:
                raise ValueError('Incomplete body')
            return body
        # Legacy close-delimited senders must half-close their request stream.
        self.close_connection = True
        body = self.rfile.read(limit + 1)
        if len(body) > limit:
            raise OverflowError('Body too large')
        return body

    def do_POST(self):
        path = urlsplit(self.path)
        try:
            raw = self._read_post_body()
        except OverflowError:
            self.send_error(413)
            return
        except (ValueError, TimeoutError):
            self.send_error(400)
            return
        if path.path == '/appendfix/reset' and raw == b'fixture-only':
            with APPENDFIX_LOCK:
                reset_appendfix()
            self.send_body(b'{}', 'application/json')
            return
        action = parse_qs(path.query).get('action', [''])[0]
        if not self.appendfix or path.path != '/profile.php' or action not in ('bbsset', 'modify'):
            self.send_error(403)
            return
        if parse_qs(path.query) != {'action': [action]}:
            self.send_error(400)
            return
        if action == 'bbsset' and self.headers.get_content_type() != 'application/x-www-form-urlencoded':
            self.send_error(415)
            return
        if action == 'modify':
            message = BytesParser(policy=policy.default).parsebytes(
                b'Content-Type: ' + self.headers.get('Content-Type', '').encode() + b'\r\n\r\n' + raw)
            if not message.is_multipart():
                self.send_error(415)
                return
            fields = {}
            for part in message.iter_parts():
                name = part.get_param('name', header='content-disposition')
                if part.get_filename() is not None:
                    if part.get_payload(decode=True):
                        self.send_error(400)  # Upload callback is deliberately not simulated.
                        return
                    continue
                fields.setdefault(name, []).append(part.get_payload(decode=True).decode('utf-8'))
        else:
            fields = parse_qs(raw.decode('utf-8'), keep_blank_values=True)
        key = 'field_1' if action == 'modify' else 'banidinfo'
        valid = fields.get('verify') == ['fixture-only'] and fields.get('step') == ['2']
        valid = valid and len(fields.get(key, [])) == 1
        if action == 'bbsset':
            valid = valid and fields.get('msggroups[]') == ['6', '7']
            valid = valid and bool(re.fullmatch(r'(?:[1-9]\d*(?:,\s*[1-9]\d*)*)?', fields.get(key, [''])[0]))
        else:
            valid = valid and fields.get('proemail') == ['local@example.invalid']
            valid = valid and fields.get('prosign') == ['preserved footer']
        if not valid:
            self.send_error(400)
            return
        with APPENDFIX_LOCK:
            APPENDFIX['nickname' if action == 'modify' else 'blacklist'] = fields[key][0]
            APPENDFIX['writes'].append(action)
        # Unknown ACK intentionally forces the real service to confirm by GET readback.
        self.send_body(b'<html><body>Fixture received</body></html>', 'text/html; charset=utf-8')

    def do_GET(self):
        path = urlsplit(self.path).path
        query = urlsplit(self.path).query
        if path == '/appendfix/stats':
            with APPENDFIX_LOCK:
                stats = {k: APPENDFIX[k] for k in ('purchases', 'writes', 'board_pages')}
                body = json.dumps(stats).encode()
            self.send_body(body, 'application/json')
            return
        if self.appendfix:
            body = None
            if path in ('/index.php', '/simple/index.php'):
                body = APPENDFIX_HOME
            elif path in ('/thread.php', '/thread_new.php') and 'fid-930' in query:
                match = re.search(r'-page-(\d+)', query)
                page = int(match[1]) if match else 1
                if page not in (1, 2):
                    self.send_error(404)
                    return
                if path == '/thread_new.php':
                    with APPENDFIX_LOCK:
                        APPENDFIX['board_pages'].append(page)
                    body = appendfix_board(page)
                else:
                    body = '''<html><body><div class="hthread"><div class="threadlist">
<a href="thread.php?fid-930.html">全部</a><a href="thread.php?fid-930-type-1.html">阅读笔记</a>
</div></div><table id="ajaxtable"><tr class="tr3"><td><h3><a href="read.php?tid-930002.html">本地阅读笔记</a></h3>
<a href="thread.php?fid-930-type-1.html">阅读笔记</a></td></tr></table></body></html>'''.encode()
            elif path == '/read.php' and re.search(r'tid-(?:930\d+|931\d+)', query):
                body = appendfix_thread(re.search(r'tid-(\d+)', query)[1])
            elif path == '/u.php':
                body = appendfix_profile(query)
            elif path == '/search.php':
                body = '<html><body><form action="search.php"><select name="f_fid"><option value="930">本地阅读版块</option></select></form></body></html>'.encode()
            elif path == '/profile.php':
                body = appendfix_account('modify' in query)
            elif path == '/plugin.php':
                body = '<html><body>没有任务</body></html>'.encode()
                if 'actions-' not in query:
                    body = '''<html><body><table><tr><td><b>每日阅读奖励</b> (人气:37) 任务时效 2026-01-01 ~ 2027-01-01
奖励: 2 SP币 上次领取未超过 24 小时</td></tr><tr><td>本地测试，禁止领取</td></tr>
<tr><td><b>尚未确认的任务</b> (人气:4) 任务时效 2026-01-01 ~ 2027-01-01 奖励: 1 SP币</td></tr>
<tr><td>状态需要刷新</td></tr></table></body></html>'''.encode()
            elif path == '/job.php':
                if parse_qs(query) != {'action': ['buytopic'], 'tid': ['930001'], 'pid': ['tpc'], 'verify': ['fixture-only']}:
                    self.send_error(400)
                    return
                with APPENDFIX_LOCK:
                    if APPENDFIX['bought']:
                        self.send_error(409)
                        return
                    APPENDFIX['bought'] = True
                    APPENDFIX['purchases'] += 1
                body = '<html><body>购买成功</body></html>'.encode()
            if body is not None:
                self.send_body(body, 'text/html; charset=utf-8')
                return
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
