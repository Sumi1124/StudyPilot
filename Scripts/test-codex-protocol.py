#!/usr/bin/env python3
"""Exercise two isolated real app-servers without signing into either account."""
from pathlib import Path
import json, os, select, subprocess, tempfile, time, sys

root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/StudyPilotCore/CodexSecurityPolicy.swift').read_text()
profile = source.split('public static let sandboxProfile = """\n')[1].split('    """')[0]
candidates = ['/opt/homebrew/bin/codex', '/usr/local/bin/codex', '/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex']
binary = next((str(Path(p).resolve()) for p in candidates if os.access(p, os.X_OK)), None)
if not binary: raise SystemExit('Install the official native Codex CLI first.')
processes = []

def launch(home):
    for name in ['CodexHome', 'Workspace', 'Temporary']: (home/name).mkdir(parents=True, mode=0o700)
    cmd = ['/usr/bin/sandbox-exec', '-DROOT='+str(home), '-DEXECUTABLE='+binary, '-DBINARY_DIRECTORY='+str(Path(binary).parent), '-p', profile, binary, 'app-server', '--stdio', '--strict-config', '-c', 'memories.use_memories=false', '-c', 'memories.generate_memories=false', '-c', 'features.shell_tool=false', '-c', 'features.unified_exec=false', '-c', 'features.apps=false', '-c', 'features.plugins=false', '-c', 'features.code_mode=false', '-c', 'features.code_mode_host=false', '-c', 'features.apply_patch_freeform=false', '-c', 'web_search="disabled"', '-c', 'sandbox_mode="read-only"', '-c', 'cli_auth_credentials_store="file"', '-c', 'forced_login_method="chatgpt"']
    env = {'HOME': str(home), 'CODEX_HOME': str(home/'CodexHome'), 'TMPDIR': str(home/'Temporary'), 'PATH': '/usr/bin:/bin', 'LANG': 'en_US.UTF-8', 'CODEX_CA_CERTIFICATE': '/private/etc/ssl/cert.pem'}
    p = subprocess.Popen(cmd, cwd=home/'Workspace', env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
    processes.append(p)
    return p

next_id = 0
buffers = {}
def rpc(p, method, params, expect_error=False):
    global next_id
    next_id += 1; ident = next_id
    p.stdin.write((json.dumps({'id': ident, 'method': method, 'params': params})+'\n').encode())
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        buf = buffers.get(p.pid, b'')
        if b'\n' not in buf:
            if not select.select([p.stdout], [], [], max(0, deadline-time.monotonic()))[0]: break
            chunk = os.read(p.stdout.fileno(), 65536)
            if not chunk: raise RuntimeError(method+': app-server exited')
            buf += chunk
        while b'\n' in buf:
            line, buf = buf.split(b'\n', 1); buffers[p.pid] = buf
            response = json.loads(line)
            if response.get('id') == ident:
                assert ('error' in response) == expect_error, method+': unexpected response status'
                return response.get('result')
        buffers[p.pid] = buf
    raise RuntimeError(method+': timed out')

with tempfile.TemporaryDirectory(prefix='studypilot-protocol-') as tmp:
    base = Path(tmp).resolve()
    try:
        homes = [base/'alice', base/'bob']
        peers = [launch(home) for home in homes]
        for peer in peers:
            rpc(peer, 'initialize', {'clientInfo': {'name': 'StudyPilotSecurityProbe', 'version': '1.0'}, 'capabilities': {'experimentalApi': True}})
            peer.stdin.write(b'{"method":"initialized","params":{}}\n')
            assert rpc(peer, 'account/read', {})['account'] is None
            config = rpc(peer, 'config/read', {'includeLayers': False})['config']
            assert all(config['features'].get(key) is False for key in ['apps', 'plugins', 'shell_tool', 'unified_exec', 'code_mode', 'code_mode_host', 'apply_patch_freeform'])
            assert config['web_search'] == 'disabled'
            assert config['memories']['use_memories'] is False
            assert config['memories']['generate_memories'] is False
            print('PASS: effective configuration disables apps, plugins, commands and web search', flush=True)
        print('PASS: two simultaneous processes have fresh, separate signed-out accounts', flush=True)
        if '--network' in sys.argv:
            # Exercise the real HTTPS auth client, never a user's account or token.
            # Starting browser login alone does not make an outbound token request.
            device = rpc(peers[0], 'account/login/start', {'type': 'chatgptDeviceCode'})
            assert device.get('loginId') and device.get('type') == 'chatgptDeviceCode'
            rpc(peers[0], 'account/login/cancel', {'loginId': device['loginId']})
            assert rpc(peers[0], 'account/read', {})['account'] is None
            print('PASS: sandboxed OpenAI HTTPS auth endpoint reachable with TLS verification; temporary login cancelled', flush=True)
        tool = {'type': 'function', 'name': 'study_count_words', 'description': 'Count words only after student approval.', 'inputSchema': {'type': 'object', 'properties': {'file_id': {'type': 'string'}}, 'required': ['file_id'], 'additionalProperties': False}}
        threads = []
        for peer, home in zip(peers, homes):
            result = rpc(peer, 'thread/start', {'cwd': str(home/'Workspace'), 'sandbox': 'read-only', 'approvalPolicy': 'on-request', 'approvalsReviewer': 'user', 'dynamicTools': [tool]})
            threads.append(result['thread']['id'])
        for peer, home in zip(peers, homes):
            ephemeral = rpc(peer, 'thread/start', {'cwd': str(home/'Workspace'), 'ephemeral': True,
                'sandbox': 'read-only', 'approvalPolicy': 'never', 'dynamicTools': [],
                'baseInstructions': 'Use only the current request.',
                'config': {'memories.use_memories': False, 'memories.generate_memories': False}})
            ident = ephemeral['thread']['id']
            assert ident not in threads
            listed = rpc(peer, 'thread/list', {'cwd': str(home/'Workspace'), 'limit': 100})
            assert ident not in [entry['id'] for entry in listed['data']]
            rpc(peer, 'thread/unsubscribe', {'threadId': ident})
        print('PASS: fresh memory-disabled ephemeral requests stay out of saved history', flush=True)
        assert threads[0] != threads[1]
        print('PASS: official dynamic tool registration and distinct conversations', flush=True)
        for i, peer in enumerate(peers):
            rpc(peer, 'thread/read', {'threadId': threads[1-i], 'includeTurns': True}, expect_error=True)
        print('PASS: cross-process guessed conversation IDs rejected in both directions', flush=True)
        # A newly started thread may not persist until its first model turn. No
        # model call or existing subscription is used in this signed-out test.
        for peer in peers: rpc(peer, 'account/logout', {})
        print('PASS: both isolated account/logout operations complete', flush=True)
    finally:
        for p in processes:
            p.terminate()
            try: p.wait(timeout=3)
            except subprocess.TimeoutExpired: p.kill(); p.wait()
print('PASS: all probe processes stopped and temporary homes removed')
