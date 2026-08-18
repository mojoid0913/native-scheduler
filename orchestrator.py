#!/usr/bin/env python3
"""
NativeScheduler FIFO Orchestrator
-----------------------------------
Interactive mode — no API calls. Opens claude in each tmux window,
then sends the prompt as keystrokes.

Pipeline:
  [Boot]    PM reads prompt.md + assigns first task
  [Loop]    Dev+Des -> Reviewer -> PM -> repeat
  [Version] PM signals version done -> user feedback -> loop or exit
  [Exit]    PM signals project complete -> exit

FIFO signals:
  /tmp/ns_agent_pm            <- PM done
  /tmp/ns_agent_developer     <- developer done
  /tmp/ns_agent_designer      <- designer done
  /tmp/ns_agent_reviewer      <- reviewer done
  /tmp/ns_version_complete    <- PM: version done
  /tmp/ns_project_complete    <- PM: project fully done
"""

import os
import subprocess
import threading
import argparse
import textwrap
import time
from datetime import datetime

SESSION     = "native_schedular"
PROJECT_DIR = os.path.expanduser("~/Projects/native_schedular")

WINDOWS = {
    "orchestrator": 0,
    "pm":           1,
    "developer":    2,
    "designer":     3,
    "reviewer":     4,
}

AGENTS = {
    "pm":        "project-advisor-reviewer",
    "developer": "cs-dev-optimizer",
    "designer":  "senior-ui-designer",
    "reviewer":  "reviewer",
}

FIFOS         = {name: f"/tmp/ns_agent_{name}" for name in AGENTS}
VERSION_FIFO  = "/tmp/ns_version_complete"
COMPLETE_FIFO = "/tmp/ns_project_complete"

CLAUDE_BOOT_WAIT = 3   # seconds to wait for claude to open


# ── FIFO helpers ──────────────────────────────────────────────────────────────

def make_fifo(path):
    if os.path.exists(path):
        os.remove(path)
    os.mkfifo(path)

def make_all_fifos():
    for path in FIFOS.values():
        make_fifo(path)
    make_fifo(VERSION_FIFO)
    make_fifo(COMPLETE_FIFO)

def reset_fifo(name):
    make_fifo(FIFOS[name])

def check_fifo_nonblock(path):
    import select
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        r, _, _ = select.select([fd], [], [], 0)
        if r:
            os.read(fd, 64)
            os.close(fd)
            return True
        os.close(fd)
    except OSError:
        pass
    return False

def wait_fifo(name):
    with open(FIFOS[name], "r") as f:
        return f.read().strip()

def wait_pm():
    """Block on PM FIFO, watch version/complete signals simultaneously."""
    result = [None]
    stop   = threading.Event()

    def _watch():
        while not stop.is_set():
            if check_fifo_nonblock(COMPLETE_FIFO):
                result[0] = "complete"
                stop.set()
                return
            if check_fifo_nonblock(VERSION_FIFO):
                result[0] = "version"
                stop.set()
                return
            time.sleep(0.3)

    t = threading.Thread(target=_watch, daemon=True)
    t.start()
    with open(FIFOS["pm"], "r") as f:
        f.read()
    stop.set()
    t.join()
    return result[0] or "done"


# ── Tmux helpers ──────────────────────────────────────────────────────────────

def tmux(cmd):
    r = subprocess.run(f"tmux {cmd}", shell=True, capture_output=True, text=True)
    return r.stdout.strip()

def session_exists():
    out = subprocess.run(
        "tmux list-sessions -F '#{session_name}' 2>/dev/null",
        shell=True, capture_output=True, text=True
    ).stdout
    return SESSION in out

def create_session():
    if session_exists():
        log("tmux", f"Session '{SESSION}' already exists — reusing.")
        return
    log("tmux", f"Creating session '{SESSION}'...")
    tmux(f"new-session -d -s {SESSION} -n orchestrator -c '{PROJECT_DIR}'")
    for name, idx in WINDOWS.items():
        if idx == 0:
            continue
        tmux(f"new-window -t {SESSION}:{idx} -n {name} -c '{PROJECT_DIR}'")
    log("tmux", "Done.")

def send_keys(window, text):
    """Send raw keystrokes to a tmux window."""
    idx  = WINDOWS[window]
    safe = text.replace("'", "'\\''")
    tmux(f"send-keys -t {SESSION}:{idx} '{safe}' Enter")

def clear_win(window):
    tmux(f"send-keys -t {SESSION}:{WINDOWS[window]} 'clear' Enter")

def is_claude_running(window):
    """Check if claude is already open in this window."""
    idx = WINDOWS[window]
    out = tmux(f"display-message -t {SESSION}:{idx} -p '#{pane_current_command}'")
    return "claude" in out.lower()


# ── Logging ───────────────────────────────────────────────────────────────────

def log(tag, msg):
    ts = datetime.now().strftime("%H:%M:%S")
    print(f"[{ts}][{tag}] {msg}", flush=True)


# ── Agent launchers ───────────────────────────────────────────────────────────
def open_claude(window):
    clear_win(window)
    time.sleep(0.3)
    send_keys(window, f"cd '{PROJECT_DIR}' && claude --dangerously-skip-permissions")
    log(window, "Opening claude...")
    time.sleep(CLAUDE_BOOT_WAIT)
    # bypass permissions 확인창 자동 수락
    send_keys(window, "2")
    time.sleep(1)

