# Mac Splice App Loop Extractor Script

A simple script to unlock the "Download" button in Splice Desktop, allowing you to save sounds locally.

## 🚀 How to use

1. **Install Node.js**: Ensure you have Node.js installed on your Mac. Check with `node -v`.
2. **Download Splice**: Make sure you have the latest [Splice Desktop App](https://splice.com/download) installed.
3. **Open Terminal** in the folder containing `splice-patch.sh`.
4. **Run the script**:
   - **Option A (Command Line)**:
     ```bash
     bash splice-patch.sh /Applications/Splice.app
     ```
   - **Option B (Drag & Drop)**:
     1. Open Terminal.
     2. Type `bash ` (with a space).
     3. Drag and drop `splice-patch.sh` into the window.
     4. Press Space again.
     5. Drag and drop your **Splice.app** (usually in Applications) into the window.
     6. Press **Enter**.

## 🛠 What it does

- **Backs up**: Renames your original `app.asar` to `app.asar.bak`.
- **Unpacks**: Uses the `asar` utility to extract Splice's source code.
- **Injects**: Adds a custom script to the app that:
  - Captures audio data when you play a sound.
  - Adds "Download" and "Get Pack" buttons to the UI.
  - Enables a "Console" button to toggle DevTools.

## 📝 Patch Description & Limitations

- **Audio Quality**: This patch captures audio data from the app's player stream. It results in **.mp3** files at **128kbps** quality.
- **"Get Pack" Button**:
  - This feature automates the playback of sounds on the **current page** to capture them.
  - It only captures samples visible in the current list. If a pack has multiple pages, you must go to each page and run it again.
  - Do not interact with the app while "Get Pack" is running to avoid interruptions.

## ⚖️ Legal & Disclaimer

**Use this tool at your own risk.**

- **No Responsibility**: The author of this script is NOT responsible for any consequences resulting from the use of this software, including but not limited to account suspension, data loss, or legal actions.
- **Copyright Compliance**: This tool is for educational purposes only. You are solely responsible for ensuring that your use of this software complies with Splice's terms of service and all applicable copyright laws.
- **Support Creators**: Please support artists and sound designers by purchasing credits and subscribing to Splice. This tool should not be used to bypass the need to support the creative community.
- **No Warranty**: This software is provided "as is", without warranty of any kind.

_Keywords: hack, crack, torrent alternative, downloader, local extraction bypass._
