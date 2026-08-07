# Maple Linux

## Philosophy

Maple Linux was designed to be much more than "yet another Linux distribution", and aims to achieve the following goals:

- Provide a fully functional operating system with as few moving parts as possible, enabling a single person to have a comprehensive view of the system
- Provide full transparency about the operating system's inner workings, improving security and preserving the sanity of system administrators
- Provide a unified user experience, where the various components behave as one coherent operating system
- Provide an operating system that is free, as in speech, not beer

While it may sound too good to be true, that's because it is. Maple Linux does not aim to be a "fix everything" solution, and compromises on the following:

- Reducing the number of moving parts in an operating system will naturally make certain software (particularly, proprietary software) incompatible with Maple Linux. An effort will be made to maintain a balance between functionality and minimalism while keeping maintenance costs low.
- While providing transparency is a noble long-term goal, some complexity is necessary to achieve an acceptable level of functionality. Maple Linux strives to provide transparency wherever possible, but much of the project's overall transparency is at the mercy of upstream developers.
- In order to achieve the "unified experience", the software included has been selected in advance so that effort can be focused on improving the system as a whole. This makes it far less generic and customizable, but offers a much more coherent and focused system overall. In addition, this makes it much more maintainable for a single developer such as myself.
- Much of the software in the Linux ecosystem, including Linux itself, is released under a copyleft license. While the Maple Linux project attempts to provide an operating system that gives you as much freedom as possible, some software licenses impose conditions on redistribution and modification that Maple Linux must respect.

## Status

| Architecture | Base      |
| ------------ | --------- |
| ARM          | Planned   |
| RISC-V       | Planned   |
| SPARC        | Planned   |
| x86_64       | Supported |

## Design

### Filesystem Hierarchy

Maple Linux uses a different filesystem hierarchy compared to most Linux systems. It is designed to be recognizable to experienced users, while being easy for new users to understand.

- `/bin` - User-Executable Code
- `/boot` - Boot Partition
- `/cache` - Retained Data
- `/dev` - Linux Device Nodes
- `/etc` - System Configuration and Persistent State
- `/home` - User Data
- `/lib` - Machine-Executable Code
- `/proc` - Linux Process Objects
- `/share` - Immutable Shared Data
- `/sys` - Linux Kernel Objects
- `/tmp` - Temporary Data

## Inspirations

- [https://crux.nu/](https://crux.nu/)
- [https://kisslinux.github.io/](https://kisslinux.github.io/)
- [https://git.sr.ht/~mcf/oasis](https://git.sr.ht/~mcf/oasis)
- [https://sta.li/filesystem/](https://sta.li/filesystem/)
- [https://suckless.org/philosophy/](https://suckless.org/philosophy/)
- [https://github.com/comfies/tldrlfs](https://github.com/comfies/tldrlfs)

## Research

- [https://lists.busybox.net/pipermail/busybox/2010-December/074114.html](https://lists.busybox.net/pipermail/busybox/2010-December/074114.html)
- [https://wiki.c2.com/?TheKenThompsonHack](https://wiki.c2.com/?TheKenThompsonHack)
- [https://felipec.wordpress.com/2024/04/04/xz-backdoor-and-autotools-insanity/](https://felipec.wordpress.com/2024/04/04/xz-backdoor-and-autotools-insanity/)
