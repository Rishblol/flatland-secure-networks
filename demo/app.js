const hosts = {
  workstation: ["Workstation", "10.149.240.10"],
  web: ["Web server", "10.149.240.74"],
  app: ["Application", "10.149.240.138"],
  database: ["Database", "10.149.240.139"],
  file: ["File server", "10.149.240.140"],
  jump: ["Jump host", "10.149.240.202"],
};
const zones = [
  ["User", "10.149.240.0/26", ["workstation"]],
  ["DMZ", "10.149.240.64/26", ["web"]],
  ["Server", "10.149.240.128/26", ["app", "database", "file"]],
  ["Management", "10.149.240.192/26", ["jump"]],
];
const business = [
  ["B01", "HTTPS to web", "workstation", "web", "TCP 443"],
  ["B02", "HTTP to application", "web", "app", "TCP 8080"],
  ["B03", "PostgreSQL query", "app", "database", "TCP 5432"],
  ["B04", "SSH to workstation", "jump", "workstation", "TCP 22"],
  ["B05", "SSH to web", "jump", "web", "TCP 22"],
  ["B06", "SSH to application", "jump", "app", "TCP 22"],
  ["B07", "SSH to database", "jump", "database", "TCP 22"],
  ["B08", "SSH to file server", "jump", "file", "TCP 22"],
];
const security = [
  ["S01-app", "Application port", "workstation", "app", "TCP 8080"],
  ["S01-database", "PostgreSQL port", "workstation", "database", "TCP 5432"],
  ["S01-file", "File server port", "workstation", "file", "TCP 445"],
  ["S02", "Database SSH", "workstation", "database", "TCP 22"],
  ["S03", "SMB share", "workstation", "file", "TCP 445"],
  ["S04", "Synthetic SMB copy", "workstation", "file", "TCP 445"],
  ["L01", "Firewall log correlation", null, null, null],
];
const evidence = {};
let applicationEvidence;
let layout = "segmented";
let filter = "security";
let selected = security[0][0];

const byId = (id) => document.getElementById(id);
function element(tag, value, className) {
  const result = document.createElement(tag);
  if (value) result.textContent = value;
  if (className) result.className = className;
  return result;
}

function parseLog(text) {
  const records = {};
  let current;
  for (const line of text.split(/\r?\n/)) {
    const record = line.match(/^((?:B|S)\d+(?:-[\w]+)?|L01) (PASS|FAIL|INCONCLUSIVE|NOT_RUN|BASELINE)\b/);
    if (record) {
      const timestamp = line.match(/\d{4}-\d\d-\d\dT[\d:.]+Z/)?.[0];
      current = { status: record[2], line, timestamp, details: [], drops: [] };
      records[record[1]] = current;
    } else if (current && line.startsWith("  ")) {
      current.details.push(line.trim());
    } else if (current && line.includes(" flatland-forward-drop ")) {
      current.drops.push(line);
    } else {
      current = undefined;
    }
  }
  return { records, revision: text.match(/revision=([\da-f]+)/)?.[1], drops: text.split(/\r?\n/).filter((line) => line.includes(" flatland-forward-drop ")) };
}

function statusFor(id) {
  const application = applicationEvidence?.[layout]?.[id];
  if (application) return application.status;
  const status = evidence[layout]?.records[id]?.status;
  if (!status) return "Unavailable";
  if (status === "NOT_RUN") return "Not run";
  if (status === "BASELINE") return "Baseline";
  if (status !== "PASS") return status === "FAIL" ? "Failed" : "Inconclusive";
  if (id.startsWith("S")) return layout === "segmented" ? "Blocked" : "Reachable";
  return "Passed";
}

function renderMap(row) {
  const [, , source, destination] = row;
  const flat = layout === "flat";
  const map = byId("map");
  const hub = element("div", flat ? "Shared Docker bridge" : "Firewall router", "hub");
  hub.append(element("small", flat ? "flatland-flat_flat" : "nftables · inter-zone traffic"));
  const group = element("div", "", "network-groups");
  const layoutZones = flat ? [["Shared network", "", Object.keys(hosts)]] : zones;
  group.classList.toggle("flat", flat);
  for (const [name, subnet, members] of layoutZones) {
    const zone = element("div", "", "zone");
    const box = element("div", "", "zone-layout");
    const title = element("div", "", "zone-title");
    title.append(element("strong", name), element("code", subnet));
    const list = element("div", "", "host-list");
    for (const key of members) {
      const [label, ip] = hosts[key];
      const host = element("div", "", "host");
      host.dataset.service = key;
      if (key === source) host.classList.add("source");
      if (key === destination) host.classList.add(statusFor(row[0]) === "Blocked" ? "blocked" : "destination");
      const identity = element("div");
      identity.append(element("strong", label), element("small", flat ? key : ip));
      const icon = element("i");
      icon.setAttribute("aria-hidden", "true");
      host.append(icon, identity);
      list.append(host);
    }
    box.append(title, list);
    zone.append(box);
    group.append(zone);
  }
  map.replaceChildren(hub, group);
  renderRuntime();
  byId("topology-caption").textContent = flat ? "Six workloads share one directly connected network." : "Cross-zone connections pass through the router.";
  byId("topology-policy").textContent = flat ? "Flat baseline" : "Default deny";
  byId("map-summary").textContent = flat ? "1 shared network" : "4 zones · 1 router";
}

