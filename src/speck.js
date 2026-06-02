document.addEventListener("DOMContentLoaded", function () {
    document.querySelectorAll("h1, h2, h3, h4, h5, h6").forEach(function (elem) {
        if (elem.tagName == "H1" && elem.parentElement.tagName == "HEADER")
            return;
        const anchor = document.createElement("a");
        anchor.href = `#${elem.id}`;
        anchor.className = "anchor";
        anchor.innerHTML = "&thinsp;&sect;"
        anchor.ariaHidden = "true";
        elem.appendChild(anchor);
    });
    document.querySelectorAll("table caption, figcaption").forEach(function (elem) {
        const anchor = document.createElement("a");
        anchor.href = `#${elem.parentElement.id}`;
        anchor.className = "anchor";
        anchor.innerHTML = "&thinsp;&sect;"
        anchor.ariaHidden = "true";
        elem.appendChild(anchor);
    });
});
