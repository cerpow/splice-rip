#!/bin/bash

# Splice.com App - Sound Extractor (macOS)
# This script injects the Audio Spy download functionality into Splice Desktop.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}--- Splice.com App - Sound Extractor (macOS) ---${NC}"

# Check for path argument
if [ -z "$1" ]; then
    echo -e "${YELLOW}Usage: drag Splice.app here and press Enter${NC}"
    read -p "Path to Splice.app: " SPLICE_PATH
else
    SPLICE_PATH="$1"
fi

# Clean up path (remove trailing slashes, handle spaces)
SPLICE_PATH="${SPLICE_PATH%/}"
# If it's a directory, check for the actual app structure
if [[ "$SPLICE_PATH" != *.app ]]; then
    echo -e "${RED}Error: Please provide a path to Splice.app${NC}"
    exit 1
fi

RESOURCES_PATH="$SPLICE_PATH/Contents/Resources"
ASAR_FILE="$RESOURCES_PATH/app.asar"
UNPACKED_PATH="$RESOURCES_PATH/app"

if [ ! -f "$ASAR_FILE" ] && [ ! -d "$UNPACKED_PATH" ]; then
    echo -e "${RED}Error: app.asar not found in $RESOURCES_PATH${NC}"
    exit 1
fi

# Check for node/npm
if ! command -v npx &> /dev/null; then
    echo -e "${RED}Error: npx not found. Please install Node.js.${NC}"
    exit 1
fi

echo -e "${CYAN}Unpacking Splice app...${NC}"

# Backup original asar if it exists
if [ -f "$ASAR_FILE" ]; then
    cp "$ASAR_FILE" "$RESOURCES_PATH/app.asar.bak"
    echo -e "${GREEN}✓ Backed up original app.asar to app.asar.bak${NC}"
fi

# Unpack asar
if [ -f "$ASAR_FILE" ]; then
    npx -y asar extract "$ASAR_FILE" "$UNPACKED_PATH"
    echo -e "${GREEN}✓ Unpacked app.asar${NC}"
    # Move original asar aside so Splice uses the unpacked folder
    mv "$ASAR_FILE" "$RESOURCES_PATH/app.asar.inactive"
fi

# 1. Inject into index.js (Main Process)
INDEX_JS="$UNPACKED_PATH/index.js"
if [ -f "$INDEX_JS" ]; then
    echo -e "${CYAN}Injecting IPC handlers into index.js...${NC}"
    
    # Check if already injected
    if grep -q "antigravity-save-file" "$INDEX_JS"; then
        echo -e "${YELLOW}! IPC handlers already exist in index.js, skipping.${NC}"
    else
        # Prepend the IPC logic at the top of the file
        cat << 'EOF' > index.js.tmp
'use strict';
try {
	const { app, ipcMain, shell } = require('electron');
	const fs = require('fs');
	const path = require('path');
	const os = require('os');
	app.on('web-contents-created', (e, c) => {
		c.on('devtools-opened', () => c.send('antigravity-devtools-state', true));
		c.on('devtools-closed', () => c.send('antigravity-devtools-state', false));
	});
	ipcMain.on('antigravity-toggle-devtools', (e) => {
		const wc = e.sender;
		if (wc.isDevToolsOpened()) {
			wc.closeDevTools();
		} else {
			wc.openDevTools({ mode: 'detach' });
		}
	});
	ipcMain.handle('antigravity-save-file', async (e, filename, buffer) => {
		try {
			const filePath = path.join(app.getPath('downloads'), filename);
			fs.writeFileSync(filePath, Buffer.from(buffer));
			shell.showItemInFolder(filePath);
			return { success: true, path: filePath };
		} catch (err) {
			return { success: false, error: err.message };
		}
	});
} catch (e) {}
EOF
        # Remove 'use strict'; from the start of the original file if it exists to avoid duplication
        sed -i '' "s/'use strict';//" "$INDEX_JS" || sed -i "s/'use strict';//" "$INDEX_JS"
        cat "$INDEX_JS" >> index.js.tmp
        mv index.js.tmp "$INDEX_JS"
        echo -e "${GREEN}✓ index.js patched${NC}"
    fi
fi