function renderDetail(row) {
  const [id, title, source, destination, port] = row;
  const capture = evidence[layout];
  const record = capture?.records[id];
  const detail = byId("evidence-detail");
  const underlying = id === "S03" ? capture?.records["S01-file"] : record;
  byId("capture").textContent = capture?.revision ? `Integration run · ${capture.revision.slice(0, 7)}` : "Recorded integration run";
  byId("raw-log").href = `/evidence/${layout}.log`;
  detail.replaceChildren(element("h3", `${id} · ${title}`));
  if (source) detail.append(element("p", `${hosts[source][0]} to ${hosts[destination][0]} · ${port}`));
  const application = applicationEvidence?.[layout]?.[id];
  if (application) {
    byId("capture").textContent = `Application check · ${applicationEvidence.revision.slice(0, 7)}`;
    byId("raw-log").href = "/evidence/application-checks.json";
    appendTimestamp(detail, application.timestamp);
    detail.append(element("p", application.summary), element("pre", application.output));
    if (application.drop) {
      const router = element("details", "", "router-evidence");
      router.append(element("summary", "Matching firewall drop"), element("pre", application.drop));
      detail.append(router);
    }
    return;
  }
  if (!record) {
    detail.append(element("p", "Evidence unavailable for this check."));
    return;
  }
  if (underlying?.timestamp) appendTimestamp(detail, underlying.timestamp);
  if (id === "S02") detail.append(element("p", "TCP reachability only. Workstation SSH authentication remains unverified."));
  if (id === "S03") detail.append(element("p", "Uses the S01-file TCP result and local share health. Workstation share access remains unverified."));
  if (id === "S04") detail.append(element("p", "The end-to-end copy was not run. The source fixture was available and the destination was absent before and after the check."));
  if (id === "B03" && layout === "segmented") detail.append(element("p", "This flow stays inside the Server zone and takes the direct route."));
  const drops = id === "L01" ? capture.drops : underlying?.drops;
  if (drops?.length) {
    detail.append(element("p", `${drops.length} matching router log ${drops.length === 1 ? "line" : "lines"}`));
    detail.append(element("pre", drops.join("\n\n"), "drop-log"));
  } else {
    const lines = id === "S04" ? [record.line, capture.records["S04-FIXTURE"]?.line] : [record.line, ...(underlying?.details ?? [])];
    detail.append(element("pre", lines.filter(Boolean).join("\n")));
  }
}

function appendTimestamp(container, timestamp) {
  const time = element("time", timestamp.replace("T", " ").replace(/(?:\.\d+)?Z$/, " UTC"));
  time.dateTime = timestamp;
  container.append(time);
}

function render(restoreFocus = false) {
  const rows = filter === "business" ? business : security;
  const row = rows.find(([id]) => id === selected);
  const capture = evidence[layout];
  if (capture) {
    const passed = business.filter(([id]) => statusFor(id) === "Passed").length;
    const matched = ["S01-app", "S01-database", "S01-file", "S02"].filter((id) => capture.records[id]?.status === "PASS").length;
    byId("results-summary").textContent = `${passed}/8 business flows passed · ${matched}/4 TCP probes ${layout === "flat" ? "connected" : "blocked"}`;
  } else {
    byId("results-summary").textContent = "Integration evidence could not be loaded.";
  }
  const list = byId("results-list");
  list.replaceChildren();
  for (const [id, title] of rows) {
    const item = element("li");
    const button = element("button", "", "result");
    const status = statusFor(id);
    button.type = "button";
    button.setAttribute("aria-pressed", String(id === selected));
    button.append(element("span", id, "id"), element("span", title), element("span", status, `status ${status.toLowerCase().replace(" ", "-")}`));
    button.addEventListener("click", () => {
      resetReplay();
      selected = id;
      render(true);
    });
    item.append(button);
    list.append(item);
    if (restoreFocus && id === selected) button.focus({ preventScroll: true });
  }
  renderMap(row);
  renderDetail(row);
}

let liveTimer;
let runtime;
let liveRequest;

