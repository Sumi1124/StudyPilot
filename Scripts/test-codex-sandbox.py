#!/usr/bin/env python3
"""macOS integration gate: OS-enforced file/exec isolation and signed-out startup.
Requires an ordinary unsandboxed terminal; never uses the caller's Codex home.
"""
from pathlib import Path
import json
import os
import select
import shutil
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/StudyPilotCore/CodexSecurityPolicy.swift').read_text()
profile = source.split('public static let sandboxProfile = """\n')[1].split('    """')[0]
candidates = ['/opt/homebrew/bin/codex', '/usr/local/bin/codex', '/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex']
binary = next((str(Path(p).resolve()) for p in candidates if os.access(p, os.X_OK)), None)
if not binary:
    raise SystemExit('Install the official Codex CLI to run the integration gate.')

def sandbox(executable, private):
    return ['/usr/bin/sandbox-exec', '-DROOT='+str(private), '-DEXECUTABLE='+str(executable),
            '-DBINARY_DIRECTORY='+str(Path(executable).parent), '-p', profile, str(executable)]

with tempfile.TemporaryDirectory(prefix='studypilot-security-') as tmp:
    base = Path(tmp).resolve()
    private = base / 'alice'
    other = base / 'bob'
    binaries = base / 'bin'
    for d in [private, other, binaries]: d.mkdir(mode=0o700)
    (private / 'allowed').write_text('alice')
    (other / 'private').write_text('bob')
    (private / 'escape').symlink_to(other)
    # A native probe runs under exactly the release policy, without a model.
    probe_source = binaries / 'probe.c'
    probe_source.write_text(r'''
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <sys/wait.h>
int main(int argc, char **argv) {
    int fd = open(argv[1], O_RDONLY); if (fd < 0) return 10; close(fd);
    fd = open(argv[2], O_RDONLY); if (fd >= 0) return 11;
    fd = open(argv[3], O_RDONLY); if (fd >= 0) return 12;
    fd = open(argv[2], O_WRONLY | O_TRUNC); if (fd >= 0) return 13;
    pid_t pid = fork(); if (pid < 0) return 14;
    if (pid == 0) { execl("/bin/sh", "sh", "-c", "exit 0", NULL); _exit(42); }
    int status; waitpid(pid, &status, 0);
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 42) return 15;
    return 0;
}
''')
    probe = binaries / 'probe'
    subprocess.run(['xcrun', 'clang', str(probe_source), '-o', str(probe)], check=True)
    subprocess.run(sandbox(probe, private) + [str(private/'allowed'), str(other/'private'), str(private/'escape/private')], check=True)
    assert (other/'private').read_text() == 'bob'
    print('PASS: own-file access; other-workspace read/write, symlink escape and shell execution denied', flush=True)
    for name in ['CodexHome', 'Workspace', 'Temporary']:
        (private/name).mkdir(mode=0o700)
    env = {'HOME': str(private), 'CODEX_HOME': str(private/'CodexHome'), 'TMPDIR': str(private/'Temporary'), 'PATH': '/usr/bin:/bin', 'LANG': 'en_US.UTF-8'}
    cmd = sandbox(binary, private) + ['app-server', '--stdio', '--strict-config', '-c', 'features.shell_tool=false', '-c', 'features.unified_exec=false', '-c', 'features.apps=false', '-c', 'features.plugins=false', '-c', 'features.code_mode=false', '-c', 'features.code_mode_host=false', '-c', 'features.apply_patch_freeform=false', '-c', 'web_search="disabled"', '-c', 'sandbox_mode="read-only"', '-c', 'cli_auth_credentials_store="file"', '-c', 'forced_login_method="chatgpt"']
    proc = subprocess.Popen(cmd, cwd=private/'Workspace', env=env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        for ident, method, params in [(1, 'initialize', {'clientInfo': {'name': 'StudyPilotSecurityProbe', 'version': '1.0'}}), (2, 'account/read', {}), (3, 'account/login/start', {'type': 'chatgpt'})]:
            proc.stdin.write(json.dumps({'id': ident, 'method': method, 'params': params})+'\n'); proc.stdin.flush()
            while True:
                if not select.select([proc.stdout], [], [], 15)[0]: raise RuntimeError('Timed out: '+method)
                line = proc.stdout.readline()
                if not line: raise RuntimeError('App server exited: '+proc.stderr.read()[-2000:])
                obj = json.loads(line)
                if obj.get('id') == ident:
                    if 'error' in obj: raise RuntimeError(method+' failed')
                    if ident == 2: assert obj['result']['account'] is None
                    if ident == 3:
                        from urllib.parse import urlparse
                        url = urlparse(obj['result']['authUrl'])
                        assert url.scheme == 'https' and (url.hostname == 'auth.openai.com' or url.hostname.endswith('.openai.com'))
                    print('PASS: '+method, flush=True)
                    break
            if ident == 1:
                proc.stdin.write('{"method":"initialized","params":{}}\n'); proc.stdin.flush()
    finally:
        proc.terminate()
        try: proc.wait(timeout=3)
        except subprocess.TimeoutExpired: proc.kill(); proc.wait()
print('PASS: isolated app-server stopped; temporary credentials/history removed')
