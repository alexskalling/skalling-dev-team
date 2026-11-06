"""Bounded command execution shared by workflow checks and coverage."""
import os
import selectors
import signal
import subprocess
import sys
import time

_ACTIVE = None

def run_bounded(argv, root, env, timeout):
    """Corre el comando en su propio grupo de procesos: al vencer el plazo (o
    si el plugin cancela y llega SIGTERM) se termina el grupo entero, sin
    dejar pruebas huérfanas corriendo."""
    global _ACTIVE
    # pnpm can install/upgrade dependencies before `run` or `exec`. A check
    # must use the prepared environment, never repair it implicitly.
    env = {**env, 'PNPM_CONFIG_VERIFY_DEPS_BEFORE_RUN': 'false',
           'npm_config_verify_deps_before_run': 'false'}
    proc = subprocess.Popen(argv, cwd=root, env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            start_new_session=True)
    _ACTIVE = proc
    deadline = time.monotonic() + timeout
    output = bytearray()
    try:
        # Drain continuously but retain only the evidence tail. communicate()
        # buffered the entire log before slicing, allowing noisy tests to OOM.
        with selectors.DefaultSelector() as selector:
            selector.register(proc.stdout, selectors.EVENT_READ)
            while selector.get_map():
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise subprocess.TimeoutExpired(argv, timeout, output=bytes(output))
                for key, _ in selector.select(remaining):
                    chunk = os.read(key.fd, 32768)
                    if not chunk:
                        selector.unregister(key.fileobj)
                    else:
                        output.extend(chunk)
                        del output[:-16000]
        proc.wait(timeout=max(0, deadline - time.monotonic()))
        return proc.returncode, output.decode('utf-8', 'replace')
    except BaseException:
        _kill_group(proc)
        proc.wait()
        raise
    finally:
        proc.stdout.close()
        _ACTIVE = None


def _kill_group(proc):
    if hasattr(os, 'killpg'):
        try:
            os.killpg(proc.pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass
    elif proc.poll() is None:
        proc.kill()


def _cancel(signum, _frame):
    if _ACTIVE is not None:
        _kill_group(_ACTIVE)
    sys.exit(128 + signum)
