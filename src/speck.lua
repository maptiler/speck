local pandoc = require("pandoc")
local pikchr = require("pikchr")

local Context = {}
Context.__index = Context

function Context:new()
    self = setmetatable({}, Context)
    self.elements = {}
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
        end,
        Table = function(block)
            if block.attributes["ratio"] ~= nil then
                return self:process_table(block)
            end
        end,
        Div = function(block)
            return self:process_div(block)
        end,
    }

    doc = doc:walk {
        Header = function(block)
            self:add_element(block)
        end,
        Table = function(block)
            return self:collect_table(block)
        end,
        Figure = function(block)
            return self:collect_figure(block)
        end,
    }

    -- We only want to collect paragraphs at the top level,
    -- not within admonitions, block quotes, etc.
    for i, block in ipairs(doc.blocks) do
        if block.t == "Para" then
            doc.blocks[i] = self:collect_paragraph(block)
        elseif block.t == "Div" and #block.classes == 0 then
            self:collect_card(block)
        end
    end

    for i, block in ipairs(doc.blocks) do
        doc.blocks[i] = block:walk {
            Cite = function(elem)
                return self:resolve_references(elem, block)
            end
        }
    end

    doc = doc:walk {
        Span = function(span)
            if span.classes:includes("backrefs") then
                return self:trace_backrefs(span)
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

    if block.classes:includes("wide") then
        table.insert(figure.classes, "wide")
    end

    local caption = block.attributes["caption"]
    if caption then
        figure.caption = pandoc.Caption({ caption })
    end

    return figure
end

function Context:process_table(block)
    local widths = {}
    local total = 0
    for value in block.attributes["ratio"]:gmatch("([^,]+)") do
        local width = tonumber(value)
        table.insert(widths, width)
        total = total + width
    end

    local specs = {}
    for i, spec in ipairs(block.colspecs) do
        table.insert(specs, { spec[1], widths[i] / total })
    end

    block.attributes["ratio"] = nil
    block.colspecs = specs
    return block
end

function Context:process_div(block)
    if block.classes:includes("note")
        or block.classes:includes("info")
        or block.classes:includes("warning")
    then
        block.classes:insert("admonition")
        return block
    end
end

function Context:collect_paragraph(block)
    local first = block.content[1]

    -- Extract the paragraph identifier, if any.
    local para_id = nil
    if first and first.t == "Str" then
        para_id = first.text:match("^{#([%w-]+)}$")
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
    div.attributes["num"] = tostring(para_num)

    if para_id then
        div.identifier = para_id
        self:add_element(div)
    else
        div.identifier = string.format("para-%d", para_num)
    end

    local ref = pandoc.Link({ pandoc.Str(para_num) }, string.format("#%s", div.identifier))
    ref.classes = pandoc.List { "para" }
    table.insert(div.content, ref)

    local backrefs = pandoc.Span({})
    backrefs.identifier = para_id
    backrefs.classes = pandoc.List { "backrefs" }
    table.insert(div.content, backrefs)

    return div
end

function Context:collect_card(block)
    local definition_list
    local first_block = block.content[1]

    -- Detect whether there is a definition list.
    -- Allow card name without any definitions.
    if first_block == nil then
        return
    elseif first_block.t == "DefinitionList" then
        definition_list = first_block
    elseif first_block.t == "Para" then
        definition_list = block.content[2]
        if definition_list == nil or definition_list.t ~= "DefinitionList" then
            return
        end
        table.remove(block.content, 1)
        table.insert(definition_list.content, 1, { first_block.content, {} })
    end

    self.para_count = self.para_count + 1
    local para_num = self.para_count

    if not block.identifier then
        block.identifier = string.format("para-%d", para_num)
    end

    block.classes:insert("card")
    block.classes:insert("para")
    block.attributes = { num = tostring(para_num) }
    self:add_element(block)

    local n = 0
    for i, definition_item in ipairs(definition_list.content) do
        if i == 1 then
            local term = definition_item[1]

            local ref = pandoc.Link({ pandoc.Str(para_num) }, string.format("#%s", block.identifier))
            ref.classes = pandoc.List { "para" }
            table.insert(term, ref)

            local backrefs = pandoc.Span({})
            backrefs.identifier = block.identifier
            backrefs.classes = pandoc.List { "backrefs" }
            table.insert(term, backrefs)
        end

        -- Do not number the first item. It should only contain the
        -- name and some metadata.
        if i > 1 or first_block.t == "Para" then
            local definitions = definition_item[2]
            for j, definition in ipairs(definitions) do
                n = n + 1

                local local_id = nil
                local first = definition[1]

                -- Extract the item identifier, if any.
                if first ~= nil and first.t == "Plain" then
                    local elem = first.content[1]
                    if elem and elem.t == "Str" then
                        local_id = elem.text:match("^{#([%w-]+)}$")
                        if local_id then
                            -- Remove the header text.
                            table.remove(first.content, 1)

                            -- Remove blank space at the end of the header line.
                            while #first.content > 0 do
                                elem = first.content[1]
                                if elem.t == "SoftBreak" or elem.t == "LineBreak" then
                                    table.remove(first.content, 1)
                                else
                                    break
                                end
                            end
                        end
                    end
                end

                local div = pandoc.Div(definition)
                div.classes = pandoc.List { "item" }
                div.attributes = { num = string.format("%d.%d", para_num, n) }

                if local_id ~= nil then
                    div.identifier = string.format("%s.%s", block.identifier, local_id)
                    self:add_element(div)
                else
                    div.identifier = string.format("%s.%s", block.identifier, n)
                end

                local ref = pandoc.Link({ pandoc.Str(string.format("%d.", n)) }, "#" .. div.identifier)
                ref.classes = pandoc.List { "item" }
                table.insert(div.content, 1, ref)

                local backrefs = pandoc.Span({})
                backrefs.identifier = div.identifier
                backrefs.classes = pandoc.List { "backrefs" }
                table.insert(div.content, backrefs)

                definitions[j] = { div }
            end
        end
    end
end

function Context:collect_table(block)
    self.table_count = self.table_count + 1
    local table_num = self.table_count

    if block.identifier then
        self:add_element(block)
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
        self:add_element(block)
    else
        block.identifier = string.format("fig-%d", figure_num)
    end

    block.attributes["num"] = figure_num
    table.insert(block.caption.long[1].content, 1, string.format("Figure %d: ", figure_num))
    return block
end

function Context:add_element(element)
    assert(element.identifier)
    if self.elements[element.identifier] then
        error("Duplicate element: " .. element.identifier)
    else
        self.elements[element.identifier] = element
    end
end

function Context:resolve_references(cite, block)
    local result = {}
    local unknown = {}
    local parenthesize = true

    for i, citation in ipairs(cite.citations) do
        if citation.mode == "AuthorInText" then
            parenthesize = false
        end

        local element_id
        local item_id = citation.id:match("^self%.([%w-]+)$")

        if item_id then
            element_id = string.format("%s.%s", block.identifier, item_id)
        else
            element_id = citation.id
        end

        local element = self.elements[element_id]
        if element == nil then
            table.insert(unknown, citation)
        else
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

            if element.t == "Header" then
                local link = pandoc.Link(element.content, "#" .. element.identifier)
                table.insert(result, pandoc.Str("section"))
                table.insert(result, pandoc.Space())
                table.insert(result, link)
            elseif element.t == "Table" then
                local link = pandoc.Link({ pandoc.Str(element.attributes["num"]) }, "#" .. element.identifier)
                table.insert(result, pandoc.Str("table"))
                table.insert(result, pandoc.Space())
                table.insert(result, link)
            elseif element.t == "Figure" then
                local link = pandoc.Link({ pandoc.Str(element.attributes["num"]) }, "#" .. element.identifier)
                table.insert(result, pandoc.Str("figure"))
                table.insert(result, pandoc.Space())
                table.insert(result, link)
            elseif element.t == "Div" then
                local text
                if item_id then
                    local item_num = element.attributes["num"]:sub(#block.attributes["num"] + 2)
                    text = { pandoc.RawInline("html", "&bull;"), pandoc.Str(item_num) }
                else
                    text = { pandoc.Str(element.attributes["num"]) }
                end
                local link = pandoc.Link(text, "#" .. element.identifier)
                table.insert(result, link)
            else
                error("Reference to invalid element type: " .. element.t)
            end

            if #citation.suffix > 0 then
                for __, inline in ipairs(citation.suffix) do
                    table.insert(result, inline)
                end
            end

            local refs = self.backrefs[element_id]
            if not refs then
                refs = {}
                self.backrefs[element_id] = refs
            end

            local ref_num
            if item_id then
                ref_num = 0
            else
                ref_num = tonumber(block.attributes["num"])
                assert(ref_num ~= nil)
            end

            if refs[ref_num] == nil then
                refs[ref_num] = block
            end
        end
    end

    if #unknown > 0 then
        -- If all references are uknown, leave the element as it was.
        -- There might be other filters that will resolve it.
        if #unknown == #cite.citations then
            return
        else
            error("Invalid cite element")
        end
    end

    if parenthesize then
        table.insert(result, 1, pandoc.Str("("))
        table.insert(result, pandoc.Str(")"))
    end

    return result
end

function Context:trace_backrefs(span)
    local refs = self.backrefs[span.identifier]

    -- The spans were created for all possible reference targets.
    -- Most of them will not have been targeted, so we remove their
    -- spans to save space in the output.
    if refs == nil then
        return {}
    end

    local ref_nums = {}
    for ref_num in pairs(refs) do
        table.insert(ref_nums, ref_num)
    end

    table.sort(ref_nums)

    for i, ref_num in ipairs(ref_nums) do
        local element = refs[ref_num]

        if i > 1 then
            table.insert(span.content, pandoc.Str(","))
            table.insert(span.content, pandoc.Space())
        end

        local text
        if ref_num == 0 then
            text = pandoc.RawInline("html", "&bull;")
        else
            text = pandoc.Str(element.attributes["num"])
        end

        local link = pandoc.Link(text, string.format("#%s", element.identifier))
        table.insert(span.content, link)
    end

    -- The identifier is used only to get the list of references.
    -- We don't need it in the output, so we remove it here.
    span.identifier = ""
    return span
end

function Pandoc(doc)
    return Context:new():run(doc)
end
