local pandoc = require("pandoc")
local pikchr = require("pikchr")

function Pandoc(doc)
    return doc:walk {
        CodeBlock = function(block)
            if block.classes:includes("pikchr") then
                local svg = pikchr.compile(block.text)
                local figure = pandoc.Figure({ pandoc.RawInline("html", svg) })

                if block.identifier then
                    figure.identifier = block.identifier
                end

                local caption = block.attributes["caption"]
                if caption then
                    figure.caption = pandoc.Caption({ caption })
                end

                return figure
            end
        end
    }
end
