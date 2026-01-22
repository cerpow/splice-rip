# Splice.com App - Sound Extractor (macOS & Windows)

A simple script to unlock the "Download" button in Splice Desktop, allowing you to save sounds locally.

## 🚀 How to use

### 1. Installation

1. **Install Node.js**: Ensure you have Node.js installed on your Mac (`node -v`).
2. **Download Splice**: Ensure the latest [Splice Desktop App](https://splice.com/download) is installed.
3. **Run the Patcher**:
   - **macOS**:
     ```bash
     bash splice-patch.sh /Applications/Splice.app
     ```
   - **Windows (not tested)**: Use Git Bash (or similar) and point to your versioned app folder:
     ```bash
     bash splice-patch.sh "/c/Users/YOUR_NAME/AppData/Local/Splice/app-x.x.x"
     ```
   - **Manual/Drag & Drop**: Type `bash `, drag `splice-patch.sh`, press Space, drag your **Splice.app** (Mac) or the **app-x.x.x** folder (Windows - not tested), then press Enter.

### 2. Usage

1. **Open Splice App**.
2. **Play a Sample**: Click on any loop or sample to start playback.
3. **Download**: A blue **"Download"** button will appear on the bottom right. Click it to save the sample.
4. **Bulk Download**: If you are on a Pack or Collection page, a **"Get Pack"** or **"Get Collection"** button will be available to automate capturing all samples on the current page.

## 🛠 Technical Details

- **Backup**: Automatically renames `app.asar` to `app.asar.bak`.
- **Injection**: Patches the app to capture audio streams and add UI controls.
- **DevTools**: Adds a hidden button to toggle Electron DevTools for debugging.

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
