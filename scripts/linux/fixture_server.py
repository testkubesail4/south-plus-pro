"""Loopback-only synthetic forum for desktop integration tests."""
import argparse
from email import policy
from email.parser import BytesParser
from html import escape
import hashlib
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
ROUND_SCAN_GATE = threading.Event()
PINNED_TITLE = '置顶阅读指南：本地收藏、用户备注与长标题换行的完整阅读示例'
LONG_SIGNATURE = '认真阅读每一段文字，记录值得回看的讨论，只在本机保存备注，不向论坛公开个人笔记。'
IDENTITY = '''<div id="user-login"><a href="u.php">本地读者</a></div>
<div id="menu_profile"><div class="ul2"><a href="u.php?action-show-uid-930001.html">资料</a></div></div>
<div id="user_info"><a href="u.php"><img src="/fixture.png"></a></div>'''
APPENDFIX_HOME = home(8, appendfix=True).replace(b'</body>', IDENTITY.encode() + b'</body>')


def reset_appendfix(redesign=False, profile_boards=False, collections=False, paged=False):
    APPENDFIX.clear()
    APPENDFIX.update(blacklist='', nickname='本地读者', bought=False,
                     purchases=0, writes=[], board_pages=[], redesign=redesign,
                     profile_boards=profile_boards, collections=collections,
                     attempts=[], reads=[], upload=None, pending_icon=None, reject_upload=False,
                     favorites={}, categories=['默认分类', 'SPP-repro-10'],
                     page_size=4 if collections else 50, external_events=[], partial_next=False,
                     unknown_ack_next=False, favorite_menu_label='SPP-repro-10',
                     round=False, edits=[], thread_pages=[], thread_reads=[], topic_pages=[], scan_waiting=False,
                     post_bodies={'950101': '[b]Opening original[/b]', '950102': '[i]Reply original[/i]'},
                     preferences=dict(tpskin='', editor='0', timedf='0', d_type='0',
                                      date_f='yyyy-mm-dd', time_f='24', t_num='0',
                                      p_num='0', proreceivemail='1', friendcheck='0',
                                      banidinfo=''),
                     profile={'facetype': '1', 'proicon': 'none.gif',
                              'httpurl[0]': '', 'httpurl[1]': '', 'httpurl[2]': '',
                              'uploadurl[1]': '', 'uploadurl[2]': ''})
    if collections:
        APPENDFIX['categories'] = ['默认分类', '待整理', '长期收藏']
        APPENDFIX['favorites'] = {'940001': '0', '940002': '0', '940003': '1'}
        if paged:
            APPENDFIX['favorites'] = {str(940000 + number): '0' for number in range(1, 6)}
            APPENDFIX['favorites']['940006'] = '2'


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
    favorite = ''
    if APPENDFIX['redesign']:
        favorite = "<script>var verifyhash = 'fixture-only';</script><a id=\"favor\">收藏</a>"
    return f'''<html><body>{favorite}<div id="breadcrumbs"><a href="thread.php?fid-930.html">本地阅读版块</a></div>
<h1 id="subject_tpc">{title}</h1><div class="pages">Pages: 1/1</div>
<table class="js-post"><tr><th class="r_two"><a href="u.php?action-show-uid-930002.html"><strong>林间书签</strong></a></th>
<th class="r_one"><div class="tiptop"><span class="fl"><span class="s3">楼主</span></span>
<span class="gray" title="2026-01-03 09:20">2026-01-03 09:20</span><span class="bianji">（{LONG_SIGNATURE}）</span></div>
<div class="tpc_content"><div id="read_tpc">{content}</div></div></th></tr></table></body></html>'''.encode()


def round_edit_fields(pid):
    return dict(step='2', action='modify', fid='950', tid='950001', pid=pid,
                article='0' if pid == '950101' else '2', special='0', verify='fixture-only',
                atc_iconid='2', atc_autourl='1', atc_usesign='1', atc_convert='1',
                atc_hide='1', atc_requireenhide='1', atc_requiresell='1',
                atc_rvrc='3', atc_money='7', atc_enhidetype='rvrc', atc_credittype='money',
                **{'keep[attachment]': 'synthetic-attachment', 'Submit': ' 提 交 '})


def round_edit_form(pid):
    fields = ''.join(
        f'<input type="checkbox" name="{key}" value="{value}" checked>' if key in
        ('atc_autourl', 'atc_usesign', 'atc_convert', 'atc_hide', 'atc_requireenhide', 'atc_requiresell')
        else f'<input type="submit" name="{key}" value="{value}">' if key == 'Submit'
        else f'<input type="hidden" name="{key}" value="{value}">'
        for key, value in round_edit_fields(pid).items())
    return f'''<html><body><form name="FORM" method="post" action="post.php?">
{fields}<input name="atc_title" value="Synthetic title">
<input type="checkbox" name="atc_anonymous" value="1">
<textarea name="atc_content">{escape(APPENDFIX['post_bodies'][pid])}</textarea>
</form></body></html>'''.encode()


