"""Run Godot on this project while holding the shared lock (several agents share it).

    python godot/tools/godot_run.py --import                      # import new/changed assets only
    python godot/tools/godot_run.py --import -- --headless --quit-after 600
    python godot/tools/godot_run.py -- --headless --script res://tests/smoke.gd
    python godot/tools/godot_run.py --timeout 300 -- --resolution 1600x900 --script res://tools/game_shot.gd -- --out C:/x.png

Everything after the first "--" goes to Godot (which gets --path godot automatically).
Use --import whenever models or other assets changed since the last run.
Runtime/script/shader errors fail the run even if Godot returns zero.
Output is printed, minus engine banner noise.
"""
import os
import queue
import subprocess
import sys
import threading
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from godot_preview import GodotLock, godot_import, GODOT, GODOT_DIR  # noqa: E402


NOISE = ("Godot Engine v", "Vulkan ", "OpenGL API")
ENGINE_ERRORS = ("SCRIPT ERROR:", "SHADER ERROR:", "ERROR:")


def _stop_child(process):
    """Reap only the Popen child we own; never kill by executable or process tree."""
    if process.poll() is None:
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=2)


def run_child(command, *, cwd, timeout, startupinfo=None, output_stream=None):
    """Stream diagnostics and fail promptly, retaining output already in the pipe."""
    output_stream = output_stream if output_stream is not None else sys.stdout
    messages = queue.Queue()
    end = object()
    process = subprocess.Popen(
        command, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, encoding="utf-8", errors="replace", bufsize=1,
        startupinfo=startupinfo,
    )

    def read_output():
        try:
            for line in process.stdout:
                messages.put(line)
        finally:
            process.stdout.close()
            messages.put(end)

    reader = threading.Thread(target=read_output, name="godot-output", daemon=True)
    reader.start()
    deadline = time.monotonic() + timeout
    engine_error = False
    timed_out = False

    def emit(line):
        nonlocal engine_error
        line = line.rstrip("\r\n")
        engine_error = engine_error or line.lstrip().startswith(ENGINE_ERRORS)
        if line.strip() and not line.startswith(NOISE):
            print(line, file=output_stream, flush=True)

    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                timed_out = True
                break
            try:
                line = messages.get(timeout=min(.1, remaining))
            except queue.Empty:
                continue
            if line is end:
                # A child may close its output before exiting. Still enforce the
                # same deadline rather than waiting forever while holding the lock.
                try:
                    process.wait(timeout=max(.001, deadline-time.monotonic()))
                except subprocess.TimeoutExpired:
                    timed_out = True
                break
            emit(line)
            if engine_error:
                break
    finally:
        _stop_child(process)
        # The reader drains stderr/stdout concurrently with terminate/wait, so
        # backtraces already written behind the first error are not discarded.
        reader.join(timeout=2)
        while True:
            try:
                line = messages.get_nowait()
            except queue.Empty:
                break
            if line is not end:
                emit(line)
    if timed_out:
        print(f"[godot_run] FAILED: child exceeded {timeout}s timeout", file=output_stream, flush=True)
        return 124
    if engine_error:
        print("[godot_run] FAILED: engine error logged; child stopped and output drained", file=output_stream, flush=True)
        return process.returncode if process.returncode and process.returncode > 0 else 1
    return process.returncode


def main():
    a = sys.argv[1:]
    godot_args = []
    if "--" in a:
        i = a.index("--")
        a, godot_args = a[:i], a[i + 1:]
    timeout = 600
    if "--timeout" in a:
        timeout = int(a[a.index("--timeout") + 1])
    with GodotLock():
        if "--import" in a:
            godot_import()
        if not godot_args:
            return 0
        startup = None
        if os.name == "nt" and "--offscreen-validation" in godot_args:
            # Do not activate a desktop window before the validation scene can
            # set its own no-focus flag. The renderer remains available offscreen.
            startup = subprocess.STARTUPINFO()
            startup.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            startup.wShowWindow = subprocess.SW_HIDE
            godot_args = ["--windowed", "--position", "-10000,-10000", "--audio-driver", "Dummy"] + godot_args
        return run_child([GODOT, "--path", GODOT_DIR] + godot_args,
                         cwd=GODOT_DIR, timeout=timeout, startupinfo=startup)



if __name__ == "__main__":
    sys.exit(main() or 0)
