/* Copyright (c) 2026 Alexander Hill
 *
 * Permission to use, copy, modify, and/or distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
 * REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
 * AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
 * INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
 * LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
 * OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
 * PERFORMANCE OF THIS SOFTWARE.
 */

#include <stdio.h> // stderr, fprintf
#include <unistd.h> // getopt, optarg, optind, opterr, optopt

#ifndef MAPLECONF_CONFIG_PATH
#define MAPLECONF_CONFIG_PATH "/etc/maple.toml"
#endif

#ifndef MAPLECONF_TEMPLATE_PATH
#define MAPLECONF_TEMPLATE_PATH "/share/mapleconf"
#endif

int main(int argc, char *argv[]) {
    char *config_path = MAPLECONF_CONFIG_PATH;
    int opt;
    char *root_path = "/";
    char *template_path = MAPLECONF_TEMPLATE_PATH;

    while((opt = getopt(argc, argv, "c:hr:t:")) != -1) {
        switch(opt) {
        case 'c':
            config_path = optarg;
            break;
        case 'h':
            fprintf(stderr, "Usage: %s [option [option ...] ]\n", argv[0]);
            fprintf(stderr, "    -c <file> - Sets the file to source configuration data from\n");
            fprintf(stderr, "    -h        - Displays this help message\n");
            fprintf(stderr, "    -r <path> - Sets the sysroot to configure\n");
            fprintf(stderr, "    -t <path> - Sets the path of the template directory\n");
            return 1;
        case 'r':
            root_path = optarg;
            break;
        case 't':
            template_path = optarg;
            break;
        default:
            fprintf(stderr, "Unknown option: %s\n", argv[optind - 1]);
            return 1;
        }
    }

    fprintf(stderr, "DEBUG: config_path = %s\n", config_path);
    fprintf(stderr, "DEBUG: root_path = %s\n", root_path);
    fprintf(stderr, "DEBUG: template_path = %s\n", template_path);

    // ...

    return 0;
}
