import * as vscode from "vscode";
import { Pikchr } from "./pikchr";

const UPDATE_DELAY_MS = 200;

// Shows Pikchr errors as diagnostics (underlines in the editor and entries in the Problems panel).
export class Diagnostics implements vscode.Disposable {
    private readonly collection = vscode.languages.createDiagnosticCollection("pikchr");
    private readonly timers = new Map<string, NodeJS.Timeout>();
    private readonly disposables: vscode.Disposable[] = [this.collection];

    constructor(private readonly pikchr: Pikchr) {
        this.disposables.push(
            vscode.workspace.onDidOpenTextDocument((document) => this.update(document)),
            vscode.workspace.onDidChangeTextDocument((event) => {
                if (event.contentChanges.length > 0) {
                    this.schedule(event.document);
                }
            }),
            vscode.workspace.onDidCloseTextDocument((document) => this.clear(document.uri)),
        );
        vscode.workspace.textDocuments.forEach((document) => this.update(document));
    }

    dispose() {
        this.timers.forEach((timer) => clearTimeout(timer));
        this.disposables.forEach((disposable) => disposable.dispose());
    }

    private schedule(document: vscode.TextDocument) {
        if (document.languageId !== "pikchr") {
            return;
        }
        const key = document.uri.toString();
        clearTimeout(this.timers.get(key));
        this.timers.set(
            key,
            setTimeout(() => {
                this.timers.delete(key);
                this.update(document);
            }, UPDATE_DELAY_MS),
        );
    }

    private update(document: vscode.TextDocument) {
        // The language can change, e.g. through "Change Language Mode".
        if (document.languageId !== "pikchr" || document.isClosed) {
            this.clear(document.uri);
            return;
        }
        const result = this.pikchr.render(document.getText());
        this.collection.set(document.uri, result.ok ? [] : [parseError(result.error, document)]);
    }

    private clear(uri: vscode.Uri) {
        const key = uri.toString();
        clearTimeout(this.timers.get(key));
        this.timers.delete(key);
        this.collection.delete(uri);
    }
}

// Converts a plain text Pikchr error into a diagnostic. The error looks like this:
//
//   /*    3 */  box wid 1 ht 1
//   /*    4 */  bogus thing
//                     ^^^^^
//   ERROR: syntax error
//
// The numbered lines show the source preceding the error, the carets mark the offending token,
// using byte offsets into the UTF-8 encoded line. Errors without a location (e.g. out of memory)
// are reported at the start of the document.
export function parseError(error: string, document: vscode.TextDocument): vscode.Diagnostic {
    const lines = error.split("\n");
    const messageLine = lines.find((line) => line.startsWith("ERROR: "));
    const message = messageLine ? messageLine.slice("ERROR: ".length) : error.trim();

    let range = new vscode.Range(0, 0, 0, 0);
    const caretIndex = lines.findIndex((line) => /^ *\^+ *$/.test(line));
    const lineMatch = caretIndex > 0 ? /^\/\* *(\d+) \*\/ {2}/.exec(lines[caretIndex - 1]) : null;

    if (lineMatch) {
        const line = Math.min(Number(lineMatch[1]) - 1, document.lineCount - 1);
        const caret = lines[caretIndex].trimEnd();
        const caretStart = caret.indexOf("^");
        // The carets are indented to align with the 12 character line number prefix,
        // except on the first line, where Pikchr indents them one column less.
        const startByte = Math.max(0, caretStart - (line === 0 ? 11 : 12));
        const endByte = startByte + caret.length - caretStart;
        const text = document.lineAt(line).text;
        range = new vscode.Range(line, byteToColumn(text, startByte), line, byteToColumn(text, endByte));
    }

    const diagnostic = new vscode.Diagnostic(range, message, vscode.DiagnosticSeverity.Error);
    diagnostic.source = "pikchr";
    return diagnostic;
}

// Converts a byte offset in the UTF-8 encoding of `text` into a (UTF-16) column in `text`.
function byteToColumn(text: string, byteOffset: number): number {
    return Buffer.from(text, "utf8").subarray(0, byteOffset).toString("utf8").length;
}
