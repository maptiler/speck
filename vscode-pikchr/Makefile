# Builds the Pikchr extension for VS Code.
# Run `npm install` once before the first build.

# Pikchr is compiled to WebAssembly from the same source as the Lua module,
# so the preview renders diagrams exactly as SPECK does. The WebAssembly binary
# is embedded in the generated JavaScript file (SINGLE_FILE), which is then
# bundled into the extension.
EMFLAGS = -O2 -DNDEBUG -std=c17 -Wall -Wextra -Werror --no-entry \
	-sMODULARIZE -sEXPORT_NAME=createPikchr \
	-sENVIRONMENT=node -sSINGLE_FILE -sALLOW_MEMORY_GROWTH \
	-sEXPORTED_FUNCTIONS=_pikchr,_malloc,_free \
	-sEXPORTED_RUNTIME_METHODS=stringToNewUTF8,UTF8ToString,getValue

ESBUILD_FLAGS = --bundle --platform=node --format=cjs --target=node20 \
	--external:vscode --sourcemap

BIN = node_modules/.bin

all: dist/extension.js

build/pikchr-wasm.js: ../src/pikchr.c
	@mkdir -p build
	emcc $(EMFLAGS) -o $@ $<

dist/extension.js: build/pikchr-wasm.js $(wildcard src/*.ts) tsconfig.json
	$(BIN)/tsc --noEmit
	$(BIN)/esbuild src/extension.ts $(ESBUILD_FLAGS) --outfile=$@

package: all
	$(BIN)/vsce package --no-dependencies --skip-license

clean:
	rm -rf build dist *.vsix

.PHONY: all package clean