def round_thread(page):
    def post(pid, floor, author, edit=False):
        op = floor == '楼主'
        anchor = 'tpc' if op else pid
        article = '0' if op else '2'
        link = (f'<a id="modify_{pid}" href="post.php?action-modify-fid-950-tid-950001-pid-{pid}-article-{article}.html">编辑</a>'
                if edit else '')
        body = APPENDFIX['post_bodies'].get(pid, 'Another author uneditable body')
        # Live topology: FORM > A[name] + DIV > TABLE, never A + TABLE.
        return f'''<a name="{anchor}"></a><div class="t5 t2"><table class="js-post"><tr>
<th class="r_two"><a href="u.php?action-show-uid-{'930001' if edit else '950002'}.html"><strong>{author}</strong></a></th>
<th class="r_one" id="td_{anchor}"><div class="tiptop"><span class="fl"><span class="s3">{floor}</span></span>
<span class="gray" title="2026-01-03 09:20">2026-01-03 09:20</span>{link}</div>
<div class="tpc_content"><div id="read_{anchor}">{escape(body)}</div></div></th></tr></table></div>'''
    posts = post('950101', '楼主', 'Synthetic self', True) if page == 1 else (
        post('950103', 'B1F', 'Synthetic other') + post('950102', 'B2F', 'Synthetic self', True))
    return f'''<html><body><h1 id="subject_tpc">Synthetic edit thread</h1>
<div id="breadcrumbs"><a href="thread.php?fid-950.html">Synthetic board</a></div>
<div class="pages">Pages: {page}/2<a href="read.php?tid-950001-page-1.html">1</a>
<a href="read.php?tid-950001-page-2.html">2</a></div><form name="read">{posts}</form></body></html>'''.encode()


def round_profile(page=None):
    shell = '''<div id="u-top"><h1 class="u-h1">Synthetic other</h1></div>
<div id="u-portrait"><img src="/fixture.png"></div>
<table id="u-profile"><tr><td>UID</td><td>950002</td></tr></table>'''
    if page is None:
        return f'<html><body>{shell}</body></html>'.encode()
    data = {1: [('950201', 'Known low', '2025-01-02', '回复 0 浏览 0'),
                ('950202', 'Unknown metrics', '2025-01-01', ''),
                ('950203', 'Known high', '2025-01-03', '回复 4 浏览 40')],
            2: [('950204', 'Unloaded maximum', '2025-02-01', '回复 9 浏览 90')],
            3: [('950205', 'Unloaded unknown', '2025-02-02', '')]}
    rows = ''.join(f'''<tr><td><a href="read.php?tid-{tid}.html">{title}</a>
<a href="thread.php?fid-950.html">Synthetic board</a> [{date}] {metrics}</td></tr>'''
                   for tid, title, date, metrics in data[page])
    return f'''<html><body>{shell}<div id="u-contentmain"><table class="u-table">{rows}</table>
<div class="pages">Pages: {page}/3<a href="u.php?action-topic-uid-950002-page-3.html">末页</a>
</div></div></body></html>'''.encode()


def appendfix_profile(query):
    shell = '''<div id="u-top"><h1 class="u-h1">林间书签</h1><span id="honor">慢慢阅读，认真记录</span></div>
<div id="u-portrait"><img src="/fixture.png"></div><div id="u-sidebar"><img title="在线" src="/fixture.png"></div>
<table id="u-profile"><tr><td>UID</td><td>930002</td></tr></table>'''
    if APPENDFIX['profile_boards'] and ('action-topic-' in query or 'action-post-' in query):
        kind = '主题' if 'action-topic-' in query else '回复'
        boards = [('229', 'CM108', 'CM108 父版'), ('230', '同人志&CG', 'CM108 子版'),
                  ('226', 'CM107', 'CM107 父版'), ('227', '同人志&CG', 'CM107 子版')]
        metrics = '回复:2<br>浏览:37' if 'action-topic-' in query else '作者:林间书签'
        rows = ''.join(f'''<tr><th><a href="read.php?tid-{940000 + int(fid)}.html">{context}{kind}</a>
<a class="gray" href="thread.php?fid-{fid}.html">{escape(label)}</a>
<span class="gray f9">[2026-01-03]</span></th><td>{metrics}</td></tr>'''
                       for fid, label, context in boards)
        shell += f'<div id="u-contentmain"><table class="u-table">{rows}</table><div class="pages">Pages: 1/1</div></div>'
    elif 'action-topic-' in query or 'action-post-' in query:
        first_metrics = '回复:2<br>浏览:37' if 'action-topic-' in query else '作者:林间书签'
        shell += f'''<div id="u-contentmain"><table class="u-table"><tr><th><a href="read.php?tid-930002.html">本地阅读笔记</a>
<a class="gray" href="thread.php?fid-930.html">本地阅读版块</a>
<span class="gray f9">[2026-01-03]</span></th><td>{first_metrics}</td></tr>
<tr><th><a href="read.php?tid-930099.html">尚未确认分类的阅读记录</a>
<a class="gray" href="thread.php?fid-930.html">本地阅读版块</a>
<span class="gray f9">[2026-01-02]</span></th><td></td></tr></table><div class="pages">Pages: 1/1</div></div>'''
    elif 'action-favor-' in query:
        shell += '<div id="u-contentmain"><table class="u-table"></table></div>'
    return f'<html><body>{shell}</body></html>'.encode()


def appendfix_account(profile):
    if APPENDFIX['redesign']:
        return redesign_account(profile)
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


