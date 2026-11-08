# Pikchr for VS Code

Support for [Pikchr](https://pikchr.org) diagrams in `.pikchr` files:

- syntax highlighting,
- a live preview, which updates while you type,
- errors underlined in the editor and listed in the Problems panel.

Diagrams are rendered by the same Pikchr source code that SPECK uses (`src/pikchr.c`),
compiled to WebAssembly, so the preview matches the generated documentation.

## Usage

Open a `.pikchr` file and click the preview button in the editor title bar,
or run **Pikchr: Open Preview to the Side** (`Ctrl+K V`) or **Pikchr: Open Preview** (`Ctrl+Shift+V`).
The preview follows the active Pikchr editor.

## Development

The build needs Emscripten and Node.js, both are available in the SPECK devcontainer.

```sh
cd vscode-pikchr
npm install       # once
make              # build dist/extension.js
make package      # build pikchr-VERSION.vsix
```

To try the extension, run **Run Pikchr extension** from the Run and Debug view (F5).
It opens a new VS Code window with the extension loaded.

The `.vscodeignore` file lists what `make package` leaves out of the `.vsix` (sources, intermediate build outputs, source maps).
Keep it, otherwise the package includes the whole directory. When adding files, check what gets packaged with `node_modules/.bin/vsce ls --no-dependencies`.

To install the packaged extension, run **Extensions: Install from VSIX...** and select the `.vsix` file.
