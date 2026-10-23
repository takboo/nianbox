#!/usr/bin/env python3
"""Exercise the shipped image in a disposable, restricted container; no desktop input."""
import argparse
import json
import os
from pathlib import Path
import secrets
import subprocess
import tempfile
import time
import urllib.error
import urllib.request
from uuid import uuid4


def docker(*args):
    return subprocess.check_output(["docker", *args], text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("image")
    args = parser.parse_args()
    name = "nianbox-image-check-" + uuid4().hex[:12]
    volume = name + "-data"
    token = secrets.token_urlsafe(48)
    report = {"image": args.image}
    created_volume = False
    created_container = False
    try:
        docker("volume", "create", volume)
        created_volume = True
        with tempfile.TemporaryDirectory(prefix="nianbox-image-check-") as directory:
            env_file = Path(directory) / "env"
            fd = os.open(env_file, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w") as output:
                output.write(f"NIANBOX_API_TOKEN={token}\nNIANBOX_DB=/data/nianbox.sqlite\n")
            docker("create", "--name", name, "--read-only", "--cap-drop", "ALL",
                   "--security-opt", "no-new-privileges:true", "--pids-limit", "64",
                   "--memory", "128m", "--cpus", "0.5", "--tmpfs", "/tmp:size=16m,mode=1777",
                   "--env-file", str(env_file), "--mount", f"source={volume},target=/data",
                   "--publish", "127.0.0.1::8000", args.image)
            created_container = True
            docker("start", name)
            def endpoint():
                port = json.loads(docker("inspect", name))[0]["NetworkSettings"]["Ports"]["8000/tcp"][0]["HostPort"]
                return f"http://127.0.0.1:{port}"

            base = endpoint()

            def request(path, body=None, authenticated=True, method=None):
                headers = {"Accept": "application/json, text/event-stream"}
                if authenticated:
                    headers["Authorization"] = "Bearer " + token
                if body is not None:
                    headers["Content-Type"] = "application/json"
                req = urllib.request.Request(base + path,
                    data=json.dumps(body).encode() if body is not None else None,
                    headers=headers, method=method)
                with urllib.request.urlopen(req, timeout=10) as response:
                    return json.load(response)

            def ready():
                deadline = time.monotonic() + 45
                while time.monotonic() < deadline:
                    try:
                        request("/health", authenticated=False)
                        return
                    except (OSError, urllib.error.URLError):
                        time.sleep(0.25)
                raise RuntimeError("Container health timeout")

            ready()
            try:
                request("/v1/tasks", authenticated=False)
                raise AssertionError("Anonymous task access succeeded")
            except urllib.error.HTTPError as error:
                assert error.code == 401

            def rpc(method, params):
                response = request("/mcp/", {"jsonrpc": "2.0", "id": 1,
                    "method": method, "params": params})
                assert "error" not in response, response
                return response["result"]

            rpc("initialize", {"protocolVersion": "2025-03-26", "capabilities": {},
                               "clientInfo": {"name": "image-check", "version": "1"}})
            tools = rpc("tools/list", {})["tools"]
            assert {t["name"] for t in tools} >= {
                "list_tasks", "get_task", "create_task", "update_task", "complete_task", "delete_task"}
            operation = {"mutationId": str(uuid4()), "taskId": str(uuid4()), "kind": "create",
                         "baseVersion": 0, "patch": {"title": "Container persistence check"}}
            saved = request("/v1/mutations", operation)
            mcp_id = str(uuid4())
            captured = rpc("tools/call", {"name": "create_task", "arguments": {
                "id": mcp_id, "title": "MCP image check"}})
            assert not captured.get("isError"), captured
            assert request("/v1/tasks/" + mcp_id)["title"] == "MCP image check"
            identity = request("/v1/changes")["serverId"]
            docker("restart", name)
            base = endpoint()
            ready()
            assert request("/v1/mutations", operation) == saved
            assert request("/v1/tasks/" + operation["taskId"]) == saved["task"]
            assert request("/v1/tasks/" + mcp_id)["title"] == "MCP image check"
            assert request("/v1/changes")["serverId"] == identity
            docker("exec", name, "python", "-m", "nianbox", "backup", "/data/check.sqlite")
            docker("exec", name, "python", "-m", "nianbox", "export", "/data/check.json")
            runtime = json.loads(docker("exec", name, "python", "-c", """
import importlib.util, json, os, shutil
from pathlib import Path
assert os.getuid() == 10001 and os.getgid() == 10001
assert importlib.util.find_spec('pytest') is None
assert all(shutil.which(tool) is None for tool in ('gcc', 'g++', 'make', 'git', 'node'))
assert not Path('/app/tests').exists() and not Path('/app/.env').exists()
assert json.loads(Path('/data/check.json').read_text())['tasks']
rss = next(line for line in Path('/proc/1/status').read_text().splitlines() if line.startswith('VmRSS:'))
print(json.dumps({'uid': os.getuid(), 'gid': os.getgid(), 'processRSS': rss, 'python': os.sys.version.split()[0]}))
"""))
            info = json.loads(docker("inspect", name))[0]
            assert info["HostConfig"]["ReadonlyRootfs"]
            assert info["HostConfig"]["CapDrop"] == ["ALL"]
            report.update(runtime=runtime, imageBytes=json.loads(docker("image", "inspect", args.image))[0]["Size"],
                          containerMemoryLimitBytes=info["HostConfig"]["Memory"],
                          checks=["health", "bearer auth", "six MCP tools", "MCP write visible via REST", "REST write", "restart persistence",
                                  "idempotency after restart", "stable server identity", "backup", "export",
                                  "non-root", "read-only root", "no development dependencies"], result="passed")
            print(json.dumps(report, indent=2))
    finally:
        if created_container:
            subprocess.run(["docker", "rm", "--force", name], check=True, stdout=subprocess.DEVNULL)
        if created_volume:
            subprocess.run(["docker", "volume", "rm", volume], check=True, stdout=subprocess.DEVNULL)


if __name__ == "__main__":
    main()
