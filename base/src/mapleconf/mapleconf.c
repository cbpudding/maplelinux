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

#include <dirent.h> // DIR, closedir, struct dirent, opendir, readdir
#include <errno.h> // errno
#include <lauxlib.h> // luaL_*
#include <lua.h> // LUA_*, lua_*
#include <lualib.h> // luaopen_*
#include <stdio.h> // FILE, SEEK_END, SEEK_SET, fclose, fopen, fprintf, fread,
                   // fseek, ftell, fwrite, puts, sprintf, stderr
#include <stdlib.h> // free, malloc
#include <string.h> // strcmp, strerror, strlen
#include <sys/stat.h> // S_ISDIR, S_ISREG, mkdir, stat, struct stat
#include <tomlc17.h> // TOML_*, toml_*
#include <unistd.h> // F_OK, access, getopt, optarg, optind, opterr, optopt

#ifndef MAPLECONF_CONFIG_PATH
#   define MAPLECONF_CONFIG_PATH "/etc/maple.toml"
#endif

const char MAPLECONF_LIQUID_LUA_SRC[] = {
#   embed "liquid.lua"
};

const char MAPLECONF_LUADATE_SRC[] = {
#   embed "date.lua"
};

#ifndef MAPLECONF_TEMPLATE_PATH
#   define MAPLECONF_TEMPLATE_PATH "/share/mapleconf"
#endif

const char MAPLECONF_DEFAULTS[] = {
#   embed "mapleconf.toml" if_empty('#')
, 0
};

void render_file(lua_State *state, char *template_path, char *path) {
    size_t length;
    const char *result;
    FILE *target;
    char *template;

    target = fopen(template_path, "r");
    if(!target) {
        fprintf(stderr, "%s: fopen: %s\n", template_path, strerror(errno));
        return;
    }

    fseek(target, 0, SEEK_END);
    length = ftell(target);
    fseek(target, 0, SEEK_SET);

    template = malloc(length);
    if(!template) {
        fprintf(
            stderr,
            "%s: Unable to allocate buffer for template\n",
            template_path
        );
        fclose(target);
        return;
    }

    if(fread(template, 1, length, target) != length) {
        fprintf(stderr, "%s: fread: Incomplete read\n", template_path);
        free(template);
        fclose(target);
        return;
    }

    fclose(target);

    // liquid.Template:parse(template):render(context)
    lua_getglobal(state, "liquid");
    lua_getfield(state, -1, "Template");
    lua_getfield(state, -1, "parse");
    lua_pushvalue(state, -2);
    lua_pushlstring(state, template, length);
    if(lua_pcall(state, 2, 1, 0) != LUA_OK) {
        fprintf(stderr, "%s: parse: %s\n", path, lua_tostring(state, -1));
        free(template);
        lua_pop(state, 3);
        return;
    }

    free(template);

    lua_getfield(state, -1, "render");
    lua_pushvalue(state, -2);
    lua_getglobal(state, "context");
    if(lua_pcall(state, 2, 1, 0) != LUA_OK) {
        fprintf(stderr, "%s: render: %s\n", path, lua_tostring(state, -1));
        lua_pop(state, 4);
        return;
    }

    target = fopen(path, "wb");
    if(target) {
        result = lua_tolstring(state, -1, &length);
        if(fwrite(result, 1, length, target) != length) {
            fprintf(stderr, "%s: fwrite: Incomplete write\n", path);
        }
        fclose(target);
    } else {
        fprintf(stderr, "%s: fopen: %s\n", path, strerror(errno));
    }

    lua_pop(state, 4);
}

