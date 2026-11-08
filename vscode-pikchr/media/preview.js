// Script of the preview webview, receives rendered diagrams from `src/preview.ts`.
(function () {
    const vscode = acquireVsCodeApi();
    const diagram = document.getElementById("diagram");
    const error = document.getElementById("error");
    let uri = vscode.getState()?.uri;

    window.addEventListener("message", (event) => {
        const message = event.data;
        if (message.type !== "render") {
            return;
        }

        // Do not show the stale diagram of a different document.
        if (message.uri !== uri) {
            uri = message.uri;
            diagram.innerHTML = "";
            // Remember the document, so that VS Code can restore the preview after a reload.
            vscode.setState({ uri });
        }

        if (message.ok) {
            diagram.innerHTML = message.svg;
            diagram.classList.remove("stale");
            error.hidden = true;
        } else {
            error.textContent = message.error.trim();
            error.hidden = false;
            diagram.classList.add("stale");
        }
    });

    vscode.postMessage({ type: "ready" });
})();
