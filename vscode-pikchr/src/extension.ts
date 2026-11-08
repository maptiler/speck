import * as vscode from "vscode";
import { Diagnostics } from "./diagnostics";
import { Pikchr } from "./pikchr";
import { Preview } from "./preview";

export async function activate(context: vscode.ExtensionContext) {
    const pikchr = await Pikchr.load();
    const preview = new Preview(context.extensionUri, pikchr);

    // Commands receive the URI of the file when invoked from a menu, and nothing from a keybinding.
    const showPreview = (toSide: boolean) => (uri?: unknown) => {
        const target = uri instanceof vscode.Uri ? uri : vscode.window.activeTextEditor?.document.uri;
        if (target) {
            preview.show(target, toSide);
        }
    };

    context.subscriptions.push(
        preview,
        new Diagnostics(pikchr),
        vscode.commands.registerCommand("pikchr.showPreview", showPreview(false)),
        vscode.commands.registerCommand("pikchr.showPreviewToSide", showPreview(true)),
    );
}

export function deactivate() {}
