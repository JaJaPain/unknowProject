"""Run a local Python file in the user's Blender MCP session."""
import json
import socket
import sys
from pathlib import Path

with socket.create_connection(('127.0.0.1', 9876), 10) as connection:
    connection.settimeout(600)
    connection.sendall(json.dumps({'type': 'execute_code', 'params': {
        'code': Path(sys.argv[1]).read_text(encoding='utf-8')}}).encode())
    data = b''
    while True:
        chunk = connection.recv(65536)
        if not chunk:
            raise RuntimeError('Blender closed the connection before returning JSON')
        data += chunk
        try:
            result = json.loads(data)
            break
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue
    print(json.dumps(result, indent=2))
    if result.get('status') != 'success':
        sys.exit(1)
