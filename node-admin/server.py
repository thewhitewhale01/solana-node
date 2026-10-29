#!/usr/bin/env python3
"""node-admin: a small MCP server that lets Claude operate this box.

Exposed over streamable HTTP behind Caddy (TLS). The access key lives in the
URL path, so the only reachable MCP endpoint is /k/<KEY>/mcp. Everything is
logged to /var/log/node-admin/calls.log.

Environment (set in the systemd unit, read from /etc/node-admin/env):
  ADMIN_KEY   long random hex string (required)
  ADMIN_HOST  public hostname Caddy serves, e.g. 84-32-63-98.sslip.io (required)
  BIND_HOST   default 127.0.0.1
  BIND_PORT   default 8808
"""

from __future__ import annotations

import datetime as _dt
import json
import os
import pathlib
import shlex
import subprocess
import sys
import time

from mcp.server.mcpserver import MCPServer
from mcp.server.transport_security import TransportSecuritySettings

ADMIN_KEY = os.environ.get("ADMIN_KEY", "").strip()
ADMIN_HOST = os.environ.get("ADMIN_HOST", "").strip()
BIND_HOST = os.environ.get("BIND_HOST", "127.0.0.1")
BIND_PORT = int(os.environ.get("BIND_PORT", "8808"))

if len(ADMIN_KEY) < 32 or not ADMIN_HOST:
    sys.stderr.write("node-admin: ADMIN_KEY (>=32 chars) and ADMIN_HOST are required\n")
    sys.exit(2)

LOG_DIR = pathlib.Path("/var/log/node-admin")
JOB_DIR = LOG_DIR / "jobs"
LOG_DIR.mkdir(parents=True, exist_ok=True)
JOB_DIR.mkdir(parents=True, exist_ok=True)
CALL_LOG = LOG_DIR / "calls.log"

MAX_OUT = 60_000  # chars returned per tool call
SOL_HOME = "/home/sol"


