import argparse
from collections import Counter, defaultdict
from concurrent.futures import ProcessPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import queue
import re
import statistics
import subprocess
import threading
import time
from urllib.parse import urlsplit

from PIL import Image, ImageDraw


PACKAGE = 'com.example.south_plus_gif_bench14'
ACTIVITY = 'com.example.south_plus_rewrite.MainActivity'
PORT = 18765
FRAME_COUNT = 24
FRAME_MS = 50
CASES = {
    'group-gif': ('98100', 100, True, True),
    'spread-gif': ('98200', 100, False, True),
    'group-still': ('98300', 100, True, False),
    'spread-still': ('98400', 100, False, False),
    'one-gif': ('98101', 1, True, True),
    'two-gif': ('98102', 2, True, True),
    'one-still': ('98301', 1, True, False),
    'two-still': ('98302', 2, True, False),
    'group-manual': ('98100', 100, True, True),
    'two-play': ('98102', 2, True, True),
}


def dimensions(index):
    return (1200, 1600) if index % 2 == 0 else (800, 600)


def generate(item):
    directory, index = item
    width, height = dimensions(index)
    palette = [component for p in range(256)
               for component in ((p * 47) % 256, (p * 71) % 256, (p * 97) % 256)]
    frames = []
    for step in range(FRAME_COUNT):
        frame = Image.new('P', (width, height), index)
        frame.putpalette(palette)
        draw = ImageDraw.Draw(frame)
        for y in range(0, height, 100):
            for x in range(0, width, 100):
                draw.rectangle((x, y, x + 99, y + 99),
                               fill=(x // 10 + y // 5 + index * 11 + step * 3) % 256)
        x = (index * 29 + step * 47) % (width - 160)
        draw.ellipse((x, 25, x + 160, 185), fill=(index + step + 100) % 256)
        draw.text((x + 20, 70), f'{index + 1:03d} / {step + 1:02d}', fill=255)
        frames.append(frame)
    frames[0].save(directory / f'{index}-still.gif')
    frames[0].save(directory / f'{index}-gif.gif', save_all=True,
                   append_images=frames[1:], duration=FRAME_MS, loop=0, optimize=False)
    for name, expected in [('still', 1), ('gif', FRAME_COUNT)]:
        with Image.open(directory / f'{index}-{name}.gif') as image:
            if image.size != (width, height) or image.n_frames != expected:
                raise ValueError(f'Incorrect GIF fixture {index}-{name}')


def thread_html(case, run_id):
    tid, count, grouped, animated = CASES[case]
    suffix = 'gif' if animated else 'still'
    sections = [
        f'<p>Image {i + 1} of {count}</p><img src="/images/{run_id}/{i}-{suffix}.gif">'
        '<p>Draft margins and line lengths vary with the reader width.</p>'
        for i in range(count)
    ]
    posts = [''.join(sections)] if grouped else sections
    posts[-1] += '<p>End of thread</p>' + '<p>Fixture text</p>' * 24
    tables = ''.join(
        '<table class="js-post"><tr><th class="r_two">'
        '<a href="/u.php?action-show-uid-900004.html"><strong>Fixture author</strong></a>'
        f'</th><th class="r_one"><div class="tpc_content" id="read_{910000 + index}">'
        f'{body}</div></th></tr></table>'
        for index, body in enumerate(posts)
    )
    return (f'<!doctype html><html><head><meta charset="utf-8"></head><body>'
            f'<h1 id="subject_tpc">GIF scroll {tid}</h1><div class="pages">Pages: 1/1</div>'
            f'{tables}</body></html>').encode()


def fixture_server(directory):
    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            if self.path != '/events':
                self.send_error(404)
                return
            size = int(self.headers['Content-Length'])
            payload = json.loads(self.rfile.read(size))
            with self.server.lock:
                payload['urlsRequested'] = len(self.server.requests)
            self.server.events.put(payload)
            self.send_response(204)
            self.end_headers()

        def do_GET(self):
            route = urlsplit(self.path)
            case = self.server.case
            run_id = self.server.run_id
            asset = re.fullmatch(r'/images/(\d+)/(\d+)-(gif|still)\.gif', route.path)
            tid, count, _, animated = CASES[case]
            if route.path == '/read.php' and re.match(fr'^tid-{tid}(?:-|\.)', route.query):
                data, kind = thread_html(case, run_id), 'text/html; charset=utf-8'
            elif (asset and asset[1] == run_id and int(asset[2]) < count
                  and asset[3] == ('gif' if animated else 'still')):
                data = (directory / f'{asset[2]}-{asset[3]}.gif').read_bytes()
                kind = 'image/gif'
                with self.server.lock:
                    self.server.requests[asset[2]] += 1
            else:
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header('Content-Type', kind)
            self.send_header('Content-Length', str(len(data)))
            self.send_header('Cache-Control', 'public, max-age=3600')
            self.end_headers()
            try:
                self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError):
                pass

        def log_message(self, *_):
            pass

    server = ThreadingHTTPServer(('127.0.0.1', PORT), Handler)
    server.lock = threading.Lock()
    server.requests = Counter()
    return server


def run_case(adb, server, case, destination):
    tid, count, _, _ = CASES[case]
    manual = case.endswith('manual')
    server.case = case
    server.run_id = str(time.time_ns())
    with server.lock:
        server.requests.clear()

    def shell(*args):
        return subprocess.check_output([*adb, 'shell', *args], text=True, timeout=8).strip()

    hz = int(shell('getconf CLK_TCK'))
    shell('am', 'force-stop', PACKAGE)
    messages = server.events = queue.Queue()
    events = []
    samples = []
    stage = 'launch'
    started = time.monotonic()
    try:
        mode = 'manual' if manual else 'play' if case.endswith('-play') else 'auto'
        launch = shell('am', 'start', '-W', '-n', f'{PACKAGE}/{ACTIVITY}', '--es', 'route',
                       f'/{tid}/{mode}')
        if 'Error' in launch:
            raise RuntimeError(launch)
        pid = int(shell(f'pidof {PACKAGE}'))
        command = (f'cat /proc/{pid}/stat /proc/{pid}/smaps_rollup; '
                   f'for file in /proc/{pid}/task/*/stat; do '
                   'read -r row < "$file" && echo "$row"; done')
        while time.monotonic() - started < 210:
            while not messages.empty():
                event = messages.get()
                if not events and (event['event'], event.get('phase')) != ('start', 'load'):
                    continue
                events.append(event)
                if event['event'] == 'start':
                    stage = event['phase']
                if event['event'] == 'error':
                    raise RuntimeError(event['message'])
                if event['event'] == 'done':
                    phases = ('load', 'top', 'scroll', 'bottom', 'exited')
                    for marker in ('start', 'end', 'timings'):
                        observed = tuple(e['phase'] for e in events if e['event'] == marker)
                        if observed != phases:
                            raise RuntimeError(f'Incomplete {marker} events: {observed}')
                    expected = 0 if manual else count
                    if event['tid'] != tid or len(server.requests) != expected:
                        raise RuntimeError(f'Expected {expected} image URLs, saw {len(server.requests)}')
                    decoded = max((event.get('decodedImages', 0) for event in events), default=0)
                    if decoded == 0 and not manual:
                        raise RuntimeError('No decoded inline images observed')
                    return
            now = time.monotonic()
            output = shell(f"su -c '{command}'")
            process, *rows = output.splitlines()
            if not process.startswith(f'{pid} ('):
                raise RuntimeError(f'App process {pid} exited during {stage}')

            def stat(row):
                head, _, tail = row.rpartition(') ')
                identity, name = head.split(' (', 1)
                fields = tail.split()
                return identity, name, int(fields[11]) + int(fields[12])

            pss = next(int(row.split()[1]) for row in rows if row.startswith('Pss:'))
            rss = next(int(row.split()[1]) for row in rows if row.startswith('Rss:'))
            tasks = {key: {'name': name, 'ticks': ticks}
                     for key, name, ticks in map(stat, (r for r in rows if re.match(r'^\d+ \(', r)))}
            samples.append({'seconds': now - started, 'phase': stage, 'pssKiB': pss, 'rssKiB': rss,
                            'ticks': stat(process)[2], 'threads': tasks})
            time.sleep(max(0, .9 - (time.monotonic() - now)))
        raise TimeoutError(f'No completion marker for {case} ({stage})')
    finally:
        with server.lock:
            requests = dict(server.requests)
        destination.write_text(json.dumps({
            'case': case, 'clockHz': hz, 'events': events, 'requests': requests,
            'samples': samples, 'system': summarize(samples, hz),
        }, indent=2), encoding='utf-8')


def summarize(samples, hz):
    grouped = defaultdict(list)
    for sample in samples:
        grouped[sample['phase']].append(sample)
    result = {}
    for phase, group in grouped.items():
        cpu = []
        threads = Counter()
        duration = 0
        for first, last in zip(group, group[1:]):
            elapsed = last['seconds'] - first['seconds']
            cpu.append((last['ticks'] - first['ticks']) * 100 / (hz * elapsed))
            duration += elapsed
            for key in first['threads'].keys() & last['threads'].keys():
                before, after = first['threads'][key], last['threads'][key]
                threads[after['name']] += after['ticks'] - before['ticks']
        result[phase] = {
            'peakPssMiB': round(max(s['pssKiB'] for s in group) / 1024, 1),
            'lastPssMiB': round(group[-1]['pssKiB'] / 1024, 1),
            'peakRssMiB': round(max(s['rssKiB'] for s in group) / 1024, 1),
            'medianCpuPercentOfOneCore': round(statistics.median(cpu), 1) if cpu else None,
            'peakCpuPercentOfOneCore': round(max(cpu), 1) if cpu else None,
            'threadCpuPercentOfOneCore': {
                name: round(ticks * 100 / (hz * duration), 1)
                for name, ticks in threads.most_common(8)
            } if duration else {},
        }
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('output', type=Path)
    parser.add_argument('--device', default='127.0.0.1:5555')
    parser.add_argument('--fixtures', type=Path)
    parser.add_argument('--cases', nargs='+', choices=CASES, default=list(CASES))
    parser.add_argument('--fixtures-only', action='store_true')
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    fixtures = args.fixtures or args.output / 'fixtures'
    fixtures.mkdir(exist_ok=True)
    missing = [i for i in range(100) if not all(
        (fixtures / f'{i}-{kind}.gif').is_file() for kind in ('gif', 'still'))]
    if missing:
        with ProcessPoolExecutor(max_workers=4) as pool:
            list(pool.map(generate, [(fixtures, i) for i in missing]))
    if args.fixtures_only:
        return
    adb = ['adb', '-s', args.device]
    port = f'tcp:{PORT}'
    mappings = subprocess.check_output([*adb, 'reverse', '--list'], text=True).splitlines()
    previous = next((row.split()[-1] for row in mappings if row.split()[1:2] == [port]), None)
    failures = []
    with fixture_server(fixtures) as server:
        if previous != port:
            subprocess.run([*adb, 'reverse', port, port], check=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            for case in args.cases:
                print(f'Running {case}', flush=True)
                try:
                    run_case(adb, server, case, args.output / f'{case}.json')
                except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
                    failures.append(case)
                    print(f'{case}: {error}', flush=True)
                else:
                    print(f'Finished {case}', flush=True)
        finally:
            server.shutdown()
            if previous is None:
                subprocess.run([*adb, 'reverse', '--remove', port], check=True)
            elif previous != port:
                subprocess.run([*adb, 'reverse', port, previous], check=True)
    if failures:
        raise SystemExit(f'Failed cases: {", ".join(failures)}')


if __name__ == '__main__':
    main()
