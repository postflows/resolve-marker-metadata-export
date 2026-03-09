-- ================================================
-- Marker Review Import
-- Part of PostFlows toolkit for DaVinci Resolve
-- https://github.com/postflows
-- ================================================

--[[
    marker_review_import.lua
    DaVinci Resolve Script — import reviewed CSV back into timeline markers.

    What it does:
      - Loads CSV with Status and Comment fields (export from marker_metadata_export + HTML viewer)
      - Matches rows to markers by Marker Timecode
      - Appends client feedback to existing marker Note:
            [existing Note]\n--- Client: [Status]\n[Comment]
      - Changes marker color depending on status (configurable in UI)
      - Status filter: import only Approved, only Rejected, etc.

    Installation:
      macOS:   ~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/
      Windows: %APPDATA%\\Blackmagic Design\\DaVinci Resolve\\Fusion\\Scripts\\Utility\\

    Run from:
      Workspace → Scripts → Utility → marker_review_import
--]]

-- Resolve init

resolve = Resolve()
local projectManager = resolve:GetProjectManager()
local project        = projectManager:GetCurrentProject()
if not project then print("[Error] No project open"); return end

local timeline = project:GetCurrentTimeline()
if not timeline then print("[Error] No timeline open"); return end

-- UI styles

local PRIMARY_COLOR  = "#4C956C"
local HOVER_COLOR    = "#61B15A"
local TEXT_COLOR     = "#ebebeb"
local BORDER_COLOR   = "#3a6ea5"
local SECTION_BG     = "#2A2A2A"
local WARN_COLOR     = "#c0804a"
local OK_COLOR       = "#4C956C"

