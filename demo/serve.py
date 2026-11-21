"""Serve the Flatland evidence dashboard on loopback."""

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import subprocess
from urllib.parse import urlsplit


DEMO = Path(__file__).resolve().parent
REPO = DEMO.parent
ASSETS = {
    "/": (DEMO / "index.html", "text/html"),
    "/style.css": (DEMO / "style.css", "text/css"),
    "/app.js": (DEMO / "app.js", "text/javascript"),
    "/evidence/application-checks.json": (REPO / "evidence" / "application-checks.json", "application/json"),
    **{
        f"/evidence/{layout}.log": (REPO / "evidence" / f"integration-{layout}.log", "text/plain")
        for layout in ("flat", "segmented")
    },
}


def compose(layout, *args):
    output = subprocess.run(
        ["docker", "compose", "-p", f"flatland-{layout}", "-f", "lab/compose.services.yaml",
         "-f", f"lab/compose.{layout}.yaml", *args],
        cwd=REPO, capture_output=True, encoding="utf-8", errors="replace", timeout=5, check=True,
    )
    return output.stdout


def live_status(layout):
    try:
        rows = compose(layout, "ps", "--all", "--format", "{{.Service}}|{{.State}}|{{.Health}}")
    except (OSError, subprocess.SubprocessError):
        return {"error": "Could not read the local Docker project."}

    services = [dict(zip(("name", "state", "health"), row.split("|")))
                for row in rows.splitlines() if row.count("|") == 2]
    result = {"services": services, "drops": []}
    if any(service["name"] == "router" and service["state"] == "running" for service in services):
        try:
            logs = compose(layout, "logs", "--no-color", "--no-log-prefix", "--timestamps",
                           "--tail", "60", "router")
            result["drops"] = [line for line in logs.splitlines()
                               if "flatland-forward-drop" in line][-12:]
        except (OSError, subprocess.SubprocessError):
            result["logsError"] = "Could not read the router log. The dashboard will retry."
    return result


class DashboardHandler(BaseHTTPRequestHandler):
    def send_content(self, content, content_type):
        self.send_response(200)
        self.send_header("Content-Type", f"{content_type}; charset=utf-8")
        self.send_header("Content-Length", str(len(content)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Content-Security-Policy",
                         "default-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'")
        self.end_headers()
        try:
            self.wfile.write(content)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        port = self.server.server_port
        if self.headers.get("Host") not in {f"127.0.0.1:{port}", f"localhost:{port}"}:
            self.send_error(400)
            return
        path = urlsplit(self.path).path
        if path in ASSETS:
            file, content_type = ASSETS[path]
            try:
                content = file.read_bytes()
            except OSError:
                self.send_error(404)
                return
            self.send_content(content, content_type)
        elif path in {"/live/flat", "/live/segmented"}:
            data = live_status(path.rsplit("/", 1)[-1])
            self.send_content(json.dumps(data).encode("utf-8"), "application/json")
        else:
            self.send_error(404)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=8765)
    args = parser.parse_args()
    with ThreadingHTTPServer(("127.0.0.1", args.port), DashboardHandler) as server:
        print(f"Flatland dashboard: http://127.0.0.1:{server.server_port}/", flush=True)
        try:
            server.serve_forever()
        except KeyboardInterrupt:
            pass