void render_directory(lua_State *state, char *template_path, char *root_path) {
    DIR *directory;
    struct dirent *entry;
    char *fullpath_root;
    char *fullpath_template;
    struct stat status;

    directory = opendir(template_path);
    if(!directory) {
        fprintf(stderr, "%s: %s\n", template_path, strerror(errno));
        return;
    }

    while((entry = readdir(directory))) {
        if(!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) {
            continue;
        }

        fullpath_root = malloc(strlen(root_path) + strlen(entry->d_name) + 2);
        fullpath_template = malloc(
            strlen(template_path) + strlen(entry->d_name) + 2
        );

        sprintf(fullpath_root, "%s/%s", root_path, entry->d_name);
        sprintf(fullpath_template, "%s/%s", template_path, entry->d_name);

        if(stat(fullpath_template, &status)) {
            fprintf(stderr, "%s: %s\n", fullpath_template, strerror(errno));
            free(fullpath_root);
            free(fullpath_template);
            continue;
        }

        if(S_ISDIR(status.st_mode)) {
            if(access(fullpath_root, F_OK)) {
                mkdir(fullpath_root, 0755);
            }

            render_directory(state, fullpath_template, fullpath_root);
        } else if(S_ISREG(status.st_mode)) {
            render_file(state, fullpath_template, fullpath_root);
        }

        free(fullpath_root);
        free(fullpath_template);
    }

    closedir(directory);
}

int push_configuration_table(toml_datum_t *datum, lua_State *state) {
    int status = 0;

    switch(datum->type) {
        case TOML_ARRAY:
            lua_createtable(state, datum->u.arr.size, 0);
            for(int n = 0; n < datum->u.arr.size; n++) {
                status |= push_configuration_table(
                    &datum->u.arr.elem[n],
                    state
                );
                lua_rawseti(state, -2, n + 1);
            }
            break;

        case TOML_BOOLEAN:
            lua_pushboolean(state, datum->u.boolean);
            break;

        case TOML_DATE:
            lua_getglobal(state, "date");
            lua_pushinteger(state, datum->u.ts.year);
            lua_pushinteger(state, datum->u.ts.month);
            lua_pushinteger(state, datum->u.ts.day);
            if(lua_pcall(state, 3, 1, 0) != LUA_OK) {
                fprintf(
                    stderr,
                    "%s:%u:%u: %s\n",
                    datum->source,
                    datum->lineno,
                    datum->colno,
                    lua_tostring(state, -1)
                );
                status = 1;
                lua_pop(state, 1);
                lua_pushnil(state);
            }
            break;

        case TOML_DATETIME:
            lua_getglobal(state, "date");
            lua_pushinteger(state, datum->u.ts.year);
            lua_pushinteger(state, datum->u.ts.month);
            lua_pushinteger(state, datum->u.ts.day);
            lua_pushinteger(state, datum->u.ts.hour);
            lua_pushinteger(state, datum->u.ts.minute);
            lua_pushinteger(state, datum->u.ts.second);
            // TODO: Can usec be converted to ticks? ~ahill
            if(lua_pcall(state, 6, 1, 0) != LUA_OK) {
                fprintf(
                    stderr,
                    "%s:%u:%u: %s\n",
                    datum->source,
                    datum->lineno,
                    datum->colno,
                    lua_tostring(state, -1)
                );
                status = 1;
                lua_pop(state, 1);
                lua_pushnil(state);
            }
            break;

        // TODO: TOML_DATETIMETZ

        case TOML_FP64:
            lua_pushnumber(state, datum->u.fp64);
            break;

        case TOML_INT64:
            lua_pushinteger(state, datum->u.int64);
            break;

        case TOML_STRING:
            lua_pushlstring(state, datum->u.str.ptr, datum->u.str.len);
            break;

        case TOML_TABLE:
            lua_createtable(state, 0, datum->u.tab.size);
            for(int n = 0; n < datum->u.tab.size; n++) {
                lua_pushstring(state, datum->u.tab.key[n]);
                status |= push_configuration_table(
                    &datum->u.tab.value[n],
                    state
                );
                lua_settable(state, -3);
            }
            break;

        case TOML_TIME:
            lua_getglobal(state, "date");
            lua_createtable(state, 0, 3);
            lua_pushinteger(state, datum->u.ts.hour);
            lua_setfield(state, -2, "hour");
            lua_pushinteger(state, datum->u.ts.minute);
            lua_setfield(state, -2, "min");
            lua_pushinteger(state, datum->u.ts.second);
            lua_setfield(state, -2, "sec");
            if(lua_pcall(state, 1, 1, 0) != LUA_OK) {
                fprintf(
                    stderr,
                    "%s:%u:%u: %s\n",
                    datum->source,
                    datum->lineno,
                    datum->colno,
                    lua_tostring(state, -1)
                );
                status = 1;
                lua_pop(state, 1);
                lua_pushnil(state);
            }
            break;

        case TOML_UNKNOWN:
            lua_pushnil(state);
            break;

        default:
            fprintf(
                stderr,
                "Unknown TOML type encountered: %u. Please report this bug!\n",
                datum->type
            );
            status = 1;
            lua_pushnil(state);
            break;
    }

    return status;
}