local PRIMARY_BUTTON = string.format([[
    QPushButton { border: 2px solid %s; border-radius: 8px; background-color: %s; color: #FFF;
        min-height: 35px; font-size: 15px; font-weight: bold; padding: 5px 15px; }
    QPushButton:hover { background-color: %s; border-color: %s; }
    QPushButton:disabled { background-color: #666; border-color: #555; color: #999; }
]], BORDER_COLOR, PRIMARY_COLOR, HOVER_COLOR, PRIMARY_COLOR)

local SECONDARY_BUTTON = string.format([[
    QPushButton { border: 1px solid %s; border-radius: 5px; background-color: %s; color: %s;
        min-height: 28px; font-size: 12px; padding: 3px 10px; }
    QPushButton:hover { background-color: #3A3A3A; }
    QPushButton:disabled { background-color: #555; color: #888; }
]], BORDER_COLOR, SECTION_BG, TEXT_COLOR)

local SECTION = string.format(
    [[ QLabel { color: %s; font-size: 13px; font-weight: bold; padding: 4px 0; } ]], TEXT_COLOR)

local STATUS_OK   = string.format([[ QLabel { color: %s; font-size: 11px; padding: 2px 0; } ]], OK_COLOR)
local STATUS_WARN = string.format([[ QLabel { color: %s; font-size: 11px; padding: 2px 0; } ]], WARN_COLOR)
local STATUS_IDLE = [[ QLabel { color: #a0a0a0; font-size: 11px; padding: 2px 0; } ]]
local CNT_APPROVED = [[ QLabel { color: #3acc66; font-size: 11px; font-family: monospace; } ]]
local CNT_REVISION = [[ QLabel { color: #e8c040; font-size: 11px; font-family: monospace; } ]]
local CNT_REJECTED = [[ QLabel { color: #d95555; font-size: 11px; font-family: monospace; } ]]

local COMBO = string.format([[
    QComboBox { border: 1px solid %s; border-radius: 4px; padding: 4px 8px;
        background-color: %s; color: %s; min-height: 24px; }
    QComboBox QAbstractItemView { background-color: #1e1e1e; color: %s;
        selection-background-color: #2a3545; }
]], BORDER_COLOR, SECTION_BG, TEXT_COLOR, TEXT_COLOR)

local LINEEDIT_STYLE = string.format([[
    QLineEdit { border: 1px solid %s; border-radius: 4px; padding: 4px 8px;
        background-color: #1e1e1e; color: %s; font-size: 12px; min-height: 24px; }
]], BORDER_COLOR, TEXT_COLOR)

local TREE_STYLE = string.format([[
    QTreeWidget { background-color: #1e1e1e; alternate-background-color: #1a1a1a;
        border: 1px solid %s; border-radius: 4px; color: #ebebeb; font-size: 12px; outline: 0; }
    QTreeWidget::item            { height: 26px; padding: 0 4px; }
    QTreeWidget::item:hover      { background: #2a3545; }
    QTreeWidget::item:selected   { background: #2a3545; color: #ebebeb; }
    QHeaderView::section { background: #2A2A2A; color: #aaa; font-size: 10px; font-weight: bold;
        padding: 4px 6px; border: none; border-bottom: 1px solid %s; }
]], BORDER_COLOR, BORDER_COLOR)

-- Resolve marker colors

local MARKER_COLORS = {
    "Blue", "Cyan", "Green", "Yellow", "Red", "Pink",
    "Purple", "Fuchsia", "Rose", "Lavender", "Sky", "Mint",
    "Lemon", "Sand", "Cocoa", "Cream",
}

-- Default mapping status → color
local DEFAULT_COLOR = {
    Approved = "Green",
    Revision = "Yellow",
    Rejected = "Red",
}

-- CSV parser

local function parse_csv(text)
    -- Strip BOM
    if text:sub(1, 3) == "\xEF\xBB\xBF" then text = text:sub(4) end
    -- Normalize line endings
    text = text:gsub("\r\n", "\n"):gsub("\r", "\n")

    local rows = {}
    local row, col, inq = {}, "", false

    for i = 1, #text + 1 do
        local ch = i <= #text and text:sub(i, i) or "\n"
        if ch == '"' then
            if inq and text:sub(i + 1, i + 1) == '"' then
                col = col .. '"'
                -- skip next char handled by loop
                i = i + 1
            else
                inq = not inq
            end
        elseif ch == "," and not inq then
            table.insert(row, col); col = ""
        elseif ch == "\n" and not inq then
            table.insert(row, col); col = ""
            local has_data = false
            for _, v in ipairs(row) do
                if v:match("%S") then has_data = true; break end
            end
            if has_data then table.insert(rows, row) end
            row = {}
        else
            col = col .. ch
        end
    end

    if #rows < 2 then return nil, "CSV has no data rows" end

    local headers = rows[1]
    -- Trim header names
    for i, h in ipairs(headers) do headers[i] = h:match("^%s*(.-)%s*$") end

    local data = {}
    for ri = 2, #rows do
        local cells = rows[ri]
        local obj = {}
        for i, h in ipairs(headers) do
            obj[h] = (cells[i] or ""):match("^%s*(.-)%s*$")
        end
        table.insert(data, obj)
    end

    return headers, data
end

-- Utilities

local function get_desktop_path()
    local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""
    return (home ~= "") and (home .. "/Desktop") or "."
end

-- Build marker index for timeline markers: timecode → { frame_id, marker, type }
-- type = "timeline" or "clip" + item ref
local function build_marker_index()
    local index = {}

    local fps_str   = timeline:GetSetting("timelineFrameRate")
    local drop      = timeline:GetSetting("timelineDropFrameTimecode")
    local start_f   = tonumber(timeline:GetStartFrame()) or 0

    -- Helper: frame → timecode string (manual fallback calculation)
    local fps_num = tonumber(fps_str) or 24
    local function frames_to_tc(abs_frame)
        local f = math.floor(abs_frame)
        local fps = math.floor(fps_num + 0.5)
        local fr  = f % fps
        local s   = math.floor(f / fps) % 60
        local m   = math.floor(f / fps / 60) % 60
        local h   = math.floor(f / fps / 3600)
        return string.format("%02d:%02d:%02d:%02d", h, m, s, fr)
    end

    -- Timeline markers
    local tl_markers = timeline:GetMarkers() or {}
    for frame_id, marker in pairs(tl_markers) do
        local abs_frame = start_f + tonumber(frame_id)
        local tc = frames_to_tc(abs_frame)
        index[tc] = { frame_id = tonumber(frame_id), marker = marker,
                      marker_type = "timeline", item = nil }
    end

    -- Clip markers
    local tc_count = timeline:GetTrackCount("video")
    for tr = 1, tc_count do
        local items = timeline:GetItemListInTrack("video", tr)
        if items then
            for _, item in ipairs(items) do
                local cm = item:GetMarkers()
                if cm then
                    for frame_id, marker in pairs(cm) do
                        local abs_frame = item:GetStart() + tonumber(frame_id)
                        local tc = frames_to_tc(abs_frame)
                        index[tc] = {
                            frame_id   = tonumber(frame_id),
                            marker     = marker,
                            marker_type = "clip",
                            item       = item
                        }
                    end
                end
            end
        end
    end

    return index
end

-- Build note text with client status/comment appended
local function build_note(existing, status, comment)
    existing = existing or ""
    status   = status or ""
    comment  = comment or ""
    if status == "" and comment == "" then
        return existing
    end
    local suffix = ""
    if status ~= "" then
        suffix = suffix .. "--- Client: " .. status
    end
    if comment ~= "" then
        suffix = suffix .. "\\n" .. comment
    end
    if existing ~= "" then
        return existing .. "\\n" .. suffix
    else
        return suffix
    end
end

-- Apply import to marker object (both timeline and clip markers)
local function apply_to_marker(entry, row, status_field, comment_field, color_map)
    local marker  = entry.marker or {}
    local status  = row[status_field]  or ""
    local comment = row[comment_field] or ""

    marker.note = build_note(marker.note, status, comment)

    if color_map and status ~= "" then
        local col = color_map[status]
        if col and col ~= "" then
            marker.color = col
        end
    end

    return marker
end

-- UI + main logic

local ui  = fusion.UIManager
local disp = bmd.UIDispatcher(ui)

local csv_path = ""
local marker_index = nil

local status_label = ui:Label({ ID = "StatusLabel", Text = "Waiting for CSV...", StyleSheet = STATUS_IDLE })
local counts_label = ui:Label({ ID = "CountsLabel", Text = "", StyleSheet = CNT_APPROVED })

local win = disp:AddWindow({
    ID          = "MarkerReviewImportWindow",
    WindowTitle = "Marker Metadata Review Import",
    Geometry    = { 200, 200, 700, 520 },
    ui:VGroup({
        ID = "root",
        ui:VGroup({
            ID = "Top",
            Weight = 0,
            ui:Label({ Text = "Import reviewed statuses and comments back into markers", StyleSheet = SECTION }),
            status_label,
            counts_label,
        }),
        ui:VGroup({
            ID = "Body",
            Weight = 1,
            ui:HGroup({
                Weight = 0,
                ui:Label({ ID = "CsvLabel", Text = "CSV file:", MinimumSize = { 70, 0 } }),
                ui:LineEdit({
                    ID = "CsvPath",
                    Text = "",
                    PlaceholderText = "Select CSV exported from Marker Metadata Export viewer...",
                    StyleSheet = LINEEDIT_STYLE,
                    ReadOnly = true,
                }),
                ui:Button({
                    ID = "BrowseCsv",
                    Text = "Browse…",
                    StyleSheet = SECONDARY_BUTTON,
                    MinimumSize = { 80, 0 },
                }),
            }),
            ui:HGroup({
                Weight = 0,
                ui:Label({ Text = "Status field:", MinimumSize = { 70, 0 } }),
                ui:ComboBox({
                    ID = "StatusField",
                    StyleSheet = COMBO,
                    MinimumSize = { 160, 0 },
                }),
                ui:Label({ Text = "Comment field:", MinimumSize = { 90, 0 } }),
                ui:ComboBox({
                    ID = "CommentField",
                    StyleSheet = COMBO,
                    MinimumSize = { 180, 0 },
                }),
            }),
            ui:HGroup({
                Weight = 0,
                ui:Label({ Text = "Import only status:", MinimumSize = { 120, 0 } }),
                ui:ComboBox({
                    ID = "StatusFilter",
                    StyleSheet = COMBO,
                    MinimumSize = { 180, 0 },
                }),
            }),
            ui:VGroup({
                Weight = 1,
                ui:Label({ Text = "Status → Marker Color mapping", StyleSheet = SECTION }),
                ui:Tree({
                    ID = "StatusTree",
                    HeaderHidden = false,
                    AlternatingRowColors = true,
                    SelectionMode = "SingleSelection",
                    StyleSheet = TREE_STYLE,
                    ColumnCount = 2,
                    ColumnNames = { "Status", "Color" },
                    SortingEnabled = false,
                }),
            }),
        }),
        ui:HGroup({
            ID = "Buttons",
            Weight = 0,
            ui:HGap(0),
            ui:Button({
                ID = "ImportBtn",
                Text = "Import into markers",
                StyleSheet = PRIMARY_BUTTON,
                MinimumSize = { 220, 0 },
                Enabled = false,
            }),
            ui:Button({
                ID = "CloseBtn",
                Text = "Close",
                StyleSheet = SECONDARY_BUTTON,
                MinimumSize = { 80, 0 },
            }),
        }),
    }),
})

local itm = win:GetItems()

local function set_status(text, style)
    itm.StatusLabel.Text = text
    if style == "ok" then
        itm.StatusLabel.StyleSheet = STATUS_OK
    elseif style == "warn" then
        itm.StatusLabel.StyleSheet = STATUS_WARN
    else
        itm.StatusLabel.StyleSheet = STATUS_IDLE
    end
end

local function update_counts(total, matched, applied)
    itm.CountsLabel.Text = string.format(
        "Rows: %d   Matched markers: %d   Applied: %d",
        total or 0, matched or 0, applied or 0)
end

local function rebuild_status_tree(headers, rows)
    itm.StatusTree:Clear()

    local statuses = {}
    for _, row in ipairs(rows or {}) do
        local st = (row.Status or row.status or ""):match("^%s*(.-)%s*$")
        if st ~= "" then statuses[st] = true end
    end

    local ordered = {}
    for st in pairs(statuses) do table.insert(ordered, st) end
    table.sort(ordered)

    for _, st in ipairs(ordered) do
        local color = DEFAULT_COLOR[st] or "Yellow"
        local item = itm.StatusTree:NewItem()
        item.Text[0] = st
        item.Text[1] = color
        itm.StatusTree:AddTopLevelItem(item)
    end
end

local function build_color_map()
    local map = {}
    local count = itm.StatusTree:TopLevelItemCount()
    for i = 0, count - 1 do
        local item = itm.StatusTree:TopLevelItem(i)
        local status = item.Text[0]
        local color  = item.Text[1]
        if status ~= "" and color ~= "" then
            map[status] = color
        end
    end
    return map
end

local function load_csv(path)
    local fh = io.open(path, "rb")
    if not fh then
        set_status("Cannot open CSV file", "warn")
        return
    end
    local content = fh:read("*a")
    fh:close()

    local headers, rows = parse_csv(content)
    if not headers then
        set_status("Failed to parse CSV", "warn")
        return
    end

    itm.StatusField:Clear()
    itm.CommentField:Clear()
    for _, h in ipairs(headers) do
        itm.StatusField:AddItem(h)
        itm.CommentField:AddItem(h)
    end

    itm.StatusFilter:Clear()
    itm.StatusFilter:AddItem("All statuses")
    itm.StatusFilter:AddItem("Approved")
    itm.StatusFilter:AddItem("Revision")
    itm.StatusFilter:AddItem("Rejected")

    rebuild_status_tree(headers, rows)

    marker_index = build_marker_index()
    set_status("CSV loaded. Ready to import.", "ok")
    itm.ImportBtn.Enabled = true

    win.CsvHeaders = headers
    win.CsvRows    = rows
end

function win.On.MarkerReviewImportWindow.Close(ev)
    disp:ExitLoop()
end

function win.On.CloseBtn.Clicked(ev)
    disp:ExitLoop()
end

function win.On.BrowseCsv.Clicked(ev)
    local start_dir = get_desktop_path()
    local path = fu.RequestFile("Select reviewed CSV file", "*.csv", false, start_dir)
    if not path or path == "" then return end
    itm.CsvPath.Text = path
    load_csv(path)
end

function win.On.ImportBtn.Clicked(ev)
    local headers = win.CsvHeaders
    local rows    = win.CsvRows
    if not headers or not rows then
        set_status("CSV is not loaded", "warn")
        return
    end

    local status_field  = itm.StatusField.CurrentText or "Status"
    local comment_field = itm.CommentField.CurrentText or "Comment"
    local status_filter = itm.StatusFilter.CurrentText or "All statuses"

    local color_map = build_color_map()

    local total, matched, applied = 0, 0, 0

    timeline:StartUndo("Marker Review Import")

    for _, row in ipairs(rows) do
        total = total + 1
        local status = row[status_field] or ""
        if status_filter ~= "All statuses" and status ~= status_filter then
            goto continue
        end

        local tc = (row["Marker Timecode"] or row["MarkerTimecode"] or ""):match("^%s*(.-)%s*$")
        if tc == "" then goto continue end

        local entry = marker_index[tc]
        if not entry then goto continue end

        matched = matched + 1
        local new_marker = apply_to_marker(entry, row, status_field, comment_field, color_map)

        if entry.marker_type == "timeline" then
            timeline:AddMarker(entry.frame_id,
                new_marker.color or "",
                new_marker.name or "",
                new_marker.note or "",
                new_marker.duration or 1,
                new_marker.customData or "")
        elseif entry.marker_type == "clip" and entry.item then
            entry.item:AddMarker(entry.frame_id,
                new_marker.color or "",
                new_marker.name or "",
                new_marker.note or "",
                new_marker.duration or 1,
                new_marker.customData or "")
        end

        applied = applied + 1

        ::continue::
    end

    timeline:EndUndo()

    update_counts(total, matched, applied)
    set_status("Import finished.", "ok")
end

win:Show()
disp:RunLoop()
win:Hide()