def redesign_home():
    hierarchy = '''<table><tr><th><h2>同人展会</h2></th></tr>
<tr><th><h3><a href="thread.php?fid-229.html">CM108</a></h3>子版：<h3>
<a href="thread.php?fid-230.html">同人志&amp;CG</a></h3></th><td>1 / 2</td><td>2026-01-01</td></tr>
<tr><th><h3><a href="thread.php?fid-226.html">CM107</a></h3>子版：<h3>
<a href="thread.php?fid-227.html">同人志&amp;CG</a></h3></th><td>1 / 2</td><td>2026-01-01</td></tr></table>'''
    if APPENDFIX['profile_boards']:
        hierarchy = hierarchy.replace('fid-230.html">同人志&amp;CG</a>',
                                      'fid-230.html">同人志&amp;CG</a><a href="thread.php?fid-239.html">未授权子版</a>')
    return APPENDFIX_HOME.replace(b'</body>', hierarchy.encode() + b'</body>')


def redesign_account(profile):
    with APPENDFIX_LOCK:
        values = dict(APPENDFIX['profile' if profile else 'preferences'])
        nickname = APPENDFIX['nickname']
    def value(name):
        return escape(values[name], quote=True)
    def radio(name, option, label):
        checked = ' checked' if values[name] == option else ''
        return f'<input type="radio" name="{name}" value="{option}"{checked}>{label}'
    def select(name, options):
        return f'<select name="{name}">' + ''.join(
            f'<option value="{key}"' + (' selected' if values[name] == key else '')
            + f'>{label}</option>' for key, label in options) + '</select>'
    if profile:
        # The native avatar is ONE row: image-only td, all three panels in the other td.
        body = f'''<form method="post" action="profile.php?action=modify&amp;" enctype="multipart/form-data">
<input name="verify" type="hidden" value="fixture-only"><input name="step" type="hidden" value="2">
<input name="proemail" value="local@example.invalid"><textarea name="prosign">preserved footer</textarea>
<table><tr><td>昵称</td><td><input name="field_1" value="{escape(nickname)}" maxlength="20"></td></tr>
<tr><td class="td1" width="25%"><img src="images/face/none.gif" name="useravatars"></td><td>
<div id="openchang"><div>{radio('facetype', '1', '系统头像')}</div>
<div>{radio('facetype', '2', '头像链接')}</div><div>{radio('facetype', '3', '头像上传')}</div>
<div id="face1"><a id="profile" onclick="sendmsg('pw_ajax.php','action=showface',this.id);" title="头像列表"><b>[头像列表]</b></a>
<input type="hidden" name="proicon" value="{value('proicon')}"></div>
<div id="face2" style="display:none">头像链接 <input name="httpurl[0]" value="{value('httpurl[0]')}" type="text"> 必须以 http://开头<br>
头像宽度 <input name="httpurl[1]" value="{value('httpurl[1]')}" size="2" maxlength="3"> 必须是 1 -- 150 之间的一个整数。<br>
头像高度 <input name="httpurl[2]" value="{value('httpurl[2]')}" size="2" maxlength="3"> 必须是 1 -- 270 之间的一个整数。<b>头像高度留空，则根据宽度自适应</b></div>
<div id="face3" style="display:none">头像上传 <span id="reupload"><input type="file" id="upload" name="upload"><a onclick="UpLoadFace()">上传</a></span><br>
头像宽度 <input name="uploadurl[1]" value="{value('uploadurl[1]')}" size="2" maxlength="3"> 必须是 1 -- 150 之间的一个整数。<br>
头像高度 <input name="uploadurl[2]" value="{value('uploadurl[2]')}" size="2" maxlength="3"> 必须是 1 -- 270 之间的一个整数。<b>头像高度留空，则根据宽度自适应</b></div>
</div></td></tr><tr><td>个人签名</td><td><input name="prohonor" value="本地签名"></td></tr></table></form>
<script>CkFaceType('{value('facetype')}');</script>'''
    else:
        body = f'''<form method="post" action="profile.php?action=bbsset">
<input name="verify" type="hidden" value="fixture-only"><input name="step" type="hidden" value="2"><table>
<tr><td>选择风格</td><td>{select('tpskin', [('', '使用默认')])}</td></tr>
<tr><td>选择默认使用的编辑器</td><td>{radio('editor', '1', '所见即所得')}{radio('editor', '0', 'code 模式')}</td></tr>
<tr><td>选择您所在的时区<br>将时间显示为您当地时间</td><td>{select('timedf', [('0', '使用默认'), ('8', '(北京时间) 北京、重庆、香港、新加坡')])}</td></tr>
<tr><td class="td1">时间格式(格式如:yyyy-mm-dd,yy-m-d)<br>yyyy:4位数年份,yy:2位数年份<br>mm:有前导零01-12,m:没前导零1-12<br>dd:有前导零01-31,d:没前导零1-31</td><td>
{radio('d_type', '0', '使用默认')}{radio('d_type', '1', '自定义')}<input type="text" name="date_f" value="{value('date_f')}">
{radio('time_f', '24', '24')}{radio('time_f', '12', '12')}</td></tr>
<tr><td>主题列表每页个数(设置为0使用默认)</td><td>{select('t_num', [(str(n), str(n)) for n in [0, 10, 20, 30, 40]])}</td></tr>
<tr><td>文章列表每页个数(设置为0使用默认)</td><td>{select('p_num', [(str(n), str(n)) for n in [0, 10, 20, 30]])}</td></tr>
<tr><td>是否接受邮件</td><td>{radio('proreceivemail', '1', '接收邮件')}{radio('proreceivemail', '0', '不接收邮件')}</td></tr>
<tr><td>加我为好友时身份验证</td><td>{radio('friendcheck', '0', '允许任何人加我为好友')}<br>{radio('friendcheck', '1', '需要身份验证才能加我为好友')}<br>{radio('friendcheck', '2', '不允许任何人加我为好友')}</td></tr>
<tr><td>屏蔽用户组</td><td><label><input name="msggroups[]" type="checkbox" value="6" checked>普通会员</label>
<label><input name="msggroups[]" type="checkbox" value="7" checked>正式会员</label></td></tr>
<tr><td>通过UID屏蔽多个用户时用逗号 "," 隔开<br>(注意，不是昵称，是纯数字UID)。<br><br>当这些被添加的屏蔽用户给您发送短消息时将不予接收。</td>
<td><textarea name="banidinfo">{value('banidinfo')}</textarea></td></tr></table></form>'''
    return f'<html><body>{body}</body></html>'.encode()