function renderRuntime() {
  const indicator = byId("live-indicator");
  const services = runtime?.services ?? [];
  const running = services.filter((service) => service.state === "running");
  const expected = layout === "flat" ? 6 : 7;
  const ready = running.filter(({ health }) => health === "healthy" || !health).length;
  const status = !runtime ? "Checking Docker" : runtime.error ? "Docker unavailable" :
    !running.length ? "Lab offline" : ready === expected ? "Live · ready" :
      services.some(({ health }) => health === "starting") ? "Live · starting" : "Live · attention";
  indicator.dataset.state = ready === expected ? "live" : running.length ? "partial" : "pending";
  if (byId("live-status").textContent !== status) byId("live-status").textContent = status;
  byId("map-runtime").textContent = runtime ? `${ready}/${expected} containers ready` : "Checking container health";
  byId("live-message").textContent = runtime?.error ?? (runtime ?
    (running.length ? `flatland-${layout} · updates every 5 seconds` : `flatland-${layout} is not running.`) :
    "Reading local Docker…");

  for (const host of document.querySelectorAll("[data-service]")) {
    const service = services.find(({ name }) => name === host.dataset.service);
    host.dataset.health = !service ? "unknown" : service.state === "running" &&
      (service.health === "healthy" || !service.health) ? "ready" : "unready";
    host.title = service ? `${service.name} · ${service.health || service.state}` : "Live health unavailable";
  }
  byId("live-services").replaceChildren(...services.map(({ name, state, health }) =>
    element("span", `${name} · ${health || state}`)));

  const logs = byId("live-log");
  const drops = runtime?.drops ?? [];
  const logText = drops.join("\n\n");
  byId("live-logs").hidden = layout !== "segmented" || !running.some(({ name }) => name === "router");
  byId("live-log-empty").hidden = drops.length > 0;
  byId("live-log-empty").textContent = runtime?.logsError ?? "No drop events in the current router log.";
  logs.hidden = !drops.length;
  if (logs.textContent !== logText) logs.textContent = logText;
}

async function refreshLive() {
  clearTimeout(liveTimer);
  liveRequest?.abort();
  const request = new AbortController();
  liveRequest = request;
  try {
    const response = await fetch(`/live/${layout}`, { signal: request.signal });
    if (!response.ok) throw new Error();
    const data = await response.json();
    if (request !== liveRequest) return;
    runtime = data;
  } catch {
    if (request !== liveRequest) return;
    runtime = { error: "Live Docker status is unavailable." };
  }
  renderRuntime();
  liveTimer = setTimeout(refreshLive, 5000);
}

let replayFrame;
let replayTimer;
let replayActive = false;
const reducedMotion = matchMedia("(prefers-reduced-motion: reduce)");
const replayModes = ["flat", "segmented"];
const chart = {};
const replayButton = byId("replay-play");
const replayStep = byId("replay-step");
const replayRows = () => filter === "business" ? business : security.filter((row) => row[2]);

function stopReplay() {
  replayActive = false;
  cancelAnimationFrame(replayFrame);
  clearTimeout(replayTimer);
  replayButton.textContent = "Play comparison";
}

function resetReplay() {
  stopReplay();
  const rows = replayRows();
  const category = filter === "business" ? "Business flows" : "Workstation checks";
  byId("replay-scope").textContent = `${category} · recorded outcomes`;
  replayButton.disabled = !replayModes.every((mode) => evidence[mode]);
  replayStep.textContent = replayButton.disabled ? "Both evidence captures are needed for playback." : "Watch each check in Flat and Segmented.";
  for (const mode of replayModes) {
    chart[mode] = { reached: 0, blocked: 0, other: 0 };
    byId(`replay-${mode}`).max = rows.length;
    updateReplayChart(mode);
  }
}

function updateReplayChart(mode) {
  const { reached, blocked, other } = chart[mode];
  byId(`replay-${mode}`).value = reached;
  byId(`replay-${mode}-text`).textContent =
    `${reached} reached · ${blocked} blocked${other ? ` · ${other} unresolved` : ""}`;
}

function routeType(mode, row, outcome) {
  if (mode === "flat") return "bridge";
  const sourceZone = zones.findIndex(([, , members]) => members.includes(row[2]));
  const destZone = zones.findIndex(([, , members]) => members.includes(row[3]));
  if (sourceZone === destZone) return "direct";
  return outcome === "blocked" ? "drop" : "routed";
}

