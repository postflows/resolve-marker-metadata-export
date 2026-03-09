# Marker Metadata Workflow (Export & Review Import)

> Part of [PostFlows](https://github.com/postflows) toolkit for DaVinci Resolve

Export timeline and clip markers with clip metadata to CSV (with optional stills), then import reviewed statuses and comments back into markers. This script pair forms a full marker review workflow called **Marker Metadata Workflow** (formerly “Marker Metadata Export”).

## What it does

- **Marker Metadata Export** (`marker_metadata_export.lua`)
  - Collects timeline and clip markers from the current timeline.
  - Gathers clip metadata for clips under each marker.
  - Exports a CSV file with fixed marker fields (timecode, name, note, color, duration) and clip metadata columns.
  - Optionally captures stills from the Color page and saves them to a `stills/` folder.
  - Writes a `viewer.html` file next to the CSV for browser-based review (thumbnail grid + metadata).

- **Marker Review Import** (`marker_review_import.lua`)
  - Loads a reviewed CSV (exported by Marker Metadata Export + HTML viewer).
  - Matches rows to markers by `Marker Timecode`.
  - Appends client feedback to marker Note in the form:
    - `[existing Note]\n--- Client: [Status]\n[Comment]`
  - Changes marker color based on selected status→color mapping.
  - Can restrict import to a specific status (e.g. only `Approved`, only `Rejected`).

## Requirements

- DaVinci Resolve Studio 20+ (scripts with UI are supported only in Studio).
- Open project and active timeline.
- For still export: Color page available and project setting **Use labels on still export** enabled, with label set to **Timeline Timecode**.

## Installation

Copy the Lua files (and optional HTML viewer) to:

- **macOS:**  
  `~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/`

- **Windows:**  
  `%APPDATA%\Blackmagic Design\DaVinci Resolve\Fusion\Scripts\Utility\`

Suggested file layout:

```text
Utility/
  marker_metadata_export.lua
  marker_review_import.lua
  marker_metadata_viewer.html
```

In your Resolve Scripts workspace menu this will appear as:

- `Workspace → Scripts → Utility → marker_metadata_export`
- `Workspace → Scripts → Utility → marker_review_import`

## Usage

1. **Export**
   - Open the target timeline.
   - Run `marker_metadata_export` from the Scripts menu.
   - Choose export options (marker types, clip metadata, stills, output folder).
   - The script creates a folder:
     - `[ProjectName]_[TimelineName]_[YYYYMMDD_HHMMSS]/`
       - `markers_[YYYYMMDD_HHMMSS].csv`
       - `viewer.html`
       - optional `stills/` with timecode-labeled JPGs.

2. **Review**
   - Open `viewer.html` in a browser to inspect markers, thumbnails and metadata.
   - Share the CSV (and optionally HTML + stills) with the client or reviewer.
   - Reviewer fills in status and comment columns (for example `Status`, `Comment`).

3. **Import**
   - Back in Resolve, open the same timeline.
   - Run `marker_review_import` from the Scripts menu.
   - Select the reviewed CSV.
   - Choose which CSV columns correspond to **Status** and **Comment**.
   - Optionally restrict import to a specific status (e.g. only `Approved`).
   - Adjust status→color mapping so that each status maps to a Resolve marker color.
   - Click **Import into markers** to apply changes:
     - existing marker Notes receive an appended client section;
     - marker colors are updated according to mapping.

## Output

- **CSV:** one row per marker with marker fields and clip metadata.
- **HTML viewer:** `viewer.html` for browser-based review of markers.
- **Stills (optional):** JPEG thumbnails named by timeline timecode and marker index.
- **Updated markers:** marker Notes and colors updated based on reviewed CSV.

## License

MIT © PostFlows

# Marker Metadata Export

> Part of [PostFlows](https://github.com/postflows) toolkit for DaVinci Resolve

Collect markers from the active timeline, gather clip metadata from the Media Pool, and export everything to a structured CSV file. Optionally captures and exports gallery stills at each marker position, with automatic filename linking in the CSV. **Lua** script.

---

## Features

- **Two marker sources** — choose between Clip Markers or Timeline Markers
- **Marker color filter** — export only markers of a selected color (or all); live count in UI
- **Selective field export** — a tree view lets you check or uncheck individual fields across three groups: Marker Fields, Clip Info, and Clip Metadata
- **Smart field filtering** — only metadata fields that contain actual data in at least one clip on the timeline are shown in the field tree; fields that are empty across all clips are excluded automatically, keeping the tree and the resulting CSV clean
- **Optional stills export** — captures a gallery still at each marker position and exports it to a `stills/` subfolder; filenames are automatically matched back to CSV rows via timecode
- **Still columns in CSV** — when stills export is enabled, two columns are added: `Still Filename` (for portability) and `Still Path` (absolute path, for automation)
- **Isolated gallery album** — stills are captured into a new dedicated album (`Marker Export YYYYMMDD_HHMMSS`) so your existing grading albums are never touched
- **Structured output folder** — each export run creates a self-contained folder named `ProjectName_TimelineName_YYYYMMDD_HHMMSS/`, preventing collisions between runs
- **Accurate timecode conversion** — uses the native `libavutil` library bundled with DaVinci Resolve for correct SMPTE timecode calculation across all frame rates, including drop-frame
- **UTF-8 BOM** in CSV for correct display in Microsoft Excel
- **HTML viewer** — each export copies a standalone `viewer.html` into the export folder; open it in a browser to load the CSV, view stills, filter by color, add status/comment, and export a reviewed CSV

---

## Output Structure

```
[Selected folder]/
└── ProjectName_TimelineName_20250315_143022/
    ├── markers_20250315_143022.csv
    ├── viewer.html                   ← open in browser to review export
    └── stills/
        ├── 01.00.28.04_2.1.1.jpg
        ├── 01.00.28.04_2.1.1.drx      ← generated by Resolve, not referenced in CSV
        └── ...
```

---

## CSV Columns

| Column | Description |
|---|---|
| Marker Timecode | Absolute timeline timecode of the marker |
| Marker Name | Name text of the marker |
| Marker Note | Note/comment text of the marker |
| Marker Color | Color label of the marker |
| Marker Duration | Duration of the marker in frames |
| Clip Name | Name of the source clip under the marker |
| *(clip metadata)* | Any additional fields selected from Clip Metadata group |
| Still Filename | Filename of the exported still *(stills export only)* |
| Still Path | Absolute path to the exported still *(stills export only)* |

---

## Requirements

- **DaVinci Resolve Studio** — this script uses a graphical interface (Fusion UIManager). Scripts with UI run only in DaVinci Resolve Studio; the free version does not support UI-based scripting.
- DaVinci Resolve 20 (tested on 20.x only; earlier versions not verified)
- Open project and timeline

---

## Installation

Copy **both files** to the same folder in the Resolve scripts tree (so the script can find the viewer template):

- `marker_metadata_export.lua` — main script
- `marker_metadata_viewer.html` — HTML viewer template (copied as `viewer.html` into each export folder)

**macOS**
```
~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Fusion/Scripts/Utility/
```
(or a subfolder, e.g. `Utility/PostFlows/resolve-marker-metadata-workflow/`)

**Windows**
```
%APPDATA%\Blackmagic Design\DaVinci Resolve\Fusion\Scripts\Utility\
```

Then launch from DaVinci Resolve via **Workspace → Scripts → Utility → … → marker_metadata_export**.

---

## HTML Viewer

Each export run copies `viewer.html` into the export folder. To review the export:

1. Open the export folder (`ProjectName_TimelineName_YYYYMMDD_HHMMSS/`).
2. Open `viewer.html` in a modern browser.
3. Drag & drop the CSV file onto the viewer, or click **Choose CSV file**.
4. The viewer loads the table and loads stills from the `stills/` subfolder automatically.

**Viewer features:** search across all fields; filter by marker color (pills matching Resolve colors); filter by review status; toggle visible columns; table and storyboard views; click a still thumbnail for full size; set per-marker **Status** (Approved / Revision / Rejected) with row highlighting; add per-marker **Comments**; status and comments auto-saved in the browser (localStorage); **Export CSV** downloads a reviewed CSV with Status and Comment columns for round-trip to the editor.

---

## Usage

Run script from **Workspace → Scripts → Utility → marker_metadata_export**. Select marker source (Clip Markers or Timeline Markers) and check the fields to include in the CSV. Optionally enable stills export and choose the image format. Set the output folder and click **Export**.

---

## Required Project Settings (for Stills Export)

Stills export and CSV linking rely on timecode-based filenames. The following settings **must** be configured before using the stills export option.

### Project Settings → General Options → Color

| Setting | Value |
|---|---|
| Automatically label gallery stills using | **Timeline Timecode** |
| Append still number on export | **As Suffix** |

### Color Page → Stills Export Options

| Setting | Value |
|---|---|
| Use labels on still export | **✓ Enabled** |

> ⚠️ If these settings are not configured, Resolve will export stills with default numeric names only (e.g. `2.1.1.jpg`), and the script will not be able to match them to the correct CSV rows. The `Still Filename` and `Still Path` columns will be empty.

---

## Known Limitations

- **Marker keywords are not available via the Resolve scripting API.** The `keywords` field visible in the Resolve marker UI is not exposed through `GetMarkers()` and cannot be exported. This is a current limitation of the Resolve API.
- **Stills export requires the Color page** to be accessible. If Resolve cannot switch to the Color page (e.g. no clip is present on the timeline), stills capture will fail. The CSV will still be saved without stills columns.
- **Clip Markers on Generator clips** (solid color, adjustment clips, etc.) do not have a Media Pool item, so clip metadata fields will be empty for those rows. The marker data itself is exported correctly.
- The script will not function correctly if an automated project backup starts during stills capture, or if a modal dialog (e.g. Project Settings) is opened while the script is running. This is a known DaVinci Resolve scripting limitation with no current workaround.

---

## Compatibility

- **DaVinci Resolve Studio only** — the free version (DaVinci Resolve) does not support scripts with a graphical interface.
- DaVinci Resolve Studio 20 (tested on 20.x only; earlier versions not verified)
- macOS and Windows
- Linux: untested, but should work if `libavutil.so` is present

---

## Credits

Developed by **[PostFlows](https://github.com/postflows)**

Timecode conversion logic based on the approach by **Roger Magnusson** ([Grab Stills at Markers](https://github.com/rogermagnusson)), used under MIT License.

---

## License

MIT © PostFlows