int require_lua_module(lua_State *state, const char *module) {
    if(lua_getglobal(state, "require") != LUA_TFUNCTION) {
        fprintf(stderr, "Lua global \"require\" is somehow not a function?\n");
        lua_pop(state, 1);
        return 1;
    }

    lua_pushstring(state, module);

    if(lua_pcall(state, 1, 1, 0) != LUA_OK) {
        fprintf(
            stderr,
            "Failed to require \"%s\": %s\n",
            module,
            lua_tostring(state, -1)
        );
        lua_pop(state, 1);
        return 1;
    }

    lua_setglobal(state, module);

    return 0;
}

lua_State *init_template_engine(toml_result_t *config) {
    lua_State *state;

    // Yes, I am using liquid.lua inside of C. Trying to find a complete Liquid
    // implementation in C is much harder than it sounds. ~ahill

    state = luaL_newstate();
    if(!state) {
        fprintf(stderr, "Failed to initialize Lua. Is there enough memory?\n");
        return NULL;
    }

    luaL_openlibs(state);

    // _G.date = require("date")
    // _G.liquid = require("liquid")
    lua_getglobal(state, "package");
    lua_getfield(state, -1, "preload");
    if(luaL_loadbufferx(
        state,
        MAPLECONF_LUADATE_SRC,
        sizeof(MAPLECONF_LUADATE_SRC),
        "@date.lua",
        "t"
    ) != LUA_OK) {
        fprintf(
            stderr,
            "Error while preloading LuaDate: %s\n",
            lua_tostring(state, -1)
        );
        lua_close(state);
        return NULL;
    }
    lua_setfield(state, -2, "date");
    if(luaL_loadbufferx(
        state,
        MAPLECONF_LIQUID_LUA_SRC,
        sizeof(MAPLECONF_LIQUID_LUA_SRC),
        "@liquid.lua",
        "t"
    ) != LUA_OK) {
        fprintf(
            stderr,
            "Error while preloading liquid-lua: %s\n",
            lua_tostring(state, -1)
        );
        lua_close(state);
        return NULL;
    }
    lua_setfield(state, -2, "liquid");
    lua_pop(state, 2);

    if(require_lua_module(state, "date")) {
        lua_close(state);
        return NULL;
    }

    if(require_lua_module(state, "liquid")) {
        lua_close(state);
        return NULL;
    }

    // _G.context = liquid.InterpreterContext:new(config)
    lua_getglobal(state, "liquid");
    lua_getfield(state, -1, "InterpreterContext");
    lua_getfield(state, -1, "new");
    lua_pushvalue(state, -2);

    if(push_configuration_table(&config->toptab, state)) {
        fprintf(stderr, "Malformed TOML configuration. Aborting.\n");
        lua_close(state);
        return NULL;
    }

    if(lua_pcall(state, 2, 1, 0) != LUA_OK) {
        fprintf(
            stderr,
            "Failed to initialize context: %s\n",
            lua_tostring(state, -1)
        );
        lua_close(state);
        return NULL;
    }

    lua_setglobal(state, "context");
    lua_pop(state, 2);

    return state;
}

int build_configuration(
    const char *config_path,
    const char *root_path,
    const char *template_path
) {
    toml_result_t config;
    toml_result_t config_toml;
    toml_result_t default_toml;
    lua_State *state;

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

    if(!config.ok) {
        fprintf(
            stderr,
            "Failed to merge %s with defaults: %s\n",
            config_path,
            config.errmsg
        );
        toml_free(config);
        return 1;
    }

    state = init_template_engine(&config);
    toml_free(config);

    if(!state) {
        fprintf(stderr, "Failed to initialize Lua. Aborting.\n");
        return 1;
    }

    render_directory(state, (char *)template_path, (char *)root_path);

    return 0;
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
