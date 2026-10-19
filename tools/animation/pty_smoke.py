"""Optional POSIX runtime smoke test; normal Nim tests do not require Python.

Compile examples first, then run: python3 tools/animation/pty.py build/2.2.10-orc
"""
import fcntl
import os
import pty
import re
import select
import struct
import subprocess
import sys
import termios
import time


class Session:
    def __init__(self, name):
        self.name = name
        self.master, self.slave = pty.openpty()
        self.resize(90, 30)
        self.original = termios.tcgetattr(self.slave)
        self.raw = b""
        self.child = subprocess.Popen(
            [os.path.join(sys.argv[1], name)],
            stdin=self.slave, stdout=self.slave, stderr=self.slave,
        )

    def resize(self, width, height):
        fcntl.ioctl(self.slave, termios.TIOCSWINSZ, struct.pack("HHHH", height, width, 0, 0))

    def pump(self, duration=0.1):
        end = time.monotonic() + duration
        while time.monotonic() < end:
            if select.select([self.master], [], [], 0.02)[0]:
                chunk = os.read(self.master, 65536)
                self.raw += chunk
                if b"\x1b[6n" in chunk:
                    os.write(self.master, b"\x1b[1;1R")

    def screen(self):
        cells = [[" "] * 120 for _ in range(40)]
        x = y = 0
        data = self.raw.decode("utf-8", errors="ignore")
        index = 0
        while index < len(data):
            if data[index] == "\x1b":
                match = re.match(r"\x1b\[([0-9;?<>]*)([@-~])", data[index:])
                if not match:
                    index += 1
                    continue
                args, command = match.groups()
                if command == "H":
                    values = [int(v or "1") for v in args.split(";")]
                    y, x = values[0] - 1, (values[1] - 1 if len(values) > 1 else 0)
                elif command == "J" and args == "2":
                    cells = [[" "] * 120 for _ in range(40)]
                index += len(match.group())
            else:
                char = data[index]
                if char == "\r":
                    x = 0
                elif char == "\n":
                    y += 1
                else:
                    if 0 <= y < 40 and 0 <= x < 120:
                        cells[y][x] = char
                    x += 1
                index += 1
        # Assertions use ASCII UI labels; Unicode cell correctness is tested in Nim.
        return "\n".join("".join(row).rstrip() for row in cells)

    def expect(self, text, duration=3):
        end = time.monotonic() + duration
        while time.monotonic() < end:
            self.pump(0.05)
            if text in self.screen():
                return
        raise AssertionError(f"{self.name}: {text!r} missing:\n{self.screen()}")

    def send(self, keys):
        os.write(self.master, keys)
        self.pump()

    def idle(self):
        self.pump(0.3)
        before = len(self.raw)
        self.pump(0.3)
        assert len(self.raw) == before, f"{self.name}: unexpected idle output"

    def close(self):
        try:
            self.send(b"\x03")
            assert self.child.wait(timeout=2) == 0, self.raw[-1000:]
            self.pump()
            restored = termios.tcgetattr(self.slave)
            for value in (self.original, restored):
                value[3] &= ~getattr(termios, "PENDIN", 0)
            assert restored == self.original, "terminal modes not restored"
            for cleanup in (b"\x1b[?1006l", b"\x1b[?1003l", b"\x1b[?25h", b"\x1b[?1049l"):
                assert cleanup in self.raw, f"missing cleanup {cleanup!r}"
        finally:
            if self.child.poll() is None:
                self.child.kill()
                self.child.wait()
            os.close(self.master)
            os.close(self.slave)


gallery = Session("animations")
try:
    gallery.expect("Canopy animation gallery")
    gallery.send(b"\x1b[D")
    gallery.expect("Slide")
    gallery.send(b"d")
    gallery.expect("Direction: Right")
    gallery.send(b" ")
    gallery.idle()
    gallery.send(b" ")
    gallery.send(b"s")
    gallery.send(b"m")
    gallery.expect("Reduced motion: On")
    gallery.idle()
    gallery.send(b"\x1b[<0;5;3M")  # Fade effect tab.
    gallery.send(b"r")
    gallery.expect("Fade · Right")
    gallery.resize(12, 5)
    gallery.pump(0.2)
    assert gallery.child.poll() is None
    gallery.resize(90, 30)
    gallery.expect("Canopy animation gallery")
    gallery.send(b"m")
    gallery.send(b"r")
    gallery.expect("Reduced motion: Off")
finally:
    gallery.close()
print("PASS gallery: effects, direction, pause/resume, restart, spring, reduced motion, mouse, idle, resize, cleanup")

dashboard = Session("dashboard")
try:
    dashboard.expect("System overview")
    dashboard.idle()
    dashboard.send(b"2\r")
    dashboard.expect("Status: Running")
    dashboard.pump(0.25)  # A zero-progress stopped job is correctly labelled Ready.
    dashboard.send(b" ")
    dashboard.expect("Status: Paused")
    dashboard.send(b"r")
    dashboard.expect("Status: Ready")
    dashboard.send(b"3\x1b[B\x1b[B\x1b[B\r")
    dashboard.expect("Reduced motion: On")
    dashboard.send(b"2\r")
    dashboard.expect("Status: Running")
    dashboard.pump(0.5)
    dashboard.send(b" ")
    dashboard.expect("Status: Paused")
    assert "Progress: 0%" not in dashboard.screen(), "reduced motion stopped job simulation"
    dashboard.send(b"r")
    dashboard.expect("Status: Ready")
    dashboard.send(b"\x1b[<0;5;3M")  # Overview tab.
    dashboard.expect("System overview")
    dashboard.resize(12, 5)
    dashboard.pump(0.2)
    assert dashboard.child.poll() is None
    dashboard.resize(90, 30)
    dashboard.expect("System overview")
    dashboard.idle()
finally:
    dashboard.close()
print("PASS dashboard: idle start, tabs, progress, pause/reset, reduced motion, mouse, resize, cleanup")