function animatePath(row, route, duration, onComplete) {
  const map = byId("map");
  const canvas = element("canvas", "", "traffic-path");
  canvas.setAttribute("aria-hidden", "true");
  map.append(canvas);
  const ctx = canvas.getContext("2d");
  const started = performance.now();
  const point = (node, origin, top = false) => {
    const bounds = node.getBoundingClientRect();
    return [bounds.left + bounds.width / 2 - origin.left, (top ? bounds.top : bounds.bottom) - origin.top];
  };
  const at = (service) => map.querySelector(`[data-service="${service}"]`);
  const stroke = (points) => {
    ctx.beginPath();
    ctx.moveTo(...points[0]);
    for (const p of points.slice(1)) ctx.lineTo(...p);
    ctx.stroke();
  };

  function frame(now) {
    const fraction = Math.min(1, (now - started) / duration);
    if (ctx) {
      const origin = map.getBoundingClientRect();
      const dpr = window.devicePixelRatio || 1;
      const width = Math.round(origin.width * dpr);
      const height = Math.round(origin.height * dpr);
      if (canvas.width !== width) canvas.width = width;
      if (canvas.height !== height) canvas.height = height;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, origin.width, origin.height);
      const source = point(at(row[2]), origin, true);
      const destination = point(at(row[3]), origin, true);
      const hub = point(map.querySelector(".hub"), origin);
      const points = route === "drop" ? [source, hub] : route === "direct" ? [source, destination] : [source, hub, destination];
      const leg = Math.min(points.length - 2, Math.floor(fraction * (points.length - 1)));
      const progress = fraction * (points.length - 1) - leg;
      const marker = points[leg].map((value, axis) => value + (points[leg + 1][axis] - value) * progress);
      const color = getComputedStyle(map).getPropertyValue(route === "drop" && fraction === 1 ? "--red" : "--green").trim();
      ctx.strokeStyle = color;
      ctx.lineWidth = 2;
      ctx.globalAlpha = .8;
      stroke([...points.slice(0, leg + 1), marker]);
      ctx.globalAlpha = 1;
      ctx.fillStyle = color;
      ctx.beginPath();
      ctx.arc(...marker, 4.5, 0, Math.PI * 2);
      ctx.fill();
    }
    if (fraction < 1 && !reducedMotion.matches) replayFrame = requestAnimationFrame(frame);
    else if (replayActive) onComplete();
  }
  frame(reducedMotion.matches ? started + duration : started);
}

function setLayout(mode) {
  if (layout !== mode) {
    layout = mode;
    runtime = undefined;
    document.querySelector(`input[name=layout][value="${mode}"]`).checked = true;
    refreshLive();
  }
  render();
}

function playComparison() {
  const rows = replayRows();
  const sequence = replayModes.flatMap((mode) => rows.map((row) => [mode, row]));
  resetReplay();
  replayActive = true;
  replayButton.textContent = "Stop replay";
  let index = 0;

  function next() {
    if (index === sequence.length) {
      stopReplay();
      replayStep.textContent = "Comparison complete. Counts reflect the recorded checks.";
      return;
    }
    const [mode, row] = sequence[index++];
    selected = row[0];
    setLayout(mode);
    const result = statusFor(row[0]);
    const outcome = result === "Blocked" ? "blocked" : ["Passed", "Reachable"].includes(result) ? "reached" : "other";
    const route = routeType(mode, row, outcome);
    const label = `${mode === "flat" ? "Flat" : "Segmented"} · ${row[0]} · ${row[1]}`;
    replayStep.textContent = label;
    const settle = () => {
      chart[mode][outcome]++;
      updateReplayChart(mode);
      const description = {
        drop: "Dropped at the router",
        direct: "Direct within the Server zone",
        bridge: "Reached over the shared bridge",
        routed: "Allowed through the router",
      };
      replayStep.textContent = `${label} · ${outcome === "other" ? result : description[route]}`;
      replayTimer = setTimeout(next, 620);
    };
    if (outcome === "other") settle();
    else animatePath(row, route, 520, settle);
  }
  next();
}

replayButton.addEventListener("click", () => {
  if (replayActive) {
    stopReplay();
    byId("map").querySelector(".traffic-path")?.remove();
    replayStep.textContent = "Replay stopped.";
  } else {
    playComparison();
  }
});

document.querySelectorAll("input[name=layout]").forEach((input) => input.addEventListener("change", () => {
  resetReplay();
  setLayout(input.value);
}));
document.querySelectorAll("[data-filter]").forEach((button) => button.addEventListener("click", () => {
  filter = button.dataset.filter;
  selected = (filter === "business" ? business : security)[0][0];
  resetReplay();
  document.querySelectorAll("[data-filter]").forEach((tab) => tab.setAttribute("aria-pressed", String(tab === button)));
  render();
}));
byId("live-indicator").addEventListener("click", () => { byId("runtime").open = true; });
refreshLive();

const loadCapture = async (mode) => {
  const response = await fetch(`/evidence/${mode}.log`);
  if (!response.ok) throw new Error();
  evidence[mode] = parseLog(await response.text());
};
const loadApplicationChecks = async () => {
  const response = await fetch("/evidence/application-checks.json");
  if (!response.ok) throw new Error();
  applicationEvidence = await response.json();
};
Promise.allSettled([loadCapture("flat"), loadCapture("segmented"), loadApplicationChecks()]).then(() => {
  render();
  resetReplay();
});
