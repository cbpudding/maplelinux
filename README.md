# Maple Linux

## Philosophy

Maple Linux was designed to be much more than "yet another Linux distribution", and aims to achieve the following goals:

- Provide a fully functional operating system with as few moving parts as possible
- Provide a unified user experience, where the various software all behave as one coherent operating system

While it may sound too good to be true, that's because it is. Maple Linux does not aim to be a "fix everything" solution, and compromises on the following:

- Reducing the number of moving parts in an operating system will naturally make certain software (particularly, proprietary software) incompatible with Maple Linux. An effort will be made to maintain the balance between functionality and minimalism to make the user experience as enjoyable as possible while keeping maintenance costs low.
- In order to achieve the "unified" experience, the software you are given has been pre-determined so I can focus on optimizing Maple Linux as a whole. This makes it far less generic and customizable, but offers a much more coherent and focused system overall. In addition, this makes it much more maintainable for a singular developer such as myself.

## Design

### Filesystem Hierarchy

Maple Linux uses a different filesystem hierarchy compared to most Linux systems. It is designed to be recognizable to experienced users, while being easier for new users to understand.

- `/bin` - User-Executable Code
- `/boot` - Boot Partition
- `/cache` - Retained Data
- `/dev` - Linux Device Nodes
- `/etc` - Persistent Data
- `/home` - User Data
- `/lib` - Machine-Executable Code
- `/proc` - Linux Process Objects
- `/share` - Immutable Data
- `/sys` - Linux Kernel Objects
- `/tmp` - Temporary Data

## Inspirations

- [https://lists.busybox.net/pipermail/busybox/2010-December/074114.html](https://lists.busybox.net/pipermail/busybox/2010-December/074114.html)
- [https://crux.nu/](https://crux.nu/)
- [https://kisslinux.github.io/](https://kisslinux.github.io/)
- [https://git.sr.ht/~mcf/oasis](https://git.sr.ht/~mcf/oasis)
- [https://sta.li/filesystem/](https://sta.li/filesystem/)
- [https://suckless.org/philosophy/](https://suckless.org/philosophy/)
- [https://github.com/comfies/tldrlfs](https://github.com/comfies/tldrlfs)
