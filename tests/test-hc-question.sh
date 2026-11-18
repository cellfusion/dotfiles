#!/usr/bin/env bash
# Verify the question template's process arguments and fail-closed search dependency.
set -u
. "$(dirname "$0")/lib/assert.sh"

if python3 - "$CHEZMOI_SOURCE/private_dot_config/herdr-core/templates/question.md" <<'PY'
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

command = next(line[9:] for line in Path(sys.argv[1]).read_text().splitlines() if line.startswith('command: '))
with tempfile.TemporaryDirectory(prefix='hc-question-') as temporary:
    root = Path(temporary)
    agent = root / 'agent with spaces'
    extension = agent / 'npm/node_modules/pi-web-search/src/index.ts'
    extension.parent.mkdir(parents=True)
    extension.write_text('// fixture')
    capture = root / 'capture.json'
    stub = root / 'mise'
    stub.write_text('''#!/usr/bin/env python3
import json, os, sys
mask = os.umask(0)
os.umask(mask)
with open(os.environ['CAPTURE'], 'w') as f:
    json.dump({'args': sys.argv[1:], 'umask': mask}, f)
''')
    stub.chmod(0o755)
    env = dict(os.environ, PATH=f"{root}:{os.environ['PATH']}", CAPTURE=str(capture), PI_CODING_AGENT_DIR=str(agent))
    env.pop('MOI_QUESTION_SESSION_DIR', None)
    subprocess.run(['sh', '-c', command], env=env, check=True)
    args = json.loads(capture.read_text())['args']
    assert args[:4] == ['x', 'pi', '--', 'pi']
    assert '--session-dir' not in args
    assert args[args.index('-e') + 1] == str(extension)
    assert '--no-extensions' in args and '--no-mcp' in args
    assert set(args[args.index('--tools') + 1].split(',')) == {'read', 'web_search', 'grep', 'find', 'ls', 'write', 'edit'}
    session = str(root / 'session with spaces')
    subprocess.run(['sh', '-c', command], env=dict(env, MOI_QUESTION_SESSION_DIR=session), check=True)
    result = json.loads(capture.read_text())
    assert result['args'][-2:] == ['--session-dir', session]
    assert result['umask'] & 0o077 == 0o077
    capture.unlink()
    extension.unlink()
    result = subprocess.run(['sh', '-c', command], env=env, capture_output=True)
    assert result.returncode != 0 and not capture.exists()
PY
then
  pass 'question template preserves restrictions and private session handling'
else
  fail_check 'question template preserves restrictions and private session handling'
fi

assert_summary