def send_prompt(window, prompt):
    """Write prompt to temp file and send via @-mention."""
    # Write prompt to file to avoid shell escaping issues
    tmp = f"/tmp/ns_prompt_{window}.txt"
    with open(tmp, "w") as f:
        f.write(prompt)
    # Send as single line
    send_keys(window, prompt)

def launch(window, extra=""):
    """Open claude and send task prompt."""
    agent      = AGENTS[window]
    fifo       = FIFOS[window]
    signal_cmd = f"echo DONE > {fifo}"

    prompt = (
        f"@{agent} 본인의 역할을 수행하시오."
    )
    if extra:
        prompt += f" {extra}"
    prompt += f" 완료 후 반드시 실행: `{signal_cmd}`"

    open_claude(window)
    log(window, f"→ @{agent}")
    send_prompt(window, prompt)

def run(window, extra=""):
    reset_fifo(window)
    launch(window, extra)
    sig = wait_fifo(window)
    log(window, f"✅ done ({sig})")

def run_parallel_devdes():
    for w in ["developer", "designer"]:
        reset_fifo(w)
    for w in ["developer", "designer"]:
        launch(w)
    threads = []
    def _wait(w):
        sig = wait_fifo(w)
        log(w, f"✅ done ({sig})")
    for w in ["developer", "designer"]:
        t = threading.Thread(target=_wait, args=(w,), daemon=True)
        t.start()
        threads.append(t)
    for t in threads:
        t.join()

def run_pm(extra=""):
    """Run PM and return signal: 'done' | 'version' | 'complete'"""
    reset_fifo("pm")
    make_fifo(VERSION_FIFO)
    make_fifo(COMPLETE_FIFO)

    signals = (
        f" 완료 후 다음 중 하나만 실행:"
        f" 태스크 배분 완료시: `echo DONE > {FIFOS['pm']}`,"
        f" 버전 완성시: `echo DONE > {VERSION_FIFO}`,"
        f" 프로젝트 완전 종료시: `echo DONE > {COMPLETE_FIFO}`"
    )

    agent = AGENTS["pm"]
    prompt = f"@{agent} 본인의 역할을 수행하시오."
    if extra:
        prompt += f" {extra}"
    prompt += signals

    open_claude("pm")
    log("pm", f"→ @{agent}")
    send_prompt("pm", prompt)

    signal = wait_pm()
    log("pm", f"✅ done (signal={signal})")
    return signal


# ── User feedback ─────────────────────────────────────────────────────────────

def request_user_feedback():
    print("\n" + "━" * 56)
    print("  ✅ Version complete.")
    print("  Build and test. Enter feedback or press Enter to finish.")
    print("━" * 56)
    try:
        feedback = input("  feedback> ").strip()
    except (KeyboardInterrupt, EOFError):
        feedback = ""
    print("━" * 56 + "\n")
    return feedback or None


# ── Pipeline ──────────────────────────────────────────────────────────────────

def pipeline(user_task=None):
    sep   = "─" * 56
    cycle = 0

    log("pipeline", sep)
    log("pipeline", f"Boot — {user_task or 'PM decides from prompt.md'}")
    log("pipeline", sep)

    boot_extra = f"유저 요청: {user_task}" if user_task else ""
    signal = run_pm(boot_extra)

    if signal == "complete":
        log("pipeline", "🏁 Done.")
        return
    if signal == "version":
        feedback = request_user_feedback()
        if not feedback:
            log("pipeline", "🏁 Done.")
            return
        signal = run_pm(f"유저 피드백: {feedback}")
        if signal == "complete":
            log("pipeline", "🏁 Done.")
            return

    while True:
        cycle += 1
        log("pipeline", f"── Cycle {cycle} ──")

        log("pipeline", f"[{cycle}] Dev + Des")
        run_parallel_devdes()

        log("pipeline", f"[{cycle}] Reviewer")
        run("reviewer")

        log("pipeline", f"[{cycle}] PM")
        signal = run_pm()

        if signal == "complete":
            log("pipeline", "🏁 Done.")
            break

        if signal == "version":
            feedback = request_user_feedback()
            if not feedback:
                log("pipeline", "🏁 Done.")
                break
            signal = run_pm(f"유저 피드백: {feedback}")
            if signal == "complete":
                log("pipeline", "🏁 Done.")
                break

    log("pipeline", sep)
    log("pipeline", "All done.")
    log("pipeline", sep)


# ── Main ──────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--setup-only", action="store_true")
    args = parser.parse_args()

    create_session()
    make_all_fifos()

    if args.setup_only:
        print(f"Setup done.\n  tmux attach -t {SESSION}")
        return

    print(textwrap.dedent(f"""
    NativeScheduler FIFO Orchestrator
    Session : {SESSION}
    Attach  : tmux attach -t {SESSION}
    Windows : 0=orchestrator 1=pm 2=developer 3=designer 4=reviewer
    """))

    try:
        user_task = input("task (or Enter to skip)> ").strip() or None
        pipeline(user_task=user_task)
    except KeyboardInterrupt:
        print("\nQuit.")

if __name__ == "__main__":
    main()
