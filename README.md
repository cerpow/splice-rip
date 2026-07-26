# Splice Rip

Patch for the [Splice Desktop](https://splice.com/download) app that adds local download and pack-search buttons.

## Requirements

- macOS (Windows is experimental)
- [Node.js](https://nodejs.org/)
- Splice Desktop installed

## Install

```bash
bash splice-patch.sh /Applications/Splice.app
```

Or drag `splice-patch.sh` into Terminal, press Space, drag `Splice.app`, then press Enter.

The script closes Splice if it’s open, applies the patch, and reopens it. A backup of the original app files is kept as `app.asar.bak`.

## Use

After patching, open Splice. Extra buttons appear at the bottom right:

| Button | What it does |
| --- | --- |
| **WAV** | Saves the selected sample as a WAV file |
| **Pages / Get Pack / Get Collection** | Downloads samples from the current list (optionally across pages) |
| **Search** | Opens a pack search on Rutracker, Audioz, or Audionews |

Tips:

- Select a sample first for **WAV** and for pack search from search results.
- On a pack page, search uses that pack’s author and name.
- Don’t click around in Splice while a bulk download is running.
- Use **Cancel** to stop a bulk download.

## Notes

- Bulk download works from what’s loaded in the list; missing pages are skipped automatically.
- Re-run the patcher after Splice updates.
- Use at your own risk. Support artists by using Splice legitimately when you can.
