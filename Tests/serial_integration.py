"""Exercise the compiled app's serial transport with an actual POSIX pseudo-terminal."""
import os
import select
import subprocess
import sys
import termios
import time

binary = sys.argv[1]


def run(disconnect=False):
    master, slave = os.openpty()
    original = termios.tcgetattr(slave)
    proc = subprocess.Popen([binary, "--capture", os.ttyname(slave), "1.5"], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    try:
        assert select.select([master], [], [], 3)[0], "Reader did not send identification request"
        assert os.read(master, 1) == b"I"
        configured = termios.tcgetattr(slave)
        assert configured[4] == termios.B9600 and configured[5] == termios.B9600
        assert not configured[3] & (termios.ECHO | termios.ICANON)
        if disconnect:
            os.close(master)
            master = None
        else:
            os.write(master, b"Z-2 USB v3.0\r\nEM-Marine[001122")
            time.sleep(0.05)
            os.write(master, b"3344] 007,00123\r\nEM-Marine[0011223344] 007,00123\r\n")
            os.write(master, b"No card\r\nEM-Marine[0011223344] 007,00123\r\n")
        output, error = proc.communicate(timeout=5)
        if disconnect:
            assert proc.returncode == 1, (proc.returncode, output, error)
            assert "Reader disconnected" in output
        else:
            assert proc.returncode == 0, (output, error)
            assert sum(line.startswith("card(") for line in output.splitlines()) == 2, output
            assert "removed" in output.splitlines(), output
            assert 'reportedHex: "0011223344", facility: 7, number: 123' in output, output
            restored = termios.tcgetattr(slave)
            # Darwin marks input for reprocessing (PENDIN) when restoring canonical mode.
            # This is transient kernel state; all actual port settings must match.
            restored[3] &= ~termios.PENDIN
            original[3] &= ~termios.PENDIN
            assert restored == original, "Original serial settings were not restored"
        print("PASS: serial disconnect detection" if disconnect else "PASS: serial 9600/raw configuration, split reads, deduplication, removal/re-presentation, settings restoration")
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        if master is not None:
            os.close(master)
        os.close(slave)


run()
run(disconnect=True)
