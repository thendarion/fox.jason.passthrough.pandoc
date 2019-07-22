--
--	This file is part of the DITA Pandoc project.
--	See the accompanying LICENSE file for applicable licenses.
-- 

-------------------------------------------------------------------
--
--  Module level varaibles used for DITA processing
--
-------------------------------------------------------------------

-- Variable to store footnotes, so they can be included after the end of a paragraph.
local note = nil
local topics = {[0] = {elem = {}, open = true}}
local parent = {0, 0, 0, 0, 0, 0}
local level = {{}, {}, {}, {}, {}, {}}

-------------------------------------------------------------------
--
--  Local functions used for DITA processing
--
-------------------------------------------------------------------


-- Character escaping
local function escape(s, in_attribute)
  return s:gsub("[<>&\"']",
    function(x)
      if x == '<' then
        return '&lt;'
      elseif x == '>' then
        return '&gt;'
      elseif x == '&' then
        return '&amp;'
      elseif x == '"' then
        return '&quot;'
      elseif x == "'" then
        return '&#39;'
      else
        return x
      end
    end)
end


-- Adds a DITA  element to an arbitrary topic
local function pushElementToTopic (index, s)
   table.insert(topics[index].elem, s)
end


-- Adds a DITA block-level element to the current topic
local function pushElementToCurrentTopic (s)
  pushElementToTopic(#topics, s)
end


-- Returns the latest block element added to the current topic
local function getLastTopicElement()
  return topics[#topics].elem[#topics[#topics].elem]
end


-- Removes a block element from the current topic.
-- This function is called when an element has been added in the wrong place.
local function popElementFromCurrentTopic ()
  table.remove(topics[#topics].elem, #topics[#topics].elem)
end


-- Reverses the direction of an array
-- This is needed for <ol> and <ul> processing since we could have added <li><p> 
-- elements to the topic directly and we need to unwind them from the stack
local function reverseArray (arr)
  local i, j = 1, #arr

  while i < j do
    arr[i], arr[j] = arr[j], arr[i]

    i = i + 1
    j = j - 1
  end
end


-- Helper function to convert an attributes table into
-- a string that can be put into HTML tags.
local function attributes(attr)
  local attr_table = {}
  for x,y in pairs(attr) do
    if y and y ~= "" then
      y = string.gsub(y, '_', '-')
      y =  string.lower(y)

      if x == "class" then
        table.insert(attr_table, ' outputclass="' .. escape(y,true) .. '"')
      else
        table.insert(attr_table, ' ' .. x .. '="' .. escape(y,true) .. '"')
      end
    end
  end
  return table.concat(attr_table)
end


-- Run cmd on a temporary file containing inp and return result.
-- local function pipe(cmd, inp)
--  local tmp = os.tmpname()
--  local tmph = io.open(tmp, "w")
--  tmph:write(inp)
--  tmph:close()
--  local outh = io.popen(cmd .. " " .. tmp,"r")
--  local result = outh:read("*all")
--  outh:close()
--  os.remove(tmp)
--  return result
--end


-- Check used to determine if links are internal to the document.
function string.starts(String,Start)
   return string.sub(String,1,string.len(Start))==Start
end


-- Check used to split an input string used for <keyword> processing
function string.split(String, sep)
  if sep == nil then
    sep = "%s"
  end
  local t={} ; i=1
  for str in string.gmatch(String, "([^"..sep.."]+)") do
    t[i] = str
    i = i + 1
  end
  return t
end

-- The Document title can come from either the meta data or from the command line.
-- Use a default title for the root topic if no title is provided
local function getRootTopicTitle(metadata)
  local title = 'Document'
  if metadata.title ~= nil then
    title = metadata.title
  end
  return title
end


-- Convert pandoc alignment to something DITA can use.
-- align is AlignLeft, AlignRight, AlignCenter, or AlignDefault.
-- Used by <table> elements.
local function dita_align(align)
  if align == 'AlignLeft' then
    return 'left'
  elseif align == 'AlignRight' then
    return 'right'
  elseif align == 'AlignCenter' then
    return 'center'
  else
    return 'left'
  end
end


-- Close the existing topic body if it is still open.
-- i.e. this topic has no further subtopics.
local function closeTopicBody (index)
  if(topics[index].open == true) then
     pushElementToTopic(index, "</body>")
     topics[index].open = false
  end 
end 


-- Element manipulation to ensure that DITA <topics> are
-- nested and closed properly
local function nestTopicWithinParent (index, parent)

  -- Close the existing topic body if it is still open.
  -- i.e. this topic has no subtopics.
  closeTopicBody(index)
  pushElementToTopic(index, "</topic>\n")
  -- Close the existing parent body if it is still open
  closeTopicBody(parent)

  -- Add to parent if it is a subtopic - otherwise add to the root topic
  if (parent == 1) then
    -- Close the root topic body if it is still open
    closeTopicBody(0)
    pushElementToTopic(0, table.concat( topics[index].elem ,'\n'))
  else
    pushElementToTopic(parent, table.concat( topics[index].elem ,'\n'))
  end
end


-------------------------------------------------------------------
--
--  All functions from here are called directly by Pandoc
--
--------------------------------------------------------------------

-- Blocksep is used to separate block elements.
function Blocksep()
  return "\n\n"
end


-- This function is called once for the whole document. Parameters:
-- body is a string, metadata is a table, variables is a table.
-- This gives you a fragment.  You could use the metadata table to
-- fill variables in a custom lua template.  Or, pass `--template=...`
-- to pandoc, and pandoc will add do the template processing as
-- usual.
function Doc(body, metadata, variables)
  local buffer = {}
  local function add(s)
    table.insert(buffer, s)
  end

  -- Iterate across h1 to h6 topics and add to the associated
  -- parent topic.
  for i = 6, 1, -1 do 
    for j = 1,  #level[i] do
      -- The +1 here is because LUA defaults to using 1 based arrays
      -- The topic[0] has been added as a root element so the counting is out
      nestTopicWithinParent (level[i][j].index + 1, level[i][j].parent + 1)
    end
  end

  -- Just in case we have a document with no headers, check to close the 
  -- root topic body as it may still be open.
  closeTopicBody(0)

  -- Now we start to create the real output
  
  -- Standard DITA xml preamble.
  add('<?xml version="1.0" encoding="UTF-8"?>')
--  add('<!DOCTYPE topic PUBLIC "-//OASIS//DTD DITA Topic//EN" "topic.dtd">')

  add('<?doctype-public -//OASIS//DTD DITA Topic//EN?>')
  add('<?doctype-system topic.dtd?>')

  -- Add a title to the root DITA topic - this should have a reasonable 
  -- default as a fallback.
  local rootTopicTitle = getRootTopicTitle(metadata)

  -- rootTopicTitle = string.gsub(rootTopicTitle, '_', '-')
   rootTopicId = string.gsub(rootTopicTitle, "[#_;<>&\"']", '-')
   rootTopicId = string.lower(rootTopicId)


  add('<topic xmlns:ditaarch="http://dita.oasis-open.org/architecture/2005/" xmlns:dita-ot="http://dita-ot.sourceforge.net/ns/201007/dita-ot" class="- topic/topic " ditaarch:DITAArchVersion="1.3" domains="(topic abbrev-d) a(props deliveryTarget) (topic equation-d) (topic hazard-d) (topic hi-d) (topic indexing-d) (topic markup-d) (topic mathml-d) (topic pr-d) (topic relmgmt-d) (topic sw-d) (topic svg-d) (topic ui-d) (topic ut-d) (topic markup-d xml-d)" id="' .. string.gsub(rootTopicId, ' ', '-') .. '">')

   -- Copy over meta data fields as comments if they exist
  if metadata.title ~= nil then
    add('  <data name="title" value="' .. metadata.title .. '"/>')
  end
  if metadata.subtitle ~= nil then
    add('  <data name="subtitle" value="' .. metadata.subtitle .. '"/>')
  end
  if metadata.date ~= nil then
    add('  <data name="date"  value="' .. metadata.date .. '"/>')
  end


  add('<title class="- topic/title " >' .. rootTopicTitle .. '</title>')
  add('<body class="- topic/body " >')
  -- Add all the elements contained within the root DITA topic, then close it
  add(table.concat( topics[0].elem ,'\n'))
  add('</topic>\n')


  return table.concat(buffer,'\n') .. '\n'
end

-- The functions that follow render corresponding pandoc elements.
-- s is always a string, attr is always a table of attributes, and
-- items is always an array of strings (the items in a list).
-- Comments indicate the types of other variables.


function Str(s)
  return escape(s)
end


function Space()
  return " "
end


-- Linebreak does not translate directly to a DITA element
-- Add a carriage return
function LineBreak()
  return "\n"
end


-- Emph is an inline element that translates to <i>
function Emph(s)
  return "<i class=' hi-d/i '>" .. s .. "</i>"
end


-- Strong is an inline element that translates to <b>
function Strong(s)
  return "<b class=' hi-d/b '>" .. s .. "</b>"
end


-- Subscript is an inline element that translates to <sub>
function Subscript(s)
  return "<sub class=' hi-d/sub '>" .. s .. "</sub>"
end


-- Superscript is an inline element that translates to <sup>
function Superscript(s)
  return "<sup class=' hi-d/sup '>" .. s .. "</sup>"
end


-- SmallCaps does not translate dirctly to a DITA element
-- Annotate an inline <ph> element with an outputclass attibute
function SmallCaps(s)
  return '<ph class="- topic/ph " outputclass="small-caps">' .. s .. '</ph>'
end


-- SmallCaps does not translate dirctly to a DITA element
-- Annotate an inline <ph> element with an outputclass attibute
function Strikeout(s)
  return '<ph class="- topic/ph   hi-d/line-through " outputclass="strikeout">' .. s .. '</ph>'
end


function SoftBreak()
  return "\n"
end

function DoubleQuoted(s)
  return "&quot;"  .. s .. "&quot;" 
end


-- Link is an inline element that translates to <xref>
-- We need to differenciate between internal and external links
function Link(s, src, tit)
   src = string.gsub(src, '_', '-')
   src =  string.lower(src)
  if string.starts(src,'#') then
    return '<xref class="- topic/xref " href="' .. escape(src,true) .. '" format="dita">' .. s .. '</xref>'
  else
    return '<xref class="- topic/xref " href="' .. string.lower(escape(src,true)) .. '" format="html" scope="external">' .. s .. '</xref>'
  end
end


-- Image is an inline element that translates to <image>
function Image(s, src, tit)
 
  if tit == nil then
    return '<image class=" topic/image " href="' .. escape(src,true) .. '"/>'
  else
    return '<image class=" topic/image " href="' .. escape(src,true) .. '">' ..
      '<alt class=" topic/alt ">' .. tit .. '</alt>' ..
      '</image>'
  end
end


-- Code is an inline element that translates to <codeph>
function Code(s, attr)
  return "<codeph class=' pr-d/codeph '" .. attributes(attr) .. ">" .. escape(s) .. "</codeph>"
end


function InlineMath(s)
  return "\\(" .. escape(s) .. "\\)"
end


function DisplayMath(s)
  return "\\[" .. escape(s) .. "\\]"
end


-- Pandoc Note translates to a DITA block level <note> element. This is usually a footnote,
-- but we can add an additional block element after the closure of the current paragraph.

-- Currently only simple single paragraph notes are supported.
function Note(s)
  
  if s ~= "" then
    -- This is a plain text list item
    note = '<note class=" topic/note " type="note">\n\t' .. s .. '\n</note>'
  else
    -- If the item is empty this is a paragraph within the <note>
    -- remove the <p> previously processed from the topic and add it to the list items
    note = '<note class=" topic/note " type="note">\n\t' .. getLastTopicElement() .. '</note>' 
    popElementFromCurrentTopic()
  end

  return ""
end


-- Span is an inline element that translates to <ph>
function Span(s, attr)
  return '<ph class="- topic/ph "' .. attributes(attr) .. ">" .. s .. "</ph>"
end


-- Cite is an inline element that translates to <cite>
function Cite(s, cs)
  return "<cite class=' topic/cite '>" .. s .. "</cite>"
end


function Plain(s)
  return s
end

function RawBlock(format, str)
  if format == "html" then
    if str == "<br/>" then
      return '<br/>'
    elseif str == "<br>" then
      return '<br/>'
    else
      return ''
    end
  else
      return ''
  end
end


function RawInline(format, str)
  if format == "html" then
    if str == "<br/>" then
      return '<br/>'
    elseif str == "<br>" then
      return '<br/>'
    else
      return ''
    end
  else
      return ''
  end
end

-- Para is an block level element that translates to <p>
function Para(s)
  pushElementToCurrentTopic('<p class="- topic/p " >\n\t' .. s .. "\n</p>")
  -- Place any <note> after the closed paragraph
  if note ~= nil then
     pushElementToCurrentTopic(note)
     note = nil
  end
  return "" 
end


-- Header is a special element that gives the document structure
-- and trasnlates to a <topic> with <title>, <body> and include sub elements

-- We need to remember the parentage of the <topic> so we can rebuild a structured
-- DITA  document later

-- lev is an integer, the header level.
function Header(lev, s, attr)
  for i = lev+1, #parent do
    parent[i]= #topics
  end

  level[lev][#level[lev]+1] =  {
    index = #topics,
    parent =  parent[lev]
  }

 -- Uncomment this line to see the structure of the document.
 -- print (#topics .. ' ' .. lev .. ' ' .. parent[lev] .. ' ' .. level[lev][#level[lev]].parent .. ' '.. s  )


  topics[#topics + 1 ] = {elem = {}, open = true}
  pushElementToCurrentTopic ('<topic xmlns:ditaarch="http://dita.oasis-open.org/architecture/2005/" xmlns:dita-ot="http://dita-ot.sourceforge.net/ns/201007/dita-ot" class="- topic/topic " ditaarch:DITAArchVersion="1.3" domains="(topic abbrev-d) a(props deliveryTarget) (topic equation-d) (topic hazard-d) (topic hi-d) (topic indexing-d) (topic markup-d) (topic mathml-d) (topic pr-d) (topic relmgmt-d) (topic sw-d) (topic svg-d) (topic ui-d) (topic ut-d) (topic markup-d xml-d)" ' ..  attributes(attr) .. 
   '>\n<title class="- topic/title " >' .. s .. '</title>\n<body class="- topic/body " >')

  return ""
end


-- Blockquote is an inline element that translates to <q>
function BlockQuote(s)
  return "<q class=' topic/q '>\n" .. s .. "\n</q>"
end


-- HorizontalRule does not translate directly to a DITA element
-- Add a carriage return
function HorizontalRule()
  return "\n"
end


-- LineBlock is an inline element that translates to <lines>
function LineBlock(ls)
  return '<lines class=" topic/lines ">' .. table.concat(ls, '\n') .. '</lines>'
end


-- Codeblock is an block level element that translates to <codeblock>
function CodeBlock(s, attr)

  

  pushElementToCurrentTopic ('<codeblock class=" pr-d/codeblock " '
      .. attributes(attr) .. '>' .. escape(s) .. '</codeblock>')
--    .. attributes(attr) .. '>' .. escape(s) .. '</codeblock>')
  return ""
end


-- BulletList is an block level element that translates to <ul> with <li> sub elements
function BulletList(items)
  local buffer = {}
  local reverse = false
  for _, item in pairs(items) do
    if item ~= "" then
      -- This is a plain text list item
      table.insert(buffer, '\t<li class=" topic/li ">' .. item .. "</li>\n")
    else
      -- If the item is empty this is a paragraph within the <li>
      -- remove the <p> previously processed from the topic and add it to the list items
       table.insert(buffer, '\t<li class=" topic/li ">' .. getLastTopicElement()  .. "</li>\n")
       popElementFromCurrentTopic()
      -- To maintainorder we'll need to reverse the order
      -- Hopefully all the items in the list can be processed the same way
       reverse = true
    end
  end

  -- If we've been picking from the end we'll need to reverse the order.
  if reverse == true then
    reverseArray(buffer)
  end


  pushElementToCurrentTopic ('<ul class=" topic/ul ">\n' .. table.concat(buffer, "") .. "</ul>")
  return ""
end


-- OrderedList is an block level element that translates to <ol> with <li> sub elements
function OrderedList(items)
  local buffer = {}
  local reverse = false
  for _, item in pairs(items) do
    if item ~= "" then
       -- This is a plain text list item
      table.insert(buffer, '\t<li class=" topic/li ">' .. item .. "</li>\n")
    else
       -- If the item is empty this is a paragraph within the <li>
       -- remove the <p> previously processed from the topic and add it to the list items
       table.insert(buffer, '\t<li class=" topic/li ">' .. getLastTopicElement() .. "</li>\n")
       popElementFromCurrentTopic()
       reverse = true
    end
  end

  if reverse == true then
    reverseArray(buffer)
  end

  pushElementToCurrentTopic('<ol class=" topic/ol ">\n' .. table.concat(buffer, "") .. "</ol>")
  return ""
end


-- DefinitionList is an block level element that translates to <dl> with <dlentry> sub elements
function DefinitionList(items)
  local buffer = {}
  for _,item in pairs(items) do
    for k, v in pairs(item) do
      table.insert(buffer,"\n\t<dlentry class=' topic/dlentry '>\n\t\t<dt class=' topic/dt '>" .. k .. "</dt>\n\t\t<dd ' topic/dd '>" ..
                        table.concat(v,"</dd>\n\t\t<dd class=' topic/dd '>") .. "</dd>\n\t</dlentry>")
    end
  end
  pushElementToCurrentTopic("<dl class=' topic/dl '>" .. table.concat(buffer, "\n") .. "\n</dl>")
  return ""
end


-- CaptionedImage is an block level element that translates to <fig> with <title> abd <image> sub elements
function CaptionedImage(src, tit, caption)
  pushElementToCurrentTopic('<fig class="- topic/fig ">\n\t<title class=" topic/title ">' .. caption .. '</title>\n' ..
      '\t<image class=" topic/image " href="' .. escape(src,true) .. '">\n' ..
      '\t\t<alt class="- topic/alt ">' .. tit .. '</alt>\n\t</image>\n</fig>')
  return ""
end


-- Table is an block level element that translates to <table> complex sub elements
-- Caption is a string, aligns is an array of strings,
-- widths is an array of floats, headers is an array of
-- strings, rows is an array of arrays of strings.
function Table(caption, aligns, widths, headers, rows)
  local buffer = {}
  local width_total = 0
  local max_cols = 0
  local function add(s)
    table.insert(buffer, s)
  end

  for _, row in pairs(rows) do
    max_cols = math.max(max_cols, #row)
  end

  add("<table class=' topic/table '>")
  if caption ~= "" then
    add("\t<title class=' topic/title '>" .. caption .. "</title>")
  end
  add('\t<tgroup class=" topic/tgroup " cols="' .. max_cols .. '">')
  if widths and widths[1] ~= 0 then
    
    for _, w in pairs(widths) do
      width_total = width_total + w
    end
    for _, w in pairs(widths) do
      add('\t\t<colspec class=" topic/colspec " colwidth="' .. string.format("%d%%", math.floor((w / width_total) * 100)) .. '"/>')
    end
  end
  local header_row = {}
  local empty_header = true
  for i, h in pairs(headers) do
    local align = dita_align(aligns[i])
    table.insert(header_row,'\t\t\t\t<entry class=" topic/entry " align="' .. align ..  '">' .. h .. '</entry>')
    empty_header = empty_header and h == ""
  end
  if empty_header then
    head = ""
  else
    add('\t\t<thead class=" topic/thead ">')
    add('\t\t\t<row class=" topic/row ">')
    for _,h in pairs(header_row) do
      add(h)
    end
    add('\t\t\t</row>')
    add('\t\t</thead>')
  end
  add('\t\t<tbody class=" topic/tbody ">')
  for _, row in pairs(rows) do
    add('\t\t\t<row class=" topic/row ">')
    for i,c in pairs(row) do
      local align = dita_align(aligns[i])
      add('\t\t\t\t<entry class=" topic/entry " align="' .. align ..  '">' .. c .. '</entry>')
    end
    add('\t\t\t</row>')
  end
  add('\t\t</tbody>')
  add('\t</tgroup>')
  add('</table>')

  local table_xml = table.concat(buffer,'\n')

  pushElementToCurrentTopic(table.concat(buffer,'\n'))
  return ""
end


function Div(s, attr)
  return "<div class='' topic/div '" .. attributes(attr) .. ">\n" .. s .. "</div>"
end


-- The following code will produce runtime warnings when you haven't defined
-- all of the functions you need for the custom writer, so it's useful
-- to include when you're working on a writer.
local meta = {}
meta.__index =
  function(_, key)
    io.stderr:write(string.format("WARNING: Undefined function '%s'\n",key))
    return function() return "" end
  end
setmetatable(_G, meta)
