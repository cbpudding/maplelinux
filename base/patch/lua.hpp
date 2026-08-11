// lua.hpp for Maple Linux
// Why is there no official version in the git sources? ~ahill

// Lua's C includes have guards, so there's no reason to add an extra guard
// here, right? ~ahill
extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}
