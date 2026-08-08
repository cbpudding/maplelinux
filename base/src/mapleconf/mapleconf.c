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

#include <stdio.h> // fprintf, puts, stderr
#include <tomlc17.h> // toml_*
#include <unistd.h> // getopt, optarg, optind, opterr, optopt

#ifndef MAPLECONF_CONFIG_PATH
#   define MAPLECONF_CONFIG_PATH "/etc/maple.toml"
#endif

#ifndef MAPLECONF_TEMPLATE_PATH
#   define MAPLECONF_TEMPLATE_PATH "/share/mapleconf"
#endif

const char MAPLECONF_DEFAULTS[] = {
#embed "mapleconf.toml" if_empty(0)
, 0
};

int render_directory() {
    // ...
    return 0;
}

int build_configuration(
    const char *config_path,
    const char *root_path,
    const char *template_path
) {
    toml_result_t config;
    toml_result_t config_toml;
    toml_result_t default_toml;

    default_toml = toml_parse(
        MAPLECONF_DEFAULTS,
        sizeof(MAPLECONF_DEFAULTS) - 1
    );

    if(!default_toml.ok) {
        fprintf(
            stderr,
            "Failed to parse mapleconf.toml. Please recompile!\n%s\n",
            default_toml.errmsg
        );
        toml_free(default_toml);
        return 1;
    }

    config_toml = toml_parse_file_ex(config_path);

    if(!config_toml.ok) {
        fprintf(stderr, "Failed to load %s: %s\n", config_path, config_toml.errmsg);
        toml_free(config_toml);
        toml_free(default_toml);
        return 1;
    }

    config = toml_merge(&default_toml, &config_toml);

    toml_free(config_toml);
    toml_free(default_toml);

    if(config.ok) {
        // ...
    } else {
        fprintf(
            stderr,
            "Failed to merge %s with defaults: %s\n",
            config_path,
            config.errmsg
        );
    }

    toml_free(config);

    return 1;
}

int main(int argc, char *argv[]) {
    const char *config_path = MAPLECONF_CONFIG_PATH;
    const char *root_path = "/";
    const char *template_path = MAPLECONF_TEMPLATE_PATH;

    int opt;

    while((opt = getopt(argc, argv, "c:dr:t:")) != -1) {
        switch(opt) {
        case 'c':
            config_path = optarg;
            break;
        case 'd':
            puts(MAPLECONF_DEFAULTS);
            return 0;
        case 'r':
            root_path = optarg;
            break;
        case 't':
            template_path = optarg;
            break;
        default:
            fprintf(stderr, "Unknown option: %s\n", argv[optind - 1]);
            fprintf(stderr, "Usage: %s [option [option ...] ]\n", argv[0]);
            fprintf(stderr, "    -c <file> - Sets the file to source configuration data from\n");
            fprintf(stderr, "    -d        - Prints the default configuration and exits\n");
            fprintf(stderr, "    -r <path> - Sets the sysroot to configure\n");
            fprintf(stderr, "    -t <path> - Sets the path of the template directory\n");
            return 1;
        }
    }

    return build_configuration(config_path, root_path, template_path);
}