def redesign_favorites(query):
    if re.search(r'action-favor-uid-\d+-type-\d+\.html', query):
        # The native pretty filtered route has a shell, not a trustworthy empty table.
        return b'<html><body><div id="u-contentmain"></div></body></html>'
    params = parse_qs(query, keep_blank_values=True)
    selected = params.get('type', [None])[0]
    page_value = params.get('page', ['1'])[0]
    if not re.fullmatch(r'[1-9]\d*', page_value):
        raise ValueError('Invalid fixture page')
    page = int(page_value)
    with APPENDFIX_LOCK:
        categories = list(APPENDFIX['categories'])
        favorites = dict(APPENDFIX['favorites'])
        size = APPENDFIX['page_size']
    if selected is not None and selected not in {str(index) for index in range(len(categories))}:
        raise ValueError('Invalid fixture category')
    shown = [(tid, category) for tid, category in favorites.items() if selected is None or category == selected]
    pages = max(1, (len(shown) + size - 1) // size)
    loaded = shown[(page - 1) * size:page * size]
    titles = {'940001': '待归档主题一', '940002': '待归档主题二', '940003': '已有分类主题',
              '940004': '待归档主题四', '940005': '第二页保留主题', '940006': '长期收藏原有主题'}
    rows = ''.join(f'''<tr><th><a href="read.php?tid-{tid}.html">{titles.get(tid, '本地阅读笔记')}</a></th>
<td><a href="u.php?uid-930002.html">本地作者</a></td><td>{escape(categories[int(category)]) if category != '0' else ''}</td>
<td><input type="checkbox" name="selid[]" value="{tid}"></td></tr>''' for tid, category in loaded)
    navigation = []
    for index, label in enumerate(categories):
        delete = '' if index == 0 else f'''<a href="u.php?action-favor-job-deltype-type-{index}-uid-930001-verify-fixture-only.html"
class="fr" onclick="return Checkinfo();" title="删除目录"><img src="/fixture.png"></a>'''
        navigation.append(f'''<tr><td id="uf_{index}" class="fav">{delete}
<a href="u.php?action-favor-uid-930001-type-{index}.html">{escape(label)}</a></td></tr>''')
    options = ''.join(f'<option value="{index}">{escape(label) if index else ""}</option>'
                      for index, label in enumerate(categories))
    # Categories and create form are in the native SIDEBAR, outside #u-contentmain.
    return f'''<html><head><script>var verifyhash = 'fixture-only';</script></head><body><div id="u-content">
<div id="u-contentside"><div id="u-fav-cate"><table class="u-table">
<tr><td id="uf_forum" class="fav forum"><a href="u.php?action-favor-uid-930001-type-forum.html">收藏的版块</a></td></tr>
<tr><td id="uf_all" class="fav"><a href="u.php?action-favor-uid-930001.html">收藏的帖子</a></td></tr>
{''.join(navigation)}<tr><td><form method="post" name="form" action="u.php?action=favor&amp;">
<input type="hidden" name="verify" value="fixture-only"><input type="hidden" name="job" value="addtype">
<strong>添加收藏分类</strong><div>名称 <input type="text" name="type" size="6"><input type="submit" value="提 交"></div>
</form></td></tr></table></div></div>
<div id="u-contentmain"><form method="post" action="u.php?action=favor&amp;">
<input type="hidden" name="verify" value="fixture-only"><table class="u-table">
<tr><th>主题</th><td>作者</td><td>目录</td><td>选择</td></tr>{rows}</table>
<input type="radio" name="job" value="change" checked>目录转换 <select name="type">{options}</select>
<input type="radio" name="job" value="clear">删除
<input type="button" name="chkall" value="全 选" onclick="CheckAll(this.form)"><input type="submit" value="提 交"></form>
<div class="pages"><ul><li class="pagesone">Pages: {page}/{pages}</li></ul></div></div></div></body></html>'''.encode()


def delete_fixture_category(index):
    label = APPENDFIX['categories'].pop(index)
    for tid, category in list(APPENDFIX['favorites'].items()):
        number = int(category)
        if number == index:
            APPENDFIX['favorites'][tid] = '0'
        elif number > index:
            APPENDFIX['favorites'][tid] = str(number - 1)
    return label


FAVORITES_ACK = '''<html><head><title>南+ South Plus</title>
<meta http-equiv="refresh" content="1;url=u.php?action=favor"></head><body>
南+ South Plus &raquo; 提示信息 <div>操作完成</div><a href="u.php?action=favor">如果您的浏览器没有自动跳转,请点击这里</a>
</body></html>'''.encode()


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
        resets = ('/appendfix/reset', '/account-redesign/reset', '/profile-board-tree/reset',
                  '/favorite-collections/reset', '/favorite-collections/paged-reset', '/round/reset')
        if path.path in resets and raw == b'fixture-only':
            with APPENDFIX_LOCK:
                reset_appendfix(redesign=path.path != '/appendfix/reset',
                                profile_boards=path.path == '/profile-board-tree/reset',
                                collections=path.path.startswith('/favorite-collections/'),
                                paged=path.path == '/favorite-collections/paged-reset')
                APPENDFIX['round'] = path.path == '/round/reset'
                ROUND_SCAN_GATE.clear()
            self.send_body(b'{}', 'application/json')
            return
        controls = ('external-delete-first', 'partial-next', 'unknown-ack-next')
        control = path.path.removeprefix('/favorite-collections/')
        if self.appendfix and APPENDFIX['collections'] and raw == b'fixture-only' and control in controls:
            with APPENDFIX_LOCK:
                if control == 'external-delete-first':
                    if len(APPENDFIX['categories']) <= 1:
                        self.send_error(409)
                        return
                    label = delete_fixture_category(1)
                    APPENDFIX['external_events'].append({'job': 'deltype', 'label': label})
                else:
                    APPENDFIX['partial_next' if control == 'partial-next' else 'unknown_ack_next'] = True
            self.send_body(b'{}', 'application/json')
            return
        if APPENDFIX['round'] and path.path == '/round/release-scan' and raw == b'fixture-only':
            ROUND_SCAN_GATE.set()
            self.send_body(b'{}', 'application/json')
            return
        if APPENDFIX['round'] and path.path == '/post.php':
            self.round_edit_submit(raw)
            return
        action = parse_qs(path.query).get('action', [''])[0]
        attempt = {'method': 'POST', 'path': path.path, 'action': action}
        if APPENDFIX['redesign']:
            with APPENDFIX_LOCK:
                APPENDFIX['attempts'].append(attempt)
        if APPENDFIX['redesign'] and path.path == '/u.php' and action == 'favor':
            if not self.appendfix:
                self.send_error(403)
                return
            if parse_qs(path.query) != {'action': ['favor']}:
                self.send_error(400)
                return
            if self.headers.get_content_type() != 'application/x-www-form-urlencoded':
                self.send_error(415)
                return
            try:
                fields = parse_qs(raw.decode('utf-8'), keep_blank_values=True)
            except UnicodeDecodeError:
                self.send_error(400)
                return
            attempt['fields'] = fields
            self.favorites_submit(fields)
            return
        allowed = ('bbsset', 'modify', 'ajaxface') if APPENDFIX['redesign'] else ('bbsset', 'modify')
        if not self.appendfix or path.path != '/profile.php' or action not in allowed:
            self.send_error(403)
            return
        if parse_qs(path.query) != {'action': [action]}:
            self.send_error(400)
            return
        if action == 'bbsset' and self.headers.get_content_type() != 'application/x-www-form-urlencoded':
            self.send_error(415)
            return
        files = {}
        if action in ('modify', 'ajaxface'):
            message = BytesParser(policy=policy.default).parsebytes(
                b'Content-Type: ' + self.headers.get('Content-Type', '').encode() + b'\r\n\r\n' + raw)
            if not message.is_multipart():
                self.send_error(415)
                return
            fields = {}
            for part in message.iter_parts():
                name = part.get_param('name', header='content-disposition')
                if part.get_filename() is not None:
                    content = part.get_payload(decode=True)
                    if content:
                        if not APPENDFIX['redesign']:
                            self.send_error(400)  # Legacy preview fixture has no upload protocol.
                            return
                        files[name] = (content, part.get_filename(), part.get_content_type())
                    continue
                fields.setdefault(name, []).append(part.get_payload(decode=True).decode('utf-8'))
        else:
            fields = parse_qs(raw.decode('utf-8'), keep_blank_values=True)
        if APPENDFIX['redesign']:
            self.redesign_submit(action, fields, files)
            return
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

    def round_edit_submit(self, raw):
        if not self.appendfix or self.headers.get_content_type() != 'application/x-www-form-urlencoded':
            self.send_error(403)
            return
        fields = parse_qs(raw.decode('utf-8'), keep_blank_values=True)
        pid = fields.get('pid', [''])[0]
        if pid not in ('950101', '950102'):
            self.send_error(400)
            return
        expected = round_edit_fields(pid)
        valid = all(fields.get(key) == [value] for key, value in expected.items())
        valid = valid and set(fields) == set(expected) | {'atc_title', 'atc_content'}
        valid = valid and len(fields.get('atc_title', [])) == len(fields.get('atc_content', [])) == 1
        valid = valid and bool(fields['atc_content'][0].strip())
        if not valid:
            self.send_error(400)
            return
        with APPENDFIX_LOCK:
            APPENDFIX['post_bodies'][pid] = fields['atc_content'][0]
            APPENDFIX['edits'].append(fields)
        self.send_body('<html><body>编辑成功</body></html>'.encode(), 'text/html; charset=utf-8')

    def favorites_submit(self, fields):
        job = fields.get('job', [''])[0]
        batch = job in ('change', 'clear')
        expected = {'verify', 'job', 'type'} | ({'selid[]'} if batch else set())
        valid = set(fields) == expected and fields.get('verify') == ['fixture-only']
        valid = valid and all(len(values) == 1 for key, values in fields.items() if key != 'selid[]')
        valid = valid and job in ('addtype', 'deltype', 'change', 'clear')
        destination = fields.get('type', [''])[0]
        if job == 'addtype':
            valid = valid and bool(destination.strip()) and '\x00' not in destination
        else:
            valid = valid and destination in {str(index) for index in range(len(APPENDFIX['categories']))}
        if job == 'deltype' and destination == '0':
            self.send_error(403)
            return
        selected = fields.get('selid[]', [])
        if batch:
            valid = valid and bool(selected) and len(set(selected)) == len(selected)
            valid = valid and all(tid in APPENDFIX['favorites'] for tid in selected)
            if job == 'clear':
                valid = valid and destination == '0'
        if not valid:
            self.send_error(400)
            return
        with APPENDFIX_LOCK:
            if job == 'addtype':
                APPENDFIX['categories'].append(destination)
            elif job == 'deltype':
                delete_fixture_category(int(destination))
            else:
                applied = selected[:1] if APPENDFIX['partial_next'] else selected
                APPENDFIX['partial_next'] = False
                for tid in applied:
                    if job == 'change':
                        APPENDFIX['favorites'][tid] = destination
                    else:
                        del APPENDFIX['favorites'][tid]
            APPENDFIX['writes'].append(job)
            unknown = APPENDFIX['unknown_ack_next']
            APPENDFIX['unknown_ack_next'] = False
        self.send_body(b'<html><body>Fixture received</body></html>' if unknown else FAVORITES_ACK,
                       'text/html; charset=utf-8')

    def redesign_submit(self, action, fields, files):
        valid = fields.get('verify') == ['fixture-only'] and fields.get('step') == ['2']
        valid = valid and all(len(values) == 1 for key, values in fields.items() if key != 'msggroups[]')
        if action in ('modify', 'ajaxface'):
            valid = valid and fields.get('proemail') == ['local@example.invalid']
            valid = valid and fields.get('prosign') == ['preserved footer']
            mode = fields.get('facetype', [''])[0]
            valid = valid and mode in ('1', '2', '3')
            if mode == '2':
                valid = valid and bool(re.fullmatch(r'https?://[^\s]+', fields.get('httpurl[0]', [''])[0]))
            if mode in ('2', '3'):
                prefix = 'httpurl' if mode == '2' else 'uploadurl'
                for index, maximum in [(1, 150), (2, 270)]:
                    dimension = fields.get(f'{prefix}[{index}]', [''])[0]
                    valid = valid and (index == 2 and dimension == '' or dimension.isdigit() and 1 <= int(dimension) <= maximum)
        else:
            valid = valid and fields.get('msggroups[]') == ['6', '7']
            valid = valid and set(APPENDFIX['preferences']).issubset(fields)
            valid = valid and fields.get('d_type') in (['0'], ['1'])
            valid = valid and fields.get('time_f') in (['24'], ['12'])
            valid = valid and bool(re.fullmatch(r'(?:[1-9]\d*(?:,\s*[1-9]\d*)*)?', fields.get('banidinfo', [''])[0]))
        if not valid:
            self.send_error(400)
            return
        if action == 'ajaxface':
            if APPENDFIX['reject_upload']:
                header = ''.join(f'<script>var nativeHeader{index}=0;</script>' for index in range(12))
                callback = "parent.facepath('','','上传附件失败，造成的原因可能有:附件目录不可写(777)、空间在安全模式下、空间大小已不足。','','');"
                self.send_body(f'<html><head>{header}</head><body><script>{callback}</script></body></html>'.encode(),
                               'text/html; charset=utf-8')
                return
            upload = files.get('upload')
            if mode != '3' or upload is None or not upload[0].startswith(b'\x89PNG\r\n\x1a\n'):
                self.send_error(400)
                return
            content, name, mime = upload
            width, height = struct.unpack('!2I', content[16:24])
            with APPENDFIX_LOCK:
                APPENDFIX['upload'] = content
                APPENDFIX['pending_icon'] = 'upload/930001.png'
                APPENDFIX['upload_metadata'] = dict(width=width, height=height, bytes=len(content),
                                                  sha256=hashlib.sha256(content).hexdigest(), filename=name, mime=mime)
            self.send_body(b'<script>parent.facepath("/images/", "upload/930001.png", "success");</script>',
                           'text/html; charset=utf-8')
            return
        if files:
            self.send_error(400)  # Final form must not upload the bytes a second time.
            return
        with APPENDFIX_LOCK:
            if action == 'bbsset':
                APPENDFIX['preferences'].update({key: fields[key][0] for key in APPENDFIX['preferences']})
                APPENDFIX['blacklist'] = fields['banidinfo'][0]
            else:
                if (fields.get('proicon') == ['upload/930001.png'] and APPENDFIX['pending_icon'] is None
                        and APPENDFIX['profile']['proicon'] != 'upload/930001.png'):
                    self.send_error(409)
                    return
                APPENDFIX['profile'].update({key: fields[key][0] for key in APPENDFIX['profile'] if key in fields})
                APPENDFIX['nickname'] = fields.get('field_1', [APPENDFIX['nickname']])[0]
                APPENDFIX['pending_icon'] = None
            APPENDFIX['writes'].append(action)
        # Readback, not an invented native success message, proves these form saves.
        self.send_body(b'<html><body>Fixture received</body></html>', 'text/html; charset=utf-8')

    def do_GET(self):
        path = urlsplit(self.path).path
        query = urlsplit(self.path).query
        if APPENDFIX['redesign'] and path == '/pw_ajax.php' and parse_qs(query).get('action') == ['favor']:
            with APPENDFIX_LOCK:
                APPENDFIX['attempts'].append({'method': 'GET', 'path': path, 'action': 'favor',
                                             'query': parse_qs(query, keep_blank_values=True)})
            if not self.appendfix:
                self.send_error(403)
                return
        if APPENDFIX['round'] and path == '/round/stats':
            with APPENDFIX_LOCK:
                body = json.dumps({key: APPENDFIX[key] for key in ('edits', 'thread_pages', 'thread_reads', 'post_bodies', 'topic_pages', 'scan_waiting')}).encode()
            self.send_body(body, 'application/json')
            return
        if self.appendfix and APPENDFIX['round']:
            if path == '/read.php':
                with APPENDFIX_LOCK:
                    APPENDFIX['thread_reads'].append(query)
            if path == '/u.php' and 'uid-950002' in query:
                if 'action-topic-' not in query:
                    self.send_body(round_profile(), 'text/html; charset=utf-8')
                    return
                match = re.search(r'-page-(\d+)', query)
                page = int(match[1]) if match else 1
                if page not in (1, 2, 3):
                    self.send_error(404)
                    return
                with APPENDFIX_LOCK:
                    APPENDFIX['topic_pages'].append(page)
                    APPENDFIX['scan_waiting'] = page == 2
                if page == 2 and not ROUND_SCAN_GATE.wait(timeout=60):
                    self.send_error(503)
                    return
                with APPENDFIX_LOCK:
                    APPENDFIX['scan_waiting'] = False
                self.send_body(round_profile(page), 'text/html; charset=utf-8')
                return
            if path == '/read.php' and 'tid-950001' in query:
                match = re.search(r'-page-(\d+)', query)
                page = int(match[1]) if match else 1
                if page not in (1, 2):
                    self.send_error(404)
                    return
                with APPENDFIX_LOCK:
                    APPENDFIX['thread_pages'].append(page)
                    body = round_thread(page)
                self.send_body(body, 'text/html; charset=utf-8')
                return
            if path == '/post.php':
                match = re.fullmatch(r'action-modify-fid-950-tid-950001-pid-(950101|950102)-article-(0|2)\.html', query)
                if not match or (match[1] == '950101') != (match[2] == '0'):
                    self.send_error(404)
                    return
                self.send_body(round_edit_form(match[1]), 'text/html; charset=utf-8')
                return
        if path == '/appendfix/stats':
            with APPENDFIX_LOCK:
                stats = {k: APPENDFIX[k] for k in ('purchases', 'writes', 'board_pages')}
                if APPENDFIX['redesign']:
                    stats.update({k: APPENDFIX[k] for k in ('attempts', 'reads', 'favorites', 'profile', 'preferences')})
                    stats['upload_metadata'] = APPENDFIX.get('upload_metadata')
                    stats['categories'] = [{'id': str(index), 'label': label}
                                           for index, label in enumerate(APPENDFIX['categories'])]
                    stats['external_events'] = APPENDFIX['external_events']
                body = json.dumps(stats).encode()
            self.send_body(body, 'application/json')
            return
        if self.appendfix:
            if APPENDFIX['redesign']:
                with APPENDFIX_LOCK:
                    APPENDFIX['reads'].append({'path': path, 'query': query})
                if path == '/account-redesign/upload':
                    self.send_body(APPENDFIX['upload'] or b'', 'image/png')
                    return
                if path == '/account-redesign/reject-upload':
                    APPENDFIX['reject_upload'] = True
                    self.send_body(b'{}', 'application/json')
                    return
                if path == '/account-redesign/menu-with-favorite-word':
                    APPENDFIX['favorite_menu_label'] = '收藏测试分类'
                    APPENDFIX['categories'][1] = '收藏测试分类'
                    self.send_body(b'{}', 'application/json')
                    return
                if path == '/pw_ajax.php' and parse_qs(query).get('action') == ['favor']:
                    self.redesign_favorite(query)
                    return
                if path == '/u.php' and ('action-favor' in query or parse_qs(query).get('action') == ['favor']):
                    delete = re.fullmatch(r'action-favor-job-deltype-type-(0|[1-9]\d*)-uid-930001-verify-fixture-only\.html', query)
                    if delete:
                        fields = {'verify': ['fixture-only'], 'job': ['deltype'], 'type': [delete[1]]}
                        with APPENDFIX_LOCK:
                            APPENDFIX['attempts'].append({'method': 'GET', 'path': path, 'action': 'favor', 'fields': fields})
                        self.favorites_submit(fields)
                        return
                    try:
                        body = redesign_favorites(query)
                    except ValueError:
                        self.send_error(400)
                        return
                    self.send_body(body, 'text/html; charset=utf-8')
                    return
                if path == '/pw_ajax.php':
                    if parse_qs(query).get('action') != ['showface']:
                        self.send_error(400)
                        return
                    body = '''<?xml version="1.0" encoding="utf-8"?><ajax><![CDATA[<div>
<a onclick="showimage('images','none.gif')"><img src="/fixture.png" alt="默认头像"></a>
<a onclick="showimage('images','1.gif')"><img src="/fixture.png" alt="蓝色头像"></a>
</div>]]></ajax>'''.encode()
                    self.send_body(body, 'text/xml; charset=utf-8')
                    return
            body = None
            if path in ('/index.php', '/simple/index.php'):
                body = redesign_home() if APPENDFIX['redesign'] else APPENDFIX_HOME
            elif APPENDFIX['redesign'] and path in ('/thread.php', '/thread_new.php') and re.search(r'fid-(229|230|226|227)(?:-|\.)', query):
                fid = re.search(r'fid-(\d+)', query)[1]
                label = {'229': 'CM108', '230': '同人志&CG', '226': 'CM107', '227': '同人志&CG'}[fid]
                body = appendfix_board(1).replace('本地阅读版块'.encode(), escape(label).encode()).replace(b'fid-930', f'fid-{fid}'.encode())
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
                if APPENDFIX['profile_boards']:
                    # Native search options are flat; only the homepage says which FID is a child.
                    body = '''<html><body><form action="search.php"><select name="f_fid">
<option value="all">全部版块</option><option value="8" disabled>&gt;&gt; 同人展会</option>
<option value="229">|- CM108</option><option value="230">|- 同人志&amp;CG</option>
<option value="226">|- CM107</option><option value="227">|- 同人志&amp;CG</option>
</select></form></body></html>'''.encode()
                else:
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
                  '/images/face/none.gif': (image(), 'image/png'),
                  '/images/face/1.gif': (image(), 'image/png'),
                  '/portrait.png': (image(240, 480), 'image/png')}
        if path not in routes:
            self.send_error(404)
            return
        body, content_type = routes[path]
        if path == '/read.php' and '900002' in self.path:
            body = THREAD.replace(b'/fixture.png', b'/portrait.png')
        self.send_body(body, content_type)

    def redesign_favorite(self, query):
        fields = parse_qs(query, keep_blank_values=True)
        required = {'action', 'tid', 'nowtime', 'verify'}
        if 'nowtime' not in fields:
            self.send_body('<ajax><![CDATA[非法请求，请返回重试!]]></ajax>'.encode(), 'text/xml; charset=utf-8')
            return
        valid = set(fields) in (required, required | {'type'})
        valid = valid and all(len(values) == 1 for values in fields.values())
        valid = valid and fields.get('verify') == ['fixture-only'] and fields.get('tid') == ['930002']
        valid = valid and bool(re.fullmatch(r'\d+', fields.get('nowtime', [''])[0]))
        if not valid:
            self.send_error(400)
            return
        if '930002' in APPENDFIX['favorites']:
            self.send_body('<?xml version="1.0" encoding="utf-8"?><ajax><![CDATA[您已经收藏了该主题]]></ajax>'.encode(),
                           'text/xml; charset=utf-8')
            return
        categories = list(APPENDFIX['categories'])
        if 'type' not in fields and len(categories) > 1:
            choices = ''.join(f'''<tr><td><a onclick="favor('{index}');{'return false;' if index else ''}" href="javascript:">{escape(label)}</a></td></tr>'''
                              for index, label in enumerate(categories))
            payload = f'''<?xml version="1.0" encoding="utf-8"?><ajax><![CDATA[<div class="bor"><table cellspacing="0" cellpadding="5" width="120">
<tr><th class="h" style="cursor:move" onmousedown="read.move(event);"><span class="fr" onclick="closep();"><img src="images/close.gif"></span>选择分类</th></tr>{choices}</table></div>]]></ajax>'''
            self.send_body(payload.encode(), 'text/xml; charset=utf-8')
            return
        destination = fields.get('type', ['0'])[0]
        if destination not in {str(index) for index in range(len(categories))}:
            self.send_error(400)
            return
        with APPENDFIX_LOCK:
            APPENDFIX['favorites'] = {'930002': destination, **APPENDFIX['favorites']}
            APPENDFIX['writes'].append('favor')
        self.send_body('<?xml version="1.0" encoding="utf-8"?><ajax><![CDATA[帖子收藏成功!]]></ajax>'.encode(), 'text/xml; charset=utf-8')

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
