#!/usr/bin/env bash
# Smoke test for playdate:debian. EXPECT_SDK=0 (CI) skips the SDK checks, since CI builds
# without the SDK (Panic's license forbids redistributing it).
. /tests/lib.sh
. /images/dev/debian/test.sh --no-finish

need arm-none-eabi-gcc cmake
run "newlib links a bare-metal binary" sh -c 'd=$(mktemp -d) && echo "int main(void){return 0;}" > "$d/a.c" && arm-none-eabi-gcc --specs=nosys.specs -o "$d/a.elf" "$d/a.c"'

if [ "${EXPECT_SDK:-1}" = 1 ]; then
  need pdc PlaydateSimulator
  run "PLAYDATE_SDK_PATH has C_API" test -d "${PLAYDATE_SDK_PATH:-/nonexistent}/C_API"
  run "simulator libraries resolve" sh -c '! ldd "$(command -v PlaydateSimulator)" | grep -q "not found"'
  run "pdc compiles a Lua game" sh -c 'd=$(mktemp -d) && mkdir "$d/src" && printf "import \"CoreLibs/graphics\"\nfunction playdate.update() end\n" > "$d/src/main.lua" && pdc "$d/src" "$d/out.pdx" && test -f "$d/out.pdx/main.pdz"'
fi

_maybe_finish "$@"
