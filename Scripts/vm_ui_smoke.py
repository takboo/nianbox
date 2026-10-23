#!/usr/bin/env python3
"""Native functional checks in an existing, isolated VirtualMac guest (no XCTest runtime).
The Swift probe independently rejects physical Macs. Run this inside the guest only.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--probe', type=Path, required=True)
parser.add_argument('--source', type=Path, required=True)
parser.add_argument('--output', type=Path, required=True)
parser.add_argument('--fixture', type=Path)
parser.add_argument('--shortcut-holder', type=Path)
args = parser.parse_args()
model = subprocess.check_output(['/usr/sbin/sysctl', '-n', 'hw.model'], text=True).strip()
if not model.startswith('VirtualMac'):
    parser.error('Refusing desktop automation on a physical Mac')
args.app, args.probe = args.app.resolve(), args.probe.resolve()
args.output.mkdir(parents=True, exist_ok=False)
report = dict(virtualMachine=True, physicalDeviceAcceptance=False, testMethod='native AX + guest CoreGraphics events; not XCUITest',
              model=model, guestOS=subprocess.check_output(['sw_vers'], text=True),
              sourceCommit=subprocess.check_output(['git', '-C', str(args.source), 'rev-parse', 'HEAD'], text=True).strip(),
              sourceDirty=bool(subprocess.check_output(['git', '-C', str(args.source), 'status', '--porcelain'], text=True)),
              appSHA256=hashlib.sha256((args.app / 'Contents/MacOS/NianBox').read_bytes()).hexdigest(),
              probeSourceSHA256=hashlib.sha256((args.probe.parent / 'vm_ui_probe.swift').read_bytes()).hexdigest(),
              controllerSHA256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(), checks=[])
pid = None


def save():
    (args.output / 'results.json').write_text(json.dumps(report, ensure_ascii=False, indent=2))


def stop():
    global pid
    if pid:
        subprocess.run(['/bin/kill', '-TERM', str(pid)], check=False, capture_output=True)
        for _ in range(30):
            if subprocess.run(['/bin/kill', '-0', str(pid)], capture_output=True).returncode:
                break
            time.sleep(.1)
        pid = None


def launch(normal=False, fixture=None):
    global pid
    stop()
    # Only our app lives under this acceptance directory; never terminate unrelated processes.
    running = subprocess.run(['/usr/bin/pgrep', '-x', 'NianBox'], capture_output=True, text=True)
    if running.returncode == 0:
        raise RuntimeError('An existing NianBox process must be closed before isolated acceptance')
    command = ['/usr/bin/open', '-n']
    if not normal:
        command += ['--env', 'NIANBOX_UI_TESTING=1']
    if fixture:
        command += ['--env', 'NIANBOX_SYNC_FIXTURE=' + str(fixture)]
    subprocess.run(command + [str(args.app)], check=True)
    for _ in range(50):
        found = subprocess.run(['/usr/bin/pgrep', '-x', 'NianBox'], capture_output=True, text=True)
        if found.returncode == 0:
            pid = int(found.stdout.strip())
            time.sleep(.8)
            return
        time.sleep(.1)
    raise RuntimeError('NianBox did not launch')


def probe(command, *arguments):
    result = subprocess.run([str(args.probe), command, str(pid), *arguments], capture_output=True, text=True, timeout=15)
    if result.returncode:
        raise RuntimeError(result.stderr.strip())
    return json.loads(result.stdout)


def nodes():
    return probe('dump')['nodes']


def find(selector):
    field, value = selector.split('=', 1)
    attributes = ['AXIdentifier'] if field == 'id' else ['AXValue', 'AXTitle', 'AXDescription']
    return next((n for n in nodes() if any(n.get(k) == value for k in attributes)), None)


def wait(selector, present=True):
    for _ in range(40):
        node = find(selector)
        if bool(node) == present:
            return node
        time.sleep(.1)
    raise AssertionError('Expected %s: %s' % ('present' if present else 'absent', selector))


def capture(name):
    (args.output / (name + '.json')).write_text(json.dumps(probe('dump'), ensure_ascii=False, indent=2))
    subprocess.run(['/usr/sbin/screencapture', '-x', str(args.output / (name + '.png'))], check=True)


def add(title):
    probe('click', 'id=add-task-button')
    wait('id=new-task-title')
    probe('click', 'id=new-task-title')
    probe('type', title)
    probe('key', 'return')
    return wait('text=' + title)


def task_id(title):
    current = None
    for node in nodes():
        identifier = node.get('AXIdentifier', '')
        if identifier.startswith('task-row-'):
            current = identifier[len('task-row-'):]
        if node.get('AXValue') == title and current:
            return current
    raise AssertionError('No row identity for ' + title)


def check(name, function):
    started = time.monotonic()
    try:
        function()
        item = dict(name=name, passed=True)
    except Exception as error:
        item = dict(name=name, passed=False, error=str(error))
        if pid:
            try: capture(name + '-failure')
            except Exception: pass
    item['seconds'] = round(time.monotonic() - started, 2)
    report['checks'].append(item)
    save()
    print(json.dumps(item, ensure_ascii=False), flush=True)
    stop()


def capture_status_menu():
    launch()
    add('Ship prototype')
    identifier = task_id('Ship prototype')
    probe('double', 'text=Ship prototype')
    wait('id=task-section-inProgress')
    probe('click', 'id=complete-task-' + identifier)
    wait('id=task-section-done')
    wait('text=Ship prototype')
    probe('click', 'id=task-actions-' + identifier)
    wait('text=Copy')
    probe('press', 'text=Edit title…')
    editor = 'id=edit-task-title-' + identifier
    wait(editor)
    probe('click', editor)
    probe('key', 'selectAll')
    probe('type', 'Retained completed history')
    probe('key', 'return')
    wait('text=Retained completed history')
    wait('id=task-section-done')
    capture('completed-history-and-rename')


def drag_order():
    launch()
    add('Alpha')
    add('Beta')
    first, second = wait('text=Alpha'), wait('text=Beta')
    assert second['y'] < first['y']
    capture('drag-before')
    probe('drag', 'text=Beta', 'text=Alpha')
    first, second = wait('text=Alpha'), wait('text=Beta')
    capture('drag-after')
    assert second['y'] > first['y'], 'OS drag did not reorder: Beta=%s Alpha=%s' % (second['y'], first['y'])


def wrapping():
    launch()
    title = 'A long task title that should wrap onto multiple lines instead of being cut off'
    assert add(title)['height'] > 20
    capture('long-title')


def search():
    launch()
    add('Book flights')
    probe('click', 'id=toggle-task-search')
    probe('click', 'id=task-search-field')
    probe('type', 'FLIGHTS')
    wait('text=Book flights')
    probe('key', 'selectAll')
    probe('type', 'trains')
    wait('text=No matches')
    wait('text=Book flights', False)
    probe('click', 'id=toggle-task-search')
    wait('text=Book flights')
    capture('search-restored')


def global_corner_persistence():
    launch(normal=True)
    # First launch may show Settings; close only NianBox's own close button.
    close = next((n for n in nodes() if n.get('AXSubrole') == 'AXCloseButton'), None)
    if close:
        probe('click', 'subrole=AXCloseButton')
    subprocess.run(['/usr/bin/open', '-a', 'Finder'], check=True)
    probe('key', 'shortcut')
    wait('id=new-task-title')
    probe('click', 'id=new-task-title')
    title = 'VM offline capture ' + args.output.name
    probe('type', title)
    probe('key', 'return')
    wait('text=' + title)
    stop()
    launch(normal=True)
    subprocess.run(['/usr/bin/open', '-a', 'Finder'], check=True)
    probe('key', 'shortcut')
    wait('text=' + title)
    probe('key', 'escape')
    probe('move', '700', '700')
    visible = lambda: [w for w in probe('windows')['windows'] if w.get('kCGWindowBounds', {}).get('Height', 0) > 100]
    assert not visible(), 'Panel did not hide'
    probe('move', '1439', '1')
    assert visible(), 'Corner did not reveal panel'
    capture('corner-reveal-after-reopen')
    probe('move', '700', '700')
    assert not visible(), 'Panel did not hide after leaving'


def hermes():
    if not args.fixture:
        raise RuntimeError('No isolated Hermes fixture supplied')
    import urllib.request
    fixture = json.loads(args.fixture.read_text())
    task = fixture['task']
    launch(fixture=args.fixture)
    wait('text=' + task['title'])
    identifier = task_id(task['title'])
    probe('click', 'id=complete-task-' + identifier)
    wait('id=task-section-done')
    for _ in range(50):
        request = urllib.request.Request(fixture['url'] + '/v1/tasks/' + task['id'], headers={'Authorization': 'Bearer ' + fixture['token']})
        with urllib.request.urlopen(request, timeout=5) as response:
            saved = json.load(response)
        if saved['status'] == 'done' and saved['completedAt']:
            capture('hermes-task-completed')
            return
        time.sleep(.1)
    raise AssertionError('VM completion did not reach NianBox Server')


def configurable_shortcut():
    launch(normal=True)
    probe('key', 'shortcut')
    probe('click', 'id=settings-button')
    control = 'id=quick-capture-shortcut'
    wait(control)
    probe('click', control)
    probe('key', 'captureK')
    wait('text=⌃⌥K')
    capture('custom-shortcut-settings')
    if args.shortcut_holder:
        holder = subprocess.Popen([str(args.shortcut_holder.resolve())], stdout=subprocess.PIPE, text=True)
        try:
            assert holder.stdout.readline().strip() == 'READY'
            probe('click', control)
            probe('key', 'captureL')
            assert any('unavailable' in str(n) for n in nodes()), 'Conflict was not reported'
            wait('text=⌃⌥K')
            capture('shortcut-conflict-retains-setting')
        finally:
            holder.terminate(); holder.wait(timeout=5)
    # Cancellation must restore the current registration.
    probe('click', control)
    probe('key', 'escape')
    subprocess.run(['/usr/bin/open', '-a', 'Finder'], check=True)
    probe('key', 'captureK')
    wait('id=new-task-title')
    title = 'Configured shortcut capture ' + str(time.time_ns())
    probe('type', title); probe('key', 'return')
    wait('text=' + title)
    stop(); launch(normal=True)
    subprocess.run(['/usr/bin/open', '-a', 'Finder'], check=True)
    probe('key', 'captureK')
    wait('id=new-task-title')
    wait('text=' + title)
    probe('click', 'id=settings-button')
    wait(control)
    probe('click', control); probe('key', 'delete')
    wait('text=Not set')
    probe('press', 'text=Restore default shortcut')
    wait('text=⌃⌥Space')
    capture('shortcut-default-restored')
    subprocess.run(['/usr/bin/open', '-a', 'Finder'], check=True)
    probe('key', 'shortcut')
    wait('id=new-task-title')


try:
    save()
    check('capture_status_menu_history', capture_status_menu)
    check('native_drag_order', drag_order)
    check('long_title_wrap', wrapping)
    check('search', search)
    check('global_shortcut_corner_and_disk_reopen', global_corner_persistence)
    if args.shortcut_holder:
        check('configurable_shortcut_conflict_and_reopen', configurable_shortcut)
    if args.fixture:
        check('hermes_server_vm_roundtrip', hermes)
finally:
    stop()
raise SystemExit(0 if all(c['passed'] for c in report['checks']) else 1)
