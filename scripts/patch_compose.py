#!/usr/bin/env python3
# Idempotently add the python_server extension flag to the Isaac Sim compose service,
# so the remote-control port (8226) comes up. Runs ON the instance.
p = '/home/ubuntu/IsaacSim/tools/docker/docker-compose.yml'
s = open(p).read()
if 'isaacsim.code_editor.python_server' in s:
    print('already patched')
    raise SystemExit(0)
open(p + '.bak', 'w').write(s)
out = []
for ln in s.split('\n'):
    out.append(ln)
    if 'image: ${ISAAC_SIM_IMAGE' in ln:
        indent = ln[:len(ln) - len(ln.lstrip())]
        out.append(indent + 'command: ["--enable", "isaacsim.code_editor.python_server"]')
open(p, 'w').write('\n'.join(out))
print('patched')
