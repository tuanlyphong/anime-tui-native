import fs from "node:fs";
import path from "node:path";
import { chromium } from "playwright";

function getProxyConfig() {
  const proxyUrl =
    process.env.ANIME_TUI_PROXY || process.env.PLAYWRIGHT_PROXY_SERVER;
  if (!proxyUrl) return undefined;
  try {
    const u = new URL(proxyUrl);
    return {
      server: `${u.protocol}//${u.host}`,
      username: u.username || undefined,
      password: u.password || undefined,
    };
  } catch {
    return { server: proxyUrl };
  }
}

function executableCandidates() {
  const explicit = process.env.PLAYWRIGHT_EXECUTABLE_PATH;
  const env = process.env;
  const candidates = [explicit];

  if (process.platform === "win32") {
    const programFiles = env.ProgramFiles;
    const programFilesX86 = env["ProgramFiles(x86)"];
    const localAppData = env.LOCALAPPDATA;
    for (const root of [programFiles, programFilesX86]) {
      if (!root) continue;
      candidates.push(
        path.join(root, "Google", "Chrome", "Application", "chrome.exe"),
        path.join(root, "Microsoft", "Edge", "Application", "msedge.exe"),
        path.join(root, "Chromium", "Application", "chrome.exe"),
      );
    }
    if (localAppData) {
      candidates.push(
        path.join(localAppData, "Google", "Chrome", "Application", "chrome.exe"),
        path.join(localAppData, "Microsoft", "Edge", "Application", "msedge.exe"),
      );
    }
  } else if (process.platform === "darwin") {
    candidates.push(
      "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
      "/Applications/Chromium.app/Contents/MacOS/Chromium",
      "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge",
      "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser",
      "/opt/homebrew/bin/chromium",
      "/usr/local/bin/chromium",
    );
  } else {
    candidates.push(
      "/usr/bin/chromium",
      "/usr/bin/chromium-browser",
      "/usr/bin/google-chrome",
      "/usr/bin/google-chrome-stable",
      "/usr/bin/microsoft-edge",
      "/usr/bin/microsoft-edge-stable",
      "/usr/bin/brave-browser",
      "/snap/bin/chromium",
      "/var/lib/flatpak/exports/bin/com.google.Chrome",
      "/var/lib/flatpak/exports/bin/org.chromium.Chromium",
    );
  }

  return candidates.filter(
    (candidate) => typeof candidate === "string" && candidate.length > 0,
  );
}

/// Launches Chromium through Playwright, preferring a system Chrome/Chromium
/// when one is installed and falling back to Playwright's managed browser.
export async function launchBrowser() {
  const proxy = getProxyConfig();
  for (const executablePath of executableCandidates()) {
    if (!fs.existsSync(executablePath)) continue;
    return chromium.launch({
      headless: true,
      executablePath,
      proxy: proxy || undefined,
    });
  }

  try {
    return await chromium.launch({ headless: true, proxy: proxy || undefined });
  } catch (error) {
    throw new Error(
      "No Chromium browser found. Install Chromium/Google Chrome, or run " +
        "`npx playwright install chromium` once, then try again.",
      { cause: error },
    );
  }
}
