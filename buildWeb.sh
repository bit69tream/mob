#!/bin/bash -eu

OUT_DIR="build/web"
mkdir -p ${OUT_DIR}

export EMSDK_QUIET=1

# Note RAYLIB_WASM_LIB=env.o -- env.o is an internal WASM object file. You can
# see how RAYLIB_WASM_LIB is used inside <odin>/vendor/raylib/raylib.odin.
#
# The emcc call will be fed the actual raylib library file. That stuff will end
# up in env.o
odin build src/web -target:js_wasm32 -build-mode:obj -define:RAYLIB_WASM_LIB=env.o -out:${OUT_DIR}/game.wasm.o

ODIN_ROOT=$(odin root)

cp ${ODIN_ROOT}/core/sys/wasm/js/odin.js $OUT_DIR

FILES="$OUT_DIR/game.wasm.o ${ODIN_ROOT}/vendor/raylib/wasm/libraylib.a"

FLAGS="-sUSE_GLFW=3 -sWASM_BIGINT -sWARN_ON_UNDEFINED_SYMBOLS=0 -sASSERTIONS --shell-file src/web/index.html"

emcc -o $OUT_DIR/index.html ${FILES} ${FLAGS}

rm $OUT_DIR/game.wasm.o

echo "Web build created in ${OUT_DIR}"
