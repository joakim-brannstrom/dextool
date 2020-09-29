/**
Copyright: Copyright (c) 2020, Joakim Brännström. All rights reserved.
License: $(LINK2 http://www.boost.org/LICENSE_1_0.txt, Boost Software License 1.0)
Author: Joakim Brännström (joakim.brannstrom@gmx.com)

Module to manipulate a file descriptor that point to a tty.
*/
module my.tty;

import my.from_;

/// Used to reset the terminal to the original mode.
struct CBreak {
    import core.sys.posix.termios;

    termios mode;

    void reset(int fd) {
        tcsetattr(fd, TCSAFLUSH, &mode);
    }
}

/// Set the terminal to cbreak mode which mean it is change from line mode to
/// character mode.
CBreak setCBreak(int fd) {
    import core.sys.posix.termios;

    termios mode;
    if (tcgetattr(fd, &mode) == 0) {
        auto newMode = mode;
        newMode.c_lflag = newMode.c_lflag & ~(ECHO | ICANON);
        newMode.c_cc[VMIN] = 1;
        newMode.c_cc[VTIME] = 0;
        tcsetattr(fd, TCSAFLUSH, &newMode);
    }

    return CBreak(mode);
}

/// Configure a tty for interactive input.
void setInteractiveTty(ref std_.stdio.File tty) {
    import core.sys.posix.termios;
    import std.conv : octal;

    // /usr/include/x86_64-linux-gnu/bits/termios-c_iflag.h
    enum IUTF8 = octal!40000; /* Input is UTF8 (not in POSIX).  */

    enum ECHOCTL = octal!1000; /* If ECHO is also set, terminal special
                                  characters other than TAB, NL, START, and
                                  STOP are echoed as ^X, where X is the
                                  character with ASCII code 0x40 greater than
                                  the special character (not in POSIX).  */

    enum ECHOKE = octal!4000; /* If ICANON is also set, KILL is echoed by
                                 erasing each character on the line, as
                                 specified by ECHOE and ECHOPRT (not in POSIX).
                               */
    enum VREPRINT = 12;
    enum VWERASE = 14;
    enum VLNEXT = 15;

    termios mode;
    mode.c_iflag = ICRNL | IXON | IUTF8;
    mode.c_oflag = OPOST | ONLCR | NL0 | CR0 | TAB0 | BS0 | VT0 | FF0;
    mode.c_cflag = CS8 | CREAD;
    mode.c_lflag = ISIG | ICANON | IEXTEN; // | ECHO | ECHOE | ECHOK | ECHOCTL | ECHOKE;

    cfsetispeed(&mode, 38400);
    cfsetospeed(&mode, 38400);

    mode.c_cc[VINTR] = 0x1f & 'C';
    mode.c_cc[VQUIT] = 0x1f & '\\';
    mode.c_cc[VERASE] = 0x7f;
    mode.c_cc[VKILL] = 0x1f & 'U';
    mode.c_cc[VEOF] = 0x1f & 'D';
    //mode.c_cc[VEOL]     = _POSIX_VDISABLE;
    //mode.c_cc[VEOL2]    = _POSIX_VDISABLE;
    mode.c_cc[VSTART] = 0x1f & 'Q';
    mode.c_cc[VSTOP] = 0x1f & 'S';
    mode.c_cc[VSUSP] = 0x1f & 'Z';
    mode.c_cc[VREPRINT] = 0x1f & 'R';
    mode.c_cc[VWERASE] = 0x1f & 'W';
    mode.c_cc[VLNEXT] = 0x1f & 'V';
    mode.c_cc[VMIN] = 1;
    mode.c_cc[VTIME] = 0;

    tcsetattr(tty.fileno, TCSAFLUSH, &mode);
}
