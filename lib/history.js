import fs from "fs";
import os from "os";
import path from "path";

const DATA_DIR = path.join(os.homedir(), ".local", "share", "anime-tui");
const HISTORY_FILE = path.join(DATA_DIR, "history.json");

function ensureFile() {
  fs.mkdirSync(DATA_DIR, { recursive: true });

  if (!fs.existsSync(HISTORY_FILE)) {
    fs.writeFileSync(HISTORY_FILE, "[]");
  }
}

function cleanTitle(title) {
  return title.replace(/\s*\[(?:Tập|Episode|Ep)\s*[^\]]+\]\s*$/i, "").trim();
}

function episodeNumber(ep) {
  if (!ep) return 0;

  const match = ep.match(/\d+/);
  return match ? Number(match[0]) : 0;
}

export function loadHistory() {
  ensureFile();

  try {
    const history = JSON.parse(fs.readFileSync(HISTORY_FILE, "utf8"));

    // Clean old polluted titles automatically and ensure `completed` exists
    return history.map((item) => ({
      ...item,
      title: cleanTitle(item.title),
      completed: item.completed ?? false,
    }));
  } catch {
    return [];
  }
}

export function saveHistory(history) {
  ensureFile();

  fs.writeFileSync(HISTORY_FILE, JSON.stringify(history, null, 2));
}

export function addHistory({ title, url, poster, latestEpisode }) {
  const history = loadHistory();

  const entry = {
    title: cleanTitle(title),
    url,
    poster,
    latestEpisode,
    updated: Date.now(),
    completed: false,
  };

  const idx = history.findIndex((anime) => anime.url === url);

  if (idx >= 0) {
    const existing = history[idx];

    const existingEp = episodeNumber(existing.latestEpisode);
    const newEp = episodeNumber(latestEpisode);

    const shouldReplace =
      newEp > existingEp ||
      (newEp === existingEp && entry.updated > existing.updated);

    if (shouldReplace) {
      // preserve completed flag from existing entry
      history[idx] = { ...entry, completed: existing.completed ?? false };
    }
  } else {
    history.push(entry);
  }

  history.sort((a, b) => {
    const epDiff =
      episodeNumber(b.latestEpisode) - episodeNumber(a.latestEpisode);

    if (epDiff !== 0) {
      return epDiff;
    }

    return b.updated - a.updated;
  });

  saveHistory(history);
}

export function setCompleted(url, completed = true) {
  const history = loadHistory();
  const idx = history.findIndex((anime) => anime.url === url);
  if (idx === -1) return false;
  history[idx].completed = completed;
  history[idx].updated = Date.now();
  saveHistory(history);
  return true;
}

function sortHistory(history) {
  history.sort((a, b) => {
    const epDiff =
      episodeNumber(b.latestEpisode) - episodeNumber(a.latestEpisode);

    if (epDiff !== 0) {
      return epDiff;
    }

    return (b.updated ?? 0) - (a.updated ?? 0);
  });
  return history;
}

// Merge a JSON array exported by another device. Imported entries win over
// local ones with the same URL, so a manual import is a deliberate replace.
export function importHistory(file) {
  const incoming = JSON.parse(fs.readFileSync(file, "utf8"));
  if (!Array.isArray(incoming)) {
    throw new Error("history import must be a JSON array");
  }

  const history = loadHistory();
  const byUrl = new Map(
    history.filter((item) => item.url).map((item) => [item.url, item]),
  );

  for (const item of incoming) {
    if (!item || typeof item.url !== "string" || item.url.trim() === "") {
      continue;
    }

    byUrl.set(item.url, {
      title: cleanTitle(String(item.title ?? "Unknown")),
      url: item.url,
      poster: String(item.poster ?? ""),
      latestEpisode: String(item.latestEpisode ?? ""),
      updated: Number.isFinite(item.updated) ? item.updated : Date.now(),
      completed:
        item.completed === true ||
        item.completed === 1 ||
        item.completed === "true",
    });
  }

  saveHistory(sortHistory([...byUrl.values()]));
}

export function printHistory(completedOnly = false) {
  const history = loadHistory();

  const items = history.filter((h) => (completedOnly ? h.completed : !h.completed));

  for (const anime of items) {
    console.log(
      `${anime.title} [${anime.latestEpisode}]\t${anime.url}\t${anime.poster}`,
    );
  }
}