def _log(tool: str, detail: str) -> None:
    ts = _dt.datetime.now(_dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    with CALL_LOG.open("a") as f:
        f.write(f"{ts} {tool} {detail[:500]}\n")


def _clip(s: str) -> str:
    if len(s) <= MAX_OUT:
        return s
    head = s[: MAX_OUT // 2]
    tail = s[-MAX_OUT // 2 :]
    return f"{head}\n\n... [{len(s) - MAX_OUT} chars clipped] ...\n\n{tail}"


def _sh(cmd: str, timeout: int, cwd: str | None = None, user: str | None = None) -> dict:
    full = cmd
    if user:
        full = f"sudo -u {shlex.quote(user)} -H bash -lc {shlex.quote(cmd)}"
    t0 = time.time()
    try:
        p = subprocess.run(
            full,
            shell=True,
            executable="/bin/bash",
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        return {
            "exit": p.returncode,
            "stdout": _clip(p.stdout),
            "stderr": _clip(p.stderr),
            "seconds": round(time.time() - t0, 2),
        }
    except subprocess.TimeoutExpired as e:
        return {
            "exit": None,
            "stdout": _clip((e.stdout or b"").decode() if isinstance(e.stdout, bytes) else (e.stdout or "")),
            "stderr": f"timed out after {timeout}s (use run_background for long jobs)",
            "seconds": round(time.time() - t0, 2),
        }


mcp = MCPServer(
    name="node-admin",
    instructions=(
        "Operate this Solana RPC node. `run` executes a shell command as root with a "
        "timeout (max 170s); use `run_background` + `job_status` for anything longer "
        "(builds, snapshot downloads). The validator runs as the `sol` user from "
        "/home/sol; its systemd unit is `sol.service`; ledger is /mnt/ledger, accounts "
        "/mnt/accounts. Every call is logged."
    ),
)


@mcp.tool()
def run(cmd: str, timeout: int = 120, cwd: str | None = None, as_user: str | None = None) -> dict:
    """Run a shell command (bash) as root, or as `as_user` (e.g. "sol"). Returns exit code, stdout, stderr.
    timeout is capped at 170 seconds; for longer work use run_background."""
    timeout = max(1, min(int(timeout), 170))
    _log("run", f"user={as_user or 'root'} cwd={cwd or '-'} :: {cmd}")
    return _sh(cmd, timeout, cwd=cwd, user=as_user)


@mcp.tool()
def run_background(name: str, cmd: str, as_user: str | None = None) -> dict:
    """Start a long-running command detached (nohup). Output goes to
    /var/log/node-admin/jobs/<name>.log; check it with job_status or tail. `name` is [a-zA-Z0-9_-]."""
    safe = "".join(c for c in name if c.isalnum() or c in "-_")
    if not safe:
        return {"error": "bad name"}
    log = JOB_DIR / f"{safe}.log"
    pidf = JOB_DIR / f"{safe}.pid"
    inner = cmd
    if as_user:
        inner = f"sudo -u {shlex.quote(as_user)} -H bash -lc {shlex.quote(cmd)}"
    wrapper = (
        f"nohup bash -c {shlex.quote(inner + '; echo \"__EXIT__=$?\"')} "
        f"> {shlex.quote(str(log))} 2>&1 & echo $! > {shlex.quote(str(pidf))}"
    )
    _log("run_background", f"name={safe} user={as_user or 'root'} :: {cmd}")
    subprocess.run(wrapper, shell=True, executable="/bin/bash", check=False)
    time.sleep(0.3)
    pid = pidf.read_text().strip() if pidf.exists() else "?"
    return {"job": safe, "pid": pid, "log": str(log)}


@mcp.tool()
def job_status(name: str, tail_lines: int = 40) -> dict:
    """Status of a run_background job: running or finished (with exit code), plus the last lines of its log."""
    safe = "".join(c for c in name if c.isalnum() or c in "-_")
    log = JOB_DIR / f"{safe}.log"
    pidf = JOB_DIR / f"{safe}.pid"
    if not log.exists():
        return {"error": f"no job named {safe}"}
    pid = pidf.read_text().strip() if pidf.exists() else None
    running = False
    if pid and pid.isdigit():
        running = pathlib.Path(f"/proc/{pid}").exists()
    text = log.read_text(errors="replace")
    exit_code = None
    for line in reversed(text.splitlines()[-5:]):
        if line.startswith("__EXIT__="):
            exit_code = int(line.split("=", 1)[1])
            break
    lines = [l for l in text.splitlines() if not l.startswith("__EXIT__=")]
    _log("job_status", safe)
    return {
        "job": safe,
        "running": running,
        "exit": exit_code,
        "log_bytes": log.stat().st_size,
        "tail": _clip("\n".join(lines[-tail_lines:])),
    }


@mcp.tool()
def read_file(path: str, max_bytes: int = 200_000, offset: int = 0) -> dict:
    """Read a text file (root). Returns up to max_bytes from offset."""
    p = pathlib.Path(path)
    _log("read_file", path)
    if not p.exists():
        return {"error": "not found", "path": path}
    size = p.stat().st_size
    with p.open("rb") as f:
        f.seek(offset)
        data = f.read(max(0, min(max_bytes, 2_000_000)))
    return {"path": path, "size": size, "offset": offset, "content": data.decode(errors="replace")}


@mcp.tool()
def write_file(path: str, content: str, mode: str | None = None, owner: str | None = None, mkdirs: bool = True) -> dict:
    """Write a text file (overwrite). Optional chmod mode like "0644" and chown owner like "sol:sol"."""
    p = pathlib.Path(path)
    _log("write_file", f"{path} ({len(content)} chars)")
    if mkdirs:
        p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(p.suffix + ".tmp-nodeadmin")
    tmp.write_text(content)
    tmp.replace(p)
    if mode:
        os.chmod(p, int(mode, 8))
    if owner:
        subprocess.run(["chown", owner, str(p)], check=False)
    return {"path": path, "bytes": len(content.encode())}


@mcp.tool()
def tail(path: str, lines: int = 100) -> dict:
    """Last N lines of a file (validator log, job logs, journal exports...)."""
    _log("tail", f"{path} n={lines}")
    r = _sh(f"tail -n {int(lines)} {shlex.quote(path)}", 30)
    return {"path": path, "content": r["stdout"], "stderr": r["stderr"]}


@mcp.tool()
def node_status() -> dict:
    """One-shot health view: sol.service state, catch-up vs cluster, disks, memory, load, agave version."""
    _log("node_status", "")
    out: dict[str, str] = {}
    out["service"] = _sh("systemctl is-active sol.service; systemctl show sol.service -p ActiveEnterTimestamp,NRestarts,MainPID", 15)["stdout"]
    out["agave_version"] = _sh("agave-validator --version 2>/dev/null || echo 'agave-validator not on PATH'", 20, user="sol")["stdout"]
    out["catchup"] = _sh(
        "timeout 25 solana catchup --our-localhost 8899 --url https://api.mainnet-beta.solana.com 2>&1 | tail -3",
        30,
        user="sol",
    )["stdout"]
    out["slot_local"] = _sh(
        "curl -s -m 5 http://127.0.0.1:8899 -H 'content-type: application/json' -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getSlot\"}'",
        10,
    )["stdout"]
    out["health"] = _sh(
        "curl -s -m 5 http://127.0.0.1:8899 -H 'content-type: application/json' -d '{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"getHealth\"}'",
        10,
    )["stdout"]
    out["disks"] = _sh("df -h / /mnt/ledger /mnt/accounts /home/sol/snapshots 2>/dev/null", 10)["stdout"]
    out["memory"] = _sh("free -g | head -2", 10)["stdout"]
    out["load"] = _sh("uptime", 10)["stdout"]
    out["log_tail"] = _sh(f"tail -n 15 {SOL_HOME}/log/validator.log 2>/dev/null", 10)["stdout"]
    return out


@mcp.tool()
def service(action: str, unit: str = "sol.service") -> dict:
    """systemctl action on a unit: status|start|stop|restart|enable|disable|journal (journal returns last 200 lines)."""
    action = action.strip().lower()
    allowed = {"status", "start", "stop", "restart", "enable", "disable", "journal"}
    if action not in allowed:
        return {"error": f"action must be one of {sorted(allowed)}"}
    _log("service", f"{action} {unit}")
    if action == "journal":
        return _sh(f"journalctl -u {shlex.quote(unit)} -n 200 --no-pager", 30)
    return _sh(f"systemctl {action} {shlex.quote(unit)} --no-pager 2>&1 | head -60", 60)


if __name__ == "__main__":
    security = TransportSecuritySettings(
        enable_dns_rebinding_protection=True,
        allowed_hosts=[ADMIN_HOST, f"{ADMIN_HOST}:*", "127.0.0.1:*", "localhost:*"],
        allowed_origins=[f"https://{ADMIN_HOST}", "https://claude.ai", "https://claude.com"],
    )
    sys.stderr.write(f"node-admin listening on {BIND_HOST}:{BIND_PORT} path /k/<key>/mcp host={ADMIN_HOST}\n")
    mcp.run(
        transport="streamable-http",
        host=BIND_HOST,
        port=BIND_PORT,
        streamable_http_path=f"/k/{ADMIN_KEY}/mcp",
        json_response=True,
        stateless_http=True,
        transport_security=security,
    )
