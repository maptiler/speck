local pandoc = require("pandoc")
local pikchr = require("pikchr")

local Context = {}
Context.__index = Context

function Context:new()
    self = setmetatable({}, Context)
    self.items = {}
    self.backrefs = {}
    self.para_count = 0
    self.table_count = 0
    self.figure_count = 0
    return self
end

function Context:run(doc)
    doc = doc:walk {
        CodeBlock = function(block)
            if block.classes:includes("pic") then
                return self:process_pic(block)
            end
        end
    }

    doc = doc:walk {
        Header = function(block)
            self:add_item(block)
        end,
        Para = function(block)
            return self:collect_paragraph(block)
        end,
        Table = function(block)
            return self:collect_table(block)
        end,
        Figure = function(block)
            return self:collect_figure(block)
        end,
        Span = function(inline)
            if inline.classes:includes("term") then
                self:add_item(inline)
            end
        end
    }

    for i, block in ipairs(doc.blocks) do
        doc.blocks[i] = pandoc.walk_block(block, {
            Cite = function(elem)
                return self:resolve_references(elem, block)
            end
        })
    end

    doc = doc:walk {
        Div = function(block)
            if block.classes:includes("para") then
                return self:trace_backrefs(block)
            end
        end
    }

    return doc
end

function Context:process_pic(block)
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

function Context:collect_paragraph(block)
    local first = block.content[1]

    -- Extract the paragraph identifier, if any.
    local para_id = nil
    if first and first.t == "Str" then
        para_id = first.text:match("^{#([%w%._-]+)}$")
        if para_id then
            -- Remove the header text.
            table.remove(block.content, 1)

            -- Remove blank space at the end of the header line.
            while #block.content > 0 do
                local elem = block.content[1]
                if elem.t == "SoftBreak" or elem.t == "LineBreak" then
                    table.remove(block.content, 1)
                else
                    break
                end
            end
        end
    end

    self.para_count = self.para_count + 1
    local para_num = self.para_count

    local div = pandoc.Div({ block })
    div.classes = pandoc.List { "para" }
    div.attributes["num"] = para_num

    if para_id then
        div.identifier = para_id
        self:add_item(div)
    else
        div.identifier = string.format("para-%d", para_num)
    end

    local link = pandoc.Link({ pandoc.Str(para_num) }, string.format("#%s", div.identifier))
    link.classes = pandoc.List { "num" }
    table.insert(div.content, link)

    return div
end

function Context:collect_table(block)
    self.table_count = self.table_count + 1
    local table_num = self.table_count

    if block.identifier then
        self:add_item(block)
    else
        block.identifier = string.format("tab-%d", table_num)
    end

    block.attributes["num"] = table_num
    table.insert(block.caption.long[1].content, 1, string.format("Table %d: ", table_num))
    return block
end

function Context:collect_figure(block)
    self.figure_count = self.figure_count + 1
    local figure_num = self.figure_count

    if block.identifier then
        self:add_item(block)
    else
        block.identifier = string.format("fig-%d", figure_num)
    end

    block.attributes["num"] = figure_num
    table.insert(block.caption.long[1].content, 1, string.format("Figure %d: ", figure_num))
    return block
end

function Context:add_item(item)
    assert(item.identifier)
    if self.items[item.identifier] then
        error("Duplicate item: " .. item.identifier)
    else
        self.items[item.identifier] = item
    end
end

function Context:resolve_references(cite, block)
    local items = {}
    local result = {}
    local unknown = 0
    local parenthesize = true

    for __, citation in ipairs(cite.citations) do
        local item = self.items[citation.id]
        table.insert(items, item)

        if not item then
            unknown = unknown + 1
        end

        if citation.mode == "AuthorInText" then
            parenthesize = false
        end
    end

    -- If all references are uknown, leave the element as it was.
    -- There might be other filters that will resolve it.
    if #cite.citations == unknown then
        return
    end

    if parenthesize then
        table.insert(result, pandoc.Str("("))
    end

    for i, citation in ipairs(cite.citations) do
        local item = items[i]
        if not item then
            error("Invalid citation: " .. citation.id)
        end

        if i > 1 then
            table.insert(result, pandoc.Str(","))
            table.insert(result, pandoc.Space())
        end

        if #citation.prefix > 0 then
            for __, inline in ipairs(citation.prefix) do
                table.insert(result, inline)
            end
            table.insert(result, pandoc.Space())
        end

        if item.t == "Header" then
            local link = pandoc.Link(item.content, "#" .. item.identifier)
            table.insert(result, pandoc.Str("section"))
            table.insert(result, pandoc.Space())
            table.insert(result, link)
        elseif item.t == "Table" then
            local link = pandoc.Link({ pandoc.Str(item.attributes["num"]) }, "#" .. item.identifier)
            table.insert(result, pandoc.Str("table"))
            table.insert(result, pandoc.Space())
            table.insert(result, link)
        elseif item.t == "Figure" then
            local link = pandoc.Link({ pandoc.Str(item.attributes["num"]) }, "#" .. item.identifier)
            table.insert(result, pandoc.Str("figure"))
            table.insert(result, pandoc.Space())
            table.insert(result, link)
        elseif item.t == "Div" and item.classes:includes("para") then
            local link = pandoc.Link({ pandoc.Str(item.attributes["num"]) }, "#" .. item.identifier)
            table.insert(result, link)
        elseif item.t == "Span" and item.classes:includes("term") then
            for __, inline in ipairs(item.content) do
                table.insert(result, inline)
            end
        else
            error("Reference to invalid element type: " .. item.t)
        end

        if #citation.suffix > 0 then
            for __, inline in ipairs(citation.suffix) do
                table.insert(result, inline)
            end
        end

        local refs = self.backrefs[item.identifier]
        if not refs then
            refs = {}
            self.backrefs[item.identifier] = refs
        end

        table.insert(refs, block)
    end

    if parenthesize then
        table.insert(result, pandoc.Str(")"))
    end

    return result
end

function Context:trace_backrefs(block)
    local refs = self.backrefs[block.identifier]
    if not refs then
        return
    end

    local content = {}
    for i, item in ipairs(refs) do
        if i > 1 then
            table.insert(content, pandoc.Str(","))
            table.insert(content, pandoc.Space())
        end

        local link = pandoc.Link(
            pandoc.Str(item.attributes["num"]),
            string.format("#%s", item.identifier)
        )
        table.insert(content, link)
    end

    local span = pandoc.Span(content)
    span.classes = pandoc.List { "backrefs" }
    table.insert(block.content, span)
    return block
end

function Pandoc(doc)
    return Context:new():run(doc)
end