# 2. Inject into index.html (Renderer Process)
INDEX_HTML="$UNPACKED_PATH/desktop-main/index.html"
if [ -f "$INDEX_HTML" ]; then
    echo -e "${CYAN}Injecting Audio Spy into index.html...${NC}"
    
    # Check if already injected
    if grep -q "Audio Spy Injected" "$INDEX_HTML"; then
        echo -e "${YELLOW}! Audio Spy already injected in index.html, skipping.${NC}"
    else
        # We'll insert our script right after <head>
        # Prepare the script content
        cat << 'EOF' > script.tmp
	<head>
		<script>
			console.log('%c[Spy] Audio Spy Injected v7 (Direct Download & State)', 'color: cyan; font-size: 20px; font-weight: bold;');

			const ICON_DOWNLOAD = `<svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor"><use xlink:href="#icon-download"></use></svg>`;
			const CSS_STYLES = `
    @keyframes spy-spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }
    .spy-spinner {
        border: 2px solid rgba(255,255,255,0.3);
        border-radius: 50%;
        border-top: 2px solid #fff;
        width: 14px;
        height: 14px;
        animation: spy-spin 1s linear infinite;
        min-width: 14px;
    }
    
    #splice-spy-btn {
        transition: transform 0.3s cubic-bezier(0.34, 1.56, 0.64, 1), opacity 0.2s ease, width 0.3s ease, background-color 0.2s;
        transform: scale(0.7); 
        opacity: 0;
        pointer-events: none;
        overflow: hidden;
        white-space: nowrap;
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 4px;
        box-shadow: 0 4px 12px rgba(0,0,0,0.3);
        background-color: #1253ff;
        color: #fff;
        border: none;
        font-weight: 500;
        font-size: 14px;
        cursor: pointer;
        height: 32px;
        padding: 0 13px 0px 8px;
        border-radius: 5px;
    }
    
    #splice-spy-btn span { opacity: 1; transition: opacity 0.2s; }
    #splice-spy-btn:hover span { opacity: 0.6; }
    #splice-spy-btn svg { opacity: 0.7; transition: opacity 0.2s; }
    #splice-spy-btn:hover svg { opacity: 0.4; }
    
    #splice-spy-btn.visible {
        transform: scale(1);
        opacity: 1;
        pointer-events: auto;
        display: flex;
    }
    #splice-spy-btn.visible.loading { width: 32px; padding: 0; opacity: 0.9; }
    #splice-spy-btn.ready { width: auto; }
    
    #splice-spy-btn .spy-spinner { display: none; margin: 0; }
    #splice-spy-btn.loading .spy-spinner { display: block; }
    #splice-spy-btn.loading svg, #splice-spy-btn.loading span { display: none; }

    .spy-d-none { display: none !important; }
    #splice-spy-btn.hidden-by-pack {
        width: 0 !important;
        padding: 0 !important;
        opacity: 0 !important;
        margin: 0 !important;
        pointer-events: none;
    }

    .splice-get-pack-btn-wrapper { display: flex; pointer-events: none; }
    #splice-get-pack-btn {
        transition: transform 0.3s cubic-bezier(0.34, 1.56, 0.64, 1), opacity 0.2s ease, width 0.3s ease, background-color 0.2s;
        transform: scale(0.7);
        opacity: 0;
        pointer-events: none;
        overflow: hidden;
        white-space: nowrap;
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 4px;
        box-shadow: 0 4px 12px rgba(0,0,0,0.3);
        background-color: color(display-p3 0.77 0.04 0.68);
        color: #fff;
        border: none;
        font-weight: 500;
        font-size: 14px;
        cursor: pointer;
        height: 32px;
        padding: 0 13px 0 8px;
        border-radius: 5px;
    }
    #splice-get-pack-btn span { opacity: 1; transition: opacity 0.2s; }
    #splice-get-pack-btn:hover span { opacity: 0.6; }
    #splice-get-pack-btn.visible { transform: scale(1); opacity: 1; pointer-events: auto; }
    #splice-get-pack-btn.visible.loading { width: auto; padding: 0 13px 0 8px; opacity: 0.9; }
`;

			const styleEl = document.createElement('style');
			styleEl.textContent = CSS_STYLES;
			document.head.appendChild(styleEl);

			const SpyState = { HIDDEN: 'hidden', LOADING: 'loading', READY: 'ready' };
			window.spyData = { state: SpyState.HIDDEN, buffer: null, ext: null, hasFocus: false, lastFocusedRow: null };

			function renderButton() {
				const btn = document.getElementById('splice-spy-btn');
				const btnGet = document.getElementById('splice-get-pack-btn');
				if (!btn) return;
				const { state, hasFocus, ext } = window.spyData;
				const shouldShow = hasFocus && state !== SpyState.HIDDEN;
				const isPackRunning = btnGet && btnGet.classList.contains('loading');

				if (!shouldShow || isPackRunning) {
					btn.classList.remove('visible');
					if (isPackRunning) btn.classList.add('hidden-by-pack');
					else btn.classList.remove('hidden-by-pack');
					setTimeout(() => { if (!btn.classList.contains('visible')) btn.classList.add('spy-d-none'); }, 300);
					return;
				}

				btn.classList.remove('hidden-by-pack', 'spy-d-none');
				void btn.offsetWidth;
				btn.classList.add('visible');

				if (state === SpyState.LOADING) btn.classList.add('loading');
				else if (state === SpyState.READY) {
					btn.classList.remove('loading');
					btn.title = `Download ${ext ? ext.toUpperCase() : ''}`;
				}
			}

			function updateState(newState, data = null) {
				if (newState) window.spyData.state = newState;
				if (data) { window.spyData.buffer = data.buffer; window.spyData.ext = data.ext; }
				renderButton();
			}

			window.addEventListener('spy-asset-update', (e) => {
				if (e.detail && e.detail.path) { window.spyData.localPath = e.detail.path; renderButton(); }
			});

			document.addEventListener('click', (e) => {
				const row = e.target.closest('core-asset-list-row');
				if (row) {
					const foundName = getFilenameFromRow(row);
					if (foundName) window.spyData.lastClickedFilename = foundName;
					if (window.spyData.lastFocusedRow !== row) {
						window.spyData.lastFocusedRow = row;
						window.spyData.state = SpyState.LOADING;
						window.spyData.buffer = null;
						window.spyData.hasFocus = true;
						renderButton();
					}
				}
			}, true);

			setInterval(() => {
				const focusedEl = document.querySelector('.focused');
				if (window.spyData.lastFocusedRow !== focusedEl) {
					window.spyData.lastFocusedRow = focusedEl;
					window.spyData.hasFocus = !!focusedEl;
					if (focusedEl) { window.spyData.state = SpyState.LOADING; window.spyData.buffer = null; }
					else window.spyData.state = SpyState.HIDDEN;
					renderButton();
				}
				const btnGet = document.getElementById('splice-get-pack-btn');
				if (btnGet) {
					const hasContainer = document.querySelector('sounds-pack-container, sounds-collection-container');
					if (hasContainer || btnGet.classList.contains('loading')) {
						btnGet.classList.add('visible');
						if (!btnGet.classList.contains('loading')) {
							const text = document.querySelector('sounds-collection-container') ? 'Get collection' : 'Get pack';
							if (!btnGet.textContent.includes(text)) btnGet.innerHTML = `${ICON_DOWNLOAD} <span>${text}</span>`;
						}
					} else btnGet.classList.remove('visible');
				}
			}, 200);

			function getFilenameFromRow(row) {
				const el = row.querySelector('.filename');
				if (!el) return null;
				let name = el.textContent.trim().replace(/\.(wav|aiff|flac|m4a)$/i, '.mp3');
				return name.endsWith('.mp3') ? name : name + '.mp3';
			}

			window.getPack = async function() {
				const btn = document.getElementById('splice-get-pack-btn');
				if (!btn) return;
				if (btn.classList.contains('loading')) { window.isGetPackCancelled = true; return; }
				const originalHtml = btn.innerHTML;
				btn.classList.add('loading');
				btn.innerHTML = `<div class="spy-spinner"></div> <span style="margin-left:5px">Cancel</span>`;
				window.isGetPackCancelled = false;
				renderButton();
				try {
					const rows = Array.from(document.querySelectorAll('core-asset-list-row'));
					for (const row of rows) {
						if (window.isGetPackCancelled) break;
						const playBtn = row.querySelector('[data-qa="playPlaybackButton"]');
						if (!playBtn) continue;
						window.spyData.buffer = null;
						row.scrollIntoView({ behavior: 'auto', block: 'center' });
						await new Promise(r => setTimeout(r, 100));
						const opts = { bubbles: true, cancelable: true, view: window };
						row.dispatchEvent(new MouseEvent('click', opts));
						playBtn.dispatchEvent(new MouseEvent('click', opts));
						let attempts = 0;
						while (!window.spyData.buffer && attempts < 25) {
							if (window.isGetPackCancelled) break;
							await new Promise(r => setTimeout(r, 200));
							attempts++;
						}
						if (window.spyData.buffer) await window.downloadLastAudio(getFilenameFromRow(row));
					}
				} finally {
					btn.classList.remove('loading');
					btn.innerHTML = originalHtml;
					renderButton();
				}
			};

			window.downloadLastAudio = async function(customFilename = null) {
				if (!customFilename) customFilename = window.spyData.lastClickedFilename;
				const localPath = window.spyData.localPath || document.body.getAttribute('data-spy-last-wav-path');
				if (localPath) {
					try {
						const fs = require('fs'), path = require('path'), os = require('os');
						const dest = path.join(os.homedir(), 'Downloads', customFilename || `splice_${Date.now()}.wav`);
						fs.copyFileSync(localPath, dest);
						const btn = document.getElementById('splice-spy-btn');
						if (btn) { const old = btn.innerHTML; btn.innerHTML = '<span>Saved!</span>'; setTimeout(() => btn.innerHTML = old, 2000); }
						return;
					} catch(e) {}
				}
				if (!window.spyData.buffer) return;
				const { ipcRenderer } = require('electron');
				await ipcRenderer.invoke('antigravity-save-file', customFilename || 'audio.mp3', window.spyData.buffer);
			};

			function injectButton() {
				if (document.getElementById('splice-spy-btn')) return;
				const container = document.createElement('div');
				container.id = 'splice-spy-container';
				Object.assign(container.style, { position: 'fixed', bottom: '82px', right: '22px', zIndex: '999999', display: 'flex', gap: '8px', alignItems: 'center' });
				
				const infoBtn = document.createElement('button');
				infoBtn.innerHTML = '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor"><rect x="3" y="3" width="12" height="12" rx="2" /><path d="M11 9h2M10 6h3M10 12h3M5 12l3-3-3-3" /></svg>';
				Object.assign(infoBtn.style, { background: 'none', border: 'none', cursor: 'pointer', color: 'rgba(255,255,255,0.5)' });
				infoBtn.onclick = () => require('electron').ipcRenderer.send('antigravity-toggle-devtools');

				const btnGetPack = document.createElement('button');
				btnGetPack.id = 'splice-get-pack-btn';
				btnGetPack.onclick = () => window.getPack();

				const btn = document.createElement('button');
				btn.id = 'splice-spy-btn';
				btn.innerHTML = `${ICON_DOWNLOAD} <span>Download</span> <div class="spy-spinner"></div>`;
				btn.onclick = () => window.downloadLastAudio();

				const wrapper = document.createElement('div');
				wrapper.className = 'splice-get-pack-btn-wrapper';
				wrapper.appendChild(btnGetPack);

				container.append(wrapper, btn, infoBtn);
				document.body.appendChild(container);

				require('electron').ipcRenderer.on('antigravity-devtools-state', (e, open) => {
					infoBtn.style.color = open ? '#aaff00' : 'rgba(255,255,255,0.5)';
				});
			}
			if (document.body) injectButton(); else document.addEventListener('DOMContentLoaded', injectButton);

			const originalFetch = window.fetch;
			window.fetch = async (...args) => {
				const url = args[0]?.toString().toLowerCase() || '';
				if (url.match(/\.(mp3|wav|m4a|aac|aiff|flac)(\?|$)/)) {
					if (window.spyData.state !== SpyState.READY) updateState(SpyState.LOADING);
				}
				return originalFetch.apply(window, args);
			};

			const originalDecodeAudioData = window.AudioContext.prototype.decodeAudioData;
			window.AudioContext.prototype.decodeAudioData = function(audioData, success, error) {
				const bufferCopy = audioData.slice(0);
				const wrappedSuccess = (decoded) => {
					decoded._spyOriginalData = bufferCopy;
					if (success) success(decoded);
				};
				return originalDecodeAudioData.call(this, audioData, wrappedSuccess, error);
			};

			const originalStart = window.AudioBufferSourceNode.prototype.start;
			window.AudioBufferSourceNode.prototype.start = function(...args) {
				if (this.buffer?._spyOriginalData) updateState(SpyState.READY, { buffer: this.buffer._spyOriginalData });
				return originalStart.apply(this, args);
			};
		</script>
EOF
        # Insert script after <head>
        sed -i '' '/<head>/r script.tmp' "$INDEX_HTML" || sed -i '/<head>/r script.tmp' "$INDEX_HTML"
        rm script.tmp
        echo -e "${GREEN}✓ index.html patched${NC}"
    fi
fi

echo -e "\n${GREEN}Modification Complete!${NC}"
echo -e "${YELLOW}Please restart Splice to see the changes.${NC}"
echo -e "${CYAN}Note: Your original app.asar has been renamed to app.asar.bak for safety.${NC}"
