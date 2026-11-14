import { spawnSync } from "node:child_process";
import { randomUUID } from "node:crypto";
import path from "node:path";

export const isWindows = process.platform === "win32";

/// Returns the endpoint mpv should listen on. POSIX uses a Unix socket inside
/// the per-playback temporary directory; Windows requires a named pipe.
export function mpvIpcPath(directory) {
  if (isWindows) {
    return `\\\\.\\pipe\\anime-tui-mpv-${process.pid}-${randomUUID()}`;
  }
  return path.join(directory, "mpv.sock");
}

/// Terminates a process and its children. POSIX children are started in their
/// own process group; Windows has no process groups in the same sense, so
/// taskkill walks the child tree instead.
export function killProcessTree(pid, signal = "SIGTERM") {
  if (!pid) return;
  if (isWindows) {
    const args = ["/PID", String(pid), "/T"];
    if (signal === "SIGKILL") args.push("/F");
    spawnSync("taskkill", args, { windowsHide: true, stdio: "ignore" });
    return;
  }
  try {
    process.kill(-pid, signal);
  } catch (error) {
    if (error.code !== "ESRCH") throw error;
  }
}

/// Windows ignores POSIX detach/process-group semantics and creates extra
/// console windows unless windowsHide is set. Keeping the platform branch in
/// one place avoids a different spawn configuration for every child process.
export function detachedOptions() {
  return { detached: !isWindows, windowsHide: true };
}
