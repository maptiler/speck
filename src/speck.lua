local pandoc = require("pandoc")
local pikchr = require("pikchr")

local Context = {}
Context.__index = Context

local function is_speck(block)
    return block.t == "Div" and block.classes:includes("SPECK")
end

function Context:new()
    self = setmetatable({}, Context)
    self.elements = {}
    self.backrefs = {}
    self.item_count = 0
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

    -- We only want to collect items at the top level,
    -- not within admonitions, block quotes, etc.
    local specks = {}
    for i, block in ipairs(doc.blocks) do
        if is_speck(block) then
            self:collect_speck(block)
            specks[i] = true
        end
    end

    for i, block in ipairs(doc.blocks) do
        if specks[i] then
            -- Citations within items, which become the sources of back references.
            -- Relative references are resolved against the root item of the card,
            -- which is the closest preceding root row.
            local root = nil
            for j, div in ipairs(block.content) do
                if div.classes:includes("root") then
                    root = div.identifier
                end
                block.content[j] = div:walk {
                    Cite = function(elem)
                        return self:resolve_references(elem, root, div)
                    end
                }
            end
        else
            -- Citations outside of any item.
            doc.blocks[i] = block:walk {
                Cite = function(elem)
                    return self:resolve_references(elem, nil, nil)
                end
            }
        end
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

function Context:collect_speck(block)
    local list = block.content[1]
    if #block.content ~= 1 or list.t ~= "BulletList" then
        error("SPECK block must contain a single bullet list")
    end

    -- Each top-level item and its sub-items form a card. The item tree
    -- is flattened into a grid of rows, with the depth of each item kept
    -- only as the indentation of its label. Top-level items are marked
    -- as roots, so that cards can be separated.
    local rows = {}
    self:collect_items(list.content, nil, 0, rows)

    block.classes = pandoc.List { "speck" }
    block.content = rows
end

function Context:collect_items(list, prefix, depth, rows)
    for _, item in ipairs(list) do
        local first = item[1]

        -- Extract the item identifier, a phrase terminated by a colon.
        -- The phrase is shown as the label, and joined with underscores
        -- to form the identifier used in cross-references.
        local phrase = nil
        local phrase_len = 0
        local local_id = nil
        if first ~= nil and first.t == "Plain" then
            local words = {}
            for i, elem in ipairs(first.content) do
                if elem.t == "Str" and elem.text:match("^[%w.]+:$") then
                    table.insert(words, elem.text:sub(1, -2))
                    phrase_len = i
                    break
                elseif elem.t == "Str" and elem.text:match("^[%w.]+$") then
                    table.insert(words, elem.text)
                elseif elem.t ~= "Space" then
                    break
                end
            end
            if phrase_len > 0 then
                phrase = table.concat(words, " ")
                local_id = table.concat(words, "_")
            end
        end

        if first ~= nil and first.t == "Para" then
            error("Loose list item in " .. (prefix or "SPECK block") .. " (remove the blank lines between items)")
        elseif local_id == nil then
            error("List item without identifier in " .. (prefix or "SPECK block"))
        end

        -- Remove the identifier and the blank space after it.
        for _ = 1, phrase_len do
            table.remove(first.content, 1)
        end
        while #first.content > 0 do
            local elem = first.content[1]
            if elem.t == "Space" or elem.t == "SoftBreak" or elem.t == "LineBreak" then
                table.remove(first.content, 1)
            else
                break
            end
        end

        self.item_count = self.item_count + 1
        local item_num = tostring(self.item_count)
        local item_id = prefix and string.format("%s.%s", prefix, local_id) or local_id

        local ref = pandoc.Link({ pandoc.Str(item_num) }, "#" .. item_id)
        ref.classes = pandoc.List { "item" }

        local backrefs = pandoc.Span({})
        backrefs.identifier = item_id
        backrefs.classes = pandoc.List { "backrefs" }

        local label = pandoc.Div({ pandoc.Plain({ pandoc.Str(phrase) }) })
        label.classes = pandoc.List { "label" }
        label.attributes = { style = string.format("--depth: %d", depth) }

        local text = pandoc.Div({ first })
        text.classes = pandoc.List { "text" }

        local div = pandoc.Div({ ref, label, text, backrefs })
        div.identifier = item_id
        div.classes = pandoc.List { "item" }
        if depth == 0 then
            div.classes:insert("root")
        end
        div.attributes = { num = item_num }
        self:add_element(div)
        table.insert(rows, div)

        -- An item may only contain its text and a list of sub-items.
        local sublist = item[2]
        if #item > 2 or (sublist ~= nil and sublist.t ~= "BulletList") then
            error("Item " .. item_id .. " may only contain a bullet list of sub-items")
        end

        -- Number the children after their parent.
        if sublist ~= nil then
            self:collect_items(sublist.content, item_id, depth + 1, rows)
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

function Context:resolve_references(cite, root, source)
    local result = {}
    local unknown = {}
    local parenthesize = true

    for i, citation in ipairs(cite.citations) do
        if citation.mode == "AuthorInText" then
            parenthesize = false
        end

        local element_id
        local item_id = citation.id:match("^self%.(.+)$")

        if item_id and root == nil then
            error("Reference outside of a card: " .. citation.id)
        elseif item_id then
            element_id = string.format("%s.%s", root, item_id)
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
                local link = pandoc.Link({ pandoc.Str(element.attributes["num"]) }, "#" .. element.identifier)
                table.insert(result, link)
            else
                error("Reference to invalid element type: " .. element.t)
            end

            if #citation.suffix > 0 then
                for __, inline in ipairs(citation.suffix) do
                    table.insert(result, inline)
                end
            end

            -- Back references can only point to numbered items.
            if source ~= nil then
                local refs = self.backrefs[element_id]
                if not refs then
                    refs = {}
                    self.backrefs[element_id] = refs
                end

                local ref_num = tonumber(source.attributes["num"])
                assert(ref_num ~= nil)
                refs[ref_num] = source.identifier
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
        if i > 1 then
            table.insert(span.content, pandoc.Str(","))
            table.insert(span.content, pandoc.Space())
        end

        local link = pandoc.Link({ pandoc.Str(tostring(ref_num)) }, "#" .. refs[ref_num])
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
