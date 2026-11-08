import { randomBytes } from "node:crypto";
import * as path from "node:path";
import * as vscode from "vscode";
import { Pikchr, RenderResult } from "./pikchr";

const VIEW_TYPE = "pikchr.preview";
const UPDATE_DELAY_MS = 1000;
// While typing, the code is often temporarily invalid. Errors are only shown
// once the user stops typing for this long, until then the last diagram stays.
const ERROR_DELAY_MS = 2000;

// State persisted by the webview (see `media/preview.js`), used to restore the panel after a reload.
interface PreviewState {
    uri?: string;
}

// Message sent to the webview whenever the diagram changes.
type RenderMessage = { type: "render"; uri: string } & RenderResult;

// A single preview panel which shows the most recently active Pikchr document,
// and updates while it is being edited, similarly to the Markdown preview.
export class Preview implements vscode.Disposable {
    private panel: vscode.WebviewPanel | undefined;
    private uri: vscode.Uri | undefined;
    private timer: NodeJS.Timeout | undefined;
    private errorTimer: NodeJS.Timeout | undefined;
    private readonly disposables: vscode.Disposable[] = [];

    constructor(
        private readonly extensionUri: vscode.Uri,
        private readonly pikchr: Pikchr,
    ) {
        this.disposables.push(
            vscode.window.registerWebviewPanelSerializer(VIEW_TYPE, {
                deserializeWebviewPanel: async (panel: vscode.WebviewPanel, state?: PreviewState) => {
                    if (state?.uri && !this.panel) {
                        this.attach(panel);
                        this.setDocument(vscode.Uri.parse(state.uri));
                    } else {
                        panel.dispose();
                    }
                },
            }),
            vscode.workspace.onDidChangeTextDocument((event) => {
                if (event.contentChanges.length > 0 && this.isShowing(event.document.uri)) {
                    this.schedule();
                }
            }),
            vscode.window.onDidChangeActiveTextEditor((editor) => {
                if (this.panel && editor?.document.languageId === "pikchr") {
                    this.setDocument(editor.document.uri);
                }
            }),
        );
    }

    dispose() {
        this.clearTimers();
        this.panel?.dispose();
        this.disposables.forEach((disposable) => disposable.dispose());
    }

    show(uri: vscode.Uri, toSide: boolean) {
        if (this.panel) {
            this.panel.reveal(undefined, toSide);
        } else {
            const column = toSide ? vscode.ViewColumn.Beside : vscode.ViewColumn.Active;
            this.attach(
                vscode.window.createWebviewPanel(VIEW_TYPE, "", { viewColumn: column, preserveFocus: toSide }),
            );
        }
        this.setDocument(uri);
    }

    private attach(panel: vscode.WebviewPanel) {
        this.panel = panel;
        panel.webview.options = {
            enableScripts: true,
            localResourceRoots: [vscode.Uri.joinPath(this.extensionUri, "media")],
        };
        panel.webview.html = this.html(panel.webview);
        panel.webview.onDidReceiveMessage((message) => {
            // The webview (re)loaded, e.g. after the panel was hidden and shown again.
            if (message?.type === "ready") {
                this.update();
            }
        });
        panel.onDidDispose(() => {
            this.clearTimers();
            this.panel = undefined;
            this.uri = undefined;
        });
    }

    private setDocument(uri: vscode.Uri) {
        if (!this.panel || this.uri?.toString() === uri.toString()) {
            return;
        }
        this.uri = uri;
        this.panel.title = `Preview ${path.basename(uri.path)}`;
        this.update();
    }

    private isShowing(uri: vscode.Uri): boolean {
        return this.panel !== undefined && this.uri?.toString() === uri.toString();
    }

    private clearTimers() {
        clearTimeout(this.timer);
        clearTimeout(this.errorTimer);
    }

    private schedule() {
        this.clearTimers();
        this.timer = setTimeout(() => this.update(true), UPDATE_DELAY_MS);
    }

    // `typing` is true for updates caused by edits, errors are then shown with a delay.
    private async update(typing = false) {
        this.clearTimers();
        const uri = this.uri;
        if (!this.panel || !uri) {
            return;
        }

        let result: RenderResult;
        try {
            // Returns the already open document, or loads it from disk if it was closed.
            const document = await vscode.workspace.openTextDocument(uri);
            result = this.pikchr.render(document.getText());
        } catch (e) {
            result = { ok: false, error: `Cannot open ${uri.fsPath}: ${e}` };
        }

        // Another document may have been selected in the meantime.
        if (!this.panel || this.uri !== uri) {
            return;
        }
        const message: RenderMessage = { type: "render", uri: uri.toString(), ...result };
        const post = () => this.panel?.webview.postMessage(message);
        if (!result.ok && typing) {
            // Cancelled by the next edit (see `schedule`).
            this.errorTimer = setTimeout(post, ERROR_DELAY_MS);
        } else {
            post();
        }
    }

    private html(webview: vscode.Webview): string {
        const media = (file: string) => webview.asWebviewUri(vscode.Uri.joinPath(this.extensionUri, "media", file));
        const nonce = randomBytes(16).toString("base64");
        // Pikchr sets the style attribute on SVG elements, which requires 'unsafe-inline'.
        const csp = [
            "default-src 'none'",
            `style-src ${webview.cspSource} 'unsafe-inline' https://fonts.googleapis.com`,
            "font-src https://fonts.gstatic.com",
            `script-src 'nonce-${nonce}'`,
        ].join("; ");

        return `<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="Content-Security-Policy" content="${csp}">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:ital,opsz,wght@0,14..32,100..900;1,14..32,100..900&display=swap">
    <link rel="stylesheet" href="${media("preview.css")}">
</head>
<body>
    <pre id="error" hidden></pre>
    <div id="diagram"></div>
    <script nonce="${nonce}" src="${media("preview.js")}"></script>
</body>
</html>`;
    }
}
