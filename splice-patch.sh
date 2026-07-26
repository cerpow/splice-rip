#!/bin/bash

# Splice.com App - Sound Extractor
# This script injects the Audio Spy download functionality into Splice Desktop.

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}--- Splice.com App - Sound Extractor ---${NC}"

# Check for path argument
if [ -z "$1" ]; then
    echo -e "${YELLOW}Usage: drag Splice.app (Mac) or the Splice installation folder (Windows) here and press Enter${NC}"
    read -p "Path: " TARGET_PATH
else
    TARGET_PATH="$1"
fi

# Clean up path
TARGET_PATH="${TARGET_PATH%/}"

# Determine Resources Path based on OS/Folder structure
if [[ "$TARGET_PATH" == *.app ]]; then
    # Mac Bundle
    RESOURCES_PATH="$TARGET_PATH/Contents/Resources"
    echo -e "${CYAN}Detected macOS structure...${NC}"
elif [ -d "$TARGET_PATH/resources" ]; then
    # Windows/Linux standard structure
    RESOURCES_PATH="$TARGET_PATH/resources"
    echo -e "${CYAN}Detected Windows/Generic structure...${NC}"
elif [ -f "$TARGET_PATH/app.asar" ]; then
    # Path to resources folder itself
    RESOURCES_PATH="$TARGET_PATH"
    echo -e "${CYAN}Detected Resources folder...${NC}"
else
    echo -e "${RED}Error: Could not find app.asar in $TARGET_PATH${NC}"
    echo -e "${YELLOW}Mac: Provide the Splice.app folder.${NC}"
    echo -e "${YELLOW}Windows: Provide the folder containing 'resources/app.asar'${NC}"
    echo -e "${YELLOW}(Usually: %LocalAppData%\\Splice\\app-[version])${NC}"
    exit 1
fi

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

REOPEN_SPLICE=0
if [[ "$TARGET_PATH" == *.app ]]; then
    if pgrep -x "Splice" >/dev/null 2>&1; then
        echo -e "${CYAN}Closing Splice before patching...${NC}"
        osascript -e 'tell application "Splice" to quit' >/dev/null 2>&1 || true
        for _ in $(seq 1 40); do
            pgrep -x "Splice" >/dev/null 2>&1 || break
            sleep 0.25
        done
        if pgrep -x "Splice" >/dev/null 2>&1; then
            killall Splice >/dev/null 2>&1 || true
            sleep 1
        fi
        echo -e "${GREEN}✓ Splice closed${NC}"
    fi
    REOPEN_SPLICE=1
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

    # Remove previous injection so re-runs pick up updates
    if grep -q "antigravity-save-file" "$INDEX_JS"; then
        echo -e "${YELLOW}! Existing IPC handlers found, replacing...${NC}"
        node -e "
const fs = require('fs');
const p = process.argv[1];
let c = fs.readFileSync(p, 'utf8');
c = c.replace(/try \{\s*const \{ app, ipcMain, shell \} = require\('electron'\);[\s\S]*?\} catch \(e\) \{\}\s*/m, '');
fs.writeFileSync(p, c);
" "$INDEX_JS"
    fi

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
			fs.mkdirSync(path.dirname(filePath), { recursive: true });
			fs.writeFileSync(filePath, Buffer.from(buffer));
			shell.showItemInFolder(filePath);
			return { success: true, path: filePath };
		} catch (err) {
			return { success: false, error: err.message };
		}
	});
} catch (e) {}
EOF
    # Use Node for portable 'use strict' removal to avoid sed -i differences
    node -e "const fs = require('fs'); const p = process.argv[1]; let c = fs.readFileSync(p, 'utf8'); fs.writeFileSync(p, c.replace(/'use strict';/, ''));" "$INDEX_JS"
    cat "$INDEX_JS" >> index.js.tmp
    mv index.js.tmp "$INDEX_JS"
    echo -e "${GREEN}✓ index.js patched${NC}"
fi

# 2. Inject into index.html (Renderer Process)
INDEX_HTML="$UNPACKED_PATH/desktop-main/index.html"
if [ -f "$INDEX_HTML" ]; then
    echo -e "${CYAN}Injecting Audio Spy into index.html...${NC}"

    # Remove previous injection so re-runs pick up updates
    if grep -q "Audio Spy Injected" "$INDEX_HTML"; then
        echo -e "${YELLOW}! Existing Audio Spy found, replacing...${NC}"
        node -e "
const fs = require('fs');
const p = process.argv[1];
let html = fs.readFileSync(p, 'utf8');
// Remove nested injected <head><script>...Audio Spy...</script> block
html = html.replace(/\n?\t<head>\s*<script>[\s\S]*?Audio Spy Injected[\s\S]*?<\/script>\s*(?=<(?!\/head>))/m, '\n');
// Also handle case where injection is a bare <script> after <head>
html = html.replace(/<script>[\s\S]*?Audio Spy Injected[\s\S]*?<\/script>\s*/m, '');
fs.writeFileSync(p, html);
" "$INDEX_HTML"
    fi

    # We'll insert our script right after <head>
    # Prepare the script content
    cat << 'EOF' > script.tmp
<script>
			console.log('%c[Spy] Audio Spy Injected v22 (No double .wav)', 'color: cyan; font-size: 20px; font-weight: bold;');

			const ICON_DOWNLOAD = `<svg viewBox="0 0 16 16" width="16" height="16" fill="currentColor"><use xlink:href="#icon-download"></use></svg>`;
			const ICON_CHEVRON_UP = `<svg width="10" height="10" viewBox="0 0 10 10" fill="currentColor"><path d="M5 2.5L9 7H1L5 2.5z"/></svg>`;
			const ICON_CHEVRON_DOWN = `<svg width="10" height="10" viewBox="0 0 10 10" fill="currentColor"><path d="M5 7.5L1 3h8L5 7.5z"/></svg>`;
			const ICON_CHECK = `<svg width="16" height="16" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M3.5 8.5l3 3 6-7"/></svg>`;
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

    #splice-spy-container {
        display: flex;
        flex-direction: row;
        justify-content: flex-end;
        align-items: center;
        gap: 4px;
        right: 22px;
        bottom: 82px;
    }
    
    .spy-btn-class {
        transition: transform 0.3s cubic-bezier(0.34, 1.56, 0.64, 1), opacity 0.2s ease, width 0.3s ease, background-color 0.2s;
        transform: scale(0.7); 
        opacity: 0;
        pointer-events: none;
        overflow: hidden;
        white-space: nowrap;
        display: none;
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
    
    .spy-btn-class span { opacity: 1; transition: opacity 0.2s; }
    .spy-btn-class:hover span { opacity: 0.6; }
    .spy-btn-class svg { opacity: 0.7; transition: opacity 0.2s; }
    .spy-btn-class:hover svg { opacity: 0.4; }
    
    .spy-btn-class.visible {
        transform: scale(1);
        opacity: 1;
        pointer-events: auto;
        display: flex;
    }
    .spy-btn-class.visible.loading { width: 32px; padding: 0; opacity: 0.9; }
    .spy-btn-class.ready { width: auto; }
    
    .spy-btn-class .spy-spinner { display: none; margin: 0; }
    .spy-btn-class.loading .spy-spinner { display: block; }
    .spy-btn-class.loading svg, .spy-btn-class.loading span { display: none; }

    .spy-d-none { display: none !important; }
    .spy-btn-class.hidden-by-pack {
        width: 0 !important;
        padding: 0 !important;
        opacity: 0 !important;
        margin: 0 !important;
        pointer-events: none;
    }

    .splice-get-pack-btn-wrapper {
        display: none;
        align-items: center;
    }
    .splice-get-pack-btn-wrapper.visible {
        display: flex;
    }

    #splice-get-pack-btn {
        display: flex;
        align-items: stretch;
        height: 32px;
        background-color: #1253ff;
        color: #fff;
        border-radius: 5px;
        box-shadow: 0 4px 12px rgba(0,0,0,0.3);
        overflow: hidden;
        transition: opacity 0.2s ease, background-color 0.2s;
    }
    #splice-get-pack-btn.loading { opacity: 1; }
    #splice-get-pack-btn.success {
        background-color: #16a34a;
    }

    #splice-get-pack-action {
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 4px;
        border: none;
        background: transparent;
        color: inherit;
        font-weight: 500;
        font-size: 14px;
        cursor: pointer;
        padding: 0 10px 0 8px;
        white-space: nowrap;
    }
    #splice-get-pack-action span { opacity: 1; transition: opacity 0.2s; }
    #splice-get-pack-btn:not(.loading):not(.success) #splice-get-pack-action:hover span { opacity: 0.6; }
    #splice-get-pack-action svg { opacity: 0.7; transition: opacity 0.2s; }
    #splice-get-pack-btn:not(.loading):not(.success) #splice-get-pack-action:hover svg { opacity: 0.4; }
    #splice-get-pack-action .spy-spinner { display: none; margin: 0; }
    #splice-get-pack-btn.loading #splice-get-pack-action {
        cursor: default;
        padding: 0 12px 0 10px;
    }
    #splice-get-pack-btn.loading .spy-page-stepper,
    #splice-get-pack-btn.success .spy-page-stepper { display: none !important; }
    #splice-get-pack-btn:not(.has-stepper) #splice-get-pack-action {
        padding: 0 13px 0 8px;
    }
    #splice-get-pack-btn:not(.has-stepper) .spy-page-stepper {
        display: none;
    }
    #splice-get-pack-cancel {
        display: flex;
        align-items: center;
        justify-content: center;
        border: none;
        border-left: 1px solid rgba(255,255,255,0.22);
        background: rgba(0,0,0,0.18);
        color: #fff;
        font-weight: 500;
        font-size: 13px;
        cursor: pointer;
        padding: 0 12px;
        white-space: nowrap;
    }
    #splice-get-pack-cancel:hover {
        background: rgba(0,0,0,0.28);
    }
    #splice-get-pack-btn.success #splice-get-pack-action {
        padding: 0 13px 0 8px;
        cursor: default;
    }
    #splice-get-pack-btn.success #splice-get-pack-action svg {
        opacity: 1;
    }

    .spy-page-stepper {
        display: flex;
        align-items: stretch;
        border-left: 1px solid rgba(255,255,255,0.22);
        background: rgba(0,0,0,0.18);
    }
    .spy-page-stepper input {
        width: 28px;
        height: 100%;
        border: none;
        outline: none;
        background: transparent;
        color: #fff;
        text-align: center;
        font-size: 13px;
        font-weight: 600;
        -moz-appearance: textfield;
        padding: 0;
    }
    .spy-page-stepper input::-webkit-outer-spin-button,
    .spy-page-stepper input::-webkit-inner-spin-button {
        -webkit-appearance: none;
        margin: 0;
    }
    .spy-page-arrows {
        display: flex;
        flex-direction: column;
        border-left: 1px solid rgba(255,255,255,0.18);
        width: 18px;
    }
    .spy-page-arrows button {
        flex: 1;
        display: flex;
        align-items: center;
        justify-content: center;
        border: none;
        background: transparent;
        color: rgba(255,255,255,0.8);
        cursor: pointer;
        padding: 0;
        line-height: 0;
    }
    .spy-page-arrows button:hover {
        background: rgba(255,255,255,0.12);
        color: #fff;
    }
    .spy-page-arrows button:active {
        background: rgba(255,255,255,0.2);
    }
    .spy-page-arrows button + button {
        border-top: 1px solid rgba(255,255,255,0.18);
    }
`;

			const styleEl = document.createElement('style');
			styleEl.textContent = CSS_STYLES;
			document.head.appendChild(styleEl);

			const SpyState = { HIDDEN: 'hidden', LOADING: 'loading', READY: 'ready' };
			window.spyData = {
				state: SpyState.HIDDEN, buffer: null, audioBuffer: null, ext: null,
				hasFocus: false, lastFocusedRow: null,
				assetType: null, fileBuffer: null, fileName: null, assetSourceUrl: null
			};
			window.spyAssetCache = new Map(); // name/uuid -> asset metadata from GraphQL

			function renderButton() {
				const btn = document.getElementById('splice-spy-btn');
				const btnWav = document.getElementById('splice-spy-btn-wav');
				const btnGet = document.getElementById('splice-get-pack-btn');
				if (!btn) return;
				const { state, hasFocus, ext, audioBuffer, buffer, fileBuffer, assetSourceUrl, assetType } = window.spyData;
				const fileAvailable = !!(fileBuffer || assetSourceUrl);
				const shouldShow = hasFocus && state !== SpyState.HIDDEN && !shouldHideDownloadsForPresets();
				const isPackRunning = btnGet && (btnGet.classList.contains('loading') || btnGet.classList.contains('success'));
				const allBtns = [btn, btnWav].filter(Boolean);

				// Prefer real MIDI/preset file, then WAV, then MP3.
				const wavAvailable = !!audioBuffer;
				const mp3Available = !!buffer;
				const preferFile = fileAvailable && (assetType === 'midi' || assetType === 'preset');
				const preferWav = !preferFile && (wavAvailable || state === SpyState.LOADING || (!mp3Available));
				const activeBtn = (preferFile || preferWav) ? btnWav : btn;
				const inactiveBtn = (preferFile || preferWav) ? btn : btnWav;

				if (!shouldShow || isPackRunning) {
					allBtns.forEach(b => b.classList.remove('visible'));
					if (isPackRunning) allBtns.forEach(b => b.classList.add('hidden-by-pack'));
					else allBtns.forEach(b => b.classList.remove('hidden-by-pack'));
					setTimeout(() => { allBtns.forEach(b => { if (!b.classList.contains('visible')) b.classList.add('spy-d-none'); }); }, 300);
					return;
				}

				if (inactiveBtn) {
					inactiveBtn.classList.remove('visible', 'loading');
					inactiveBtn.classList.add('spy-d-none');
				}

				if (activeBtn) {
					activeBtn.classList.remove('hidden-by-pack', 'spy-d-none');
					void activeBtn.offsetWidth;
					activeBtn.classList.add('visible');

					if (state === SpyState.LOADING) activeBtn.classList.add('loading');
					else if (state === SpyState.READY) {
						activeBtn.classList.remove('loading');
						if (preferFile) activeBtn.title = `Download selected ${assetType === 'midi' ? 'MIDI' : 'preset'} file`;
						else activeBtn.title = preferWav ? 'Download selected as WAV' : `Download selected as ${ext ? ext.toUpperCase() : 'MP3'}`;
					}
				}
			}

			function updateState(newState, data = null) {
				if (newState) window.spyData.state = newState;
				if (data) { window.spyData.buffer = data.buffer; window.spyData.audioBuffer = data.audioBuffer; window.spyData.ext = data.ext; }
				renderButton();
			}

			window.addEventListener('spy-asset-update', (e) => {
				if (e.detail && e.detail.path) { window.spyData.localPath = e.detail.path; renderButton(); }
			});

			document.addEventListener('click', (e) => {
				const row = e.target.closest('core-asset-list-row');
				if (row) {
					const foundName = getRawFilenameFromRow(row);
					if (foundName) window.spyData.lastClickedFilename = foundName;
					if (window.spyData.lastFocusedRow !== row) {
						window.spyData.lastFocusedRow = row;
						window.spyData.state = SpyState.LOADING;
						window.spyData.buffer = null;
						window.spyData.audioBuffer = null;
						window.spyData.fileBuffer = null;
						window.spyData.assetSourceUrl = null;
						window.spyData.hasFocus = true;
						resolveRowAsset(row);
						renderButton();
					}
				}
			}, true);

			setInterval(() => {
				const focusedEl = document.querySelector('.focused');
				if (window.spyData.lastFocusedRow !== focusedEl) {
					window.spyData.lastFocusedRow = focusedEl;
					window.spyData.hasFocus = !!focusedEl;
					if (focusedEl) {
						window.spyData.state = SpyState.LOADING;
						window.spyData.buffer = null;
						window.spyData.audioBuffer = null;
						window.spyData.fileBuffer = null;
						window.spyData.assetSourceUrl = null;
						resolveRowAsset(focusedEl);
					} else window.spyData.state = SpyState.HIDDEN;
					renderButton();
				}
				const btnGet = document.getElementById('splice-get-pack-btn');
				const packWrapper = document.querySelector('.splice-get-pack-btn-wrapper');
				if (btnGet && packWrapper) {
					const showBulk = shouldShowBulkButton();
					if (showBulk || btnGet.classList.contains('loading')) {
						packWrapper.classList.add('visible');
						if (!btnGet.classList.contains('loading')) syncPagesButtonLabel();
					} else packWrapper.classList.remove('visible');
				}
			}, 200);

			function isPackPage() {
				return !!document.querySelector('sounds-pack-container');
			}

			function isCollectionPage() {
				return !!document.querySelector('sounds-collection-container');
			}

			function isPackOrCollectionPage() {
				return isPackPage() || isCollectionPage();
			}

			function hasPaginationControls() {
				return !!(
					document.querySelector('.page-select-link') ||
					document.querySelector('[aria-label="Next Page"]') ||
					document.querySelector('[aria-label="Previous Page"]') ||
					document.querySelector('[data-qa="pagination.next-button"]') ||
					document.querySelector('[data-qa="pagination.prev-button"]') ||
					document.querySelector('[data-qa="next-button-event"]') ||
					document.querySelector('[data-qa*="pagination"]')
				);
			}


			function isPresetsTabActive() {
				const path = (location.pathname || '').toLowerCase();
				if (/(?:^|\/)presets(?:\/|$)/.test(path)) return true;
				const candidates = document.querySelectorAll('[role="tab"], a, button, .mat-tab-label, [class*="tab"]');
				for (const el of candidates) {
					const text = (el.textContent || '').trim().toLowerCase();
					if (text !== 'presets' && text !== 'preset') continue;
					const selected =
						el.getAttribute('aria-selected') === 'true' ||
						el.classList.contains('active') ||
						el.classList.contains('selected') ||
						el.classList.contains('mat-tab-label-active') ||
						el.getAttribute('aria-current') === 'page';
					if (selected) return true;
				}
				return false;
			}

			function isSelectedPreset() {
				if (window.spyData.assetType === 'preset') return true;
				const row = window.spyData.lastFocusedRow;
				if (!row) return false;
				return getAssetKind(getRawFilenameFromRow(row)) === 'preset';
			}

			function shouldHideDownloadsForPresets() {
				return isPresetsTabActive() || isSelectedPreset();
			}

			function shouldShowBulkButton() {
				if (isPresetsTabActive()) return false;
				return isPackOrCollectionPage() || hasPaginationControls();
			}

			function getDetectedTotalPages() {
				const nums = Array.from(document.querySelectorAll('.page-select-link'))
					.map(el => parseInt(el.textContent.trim(), 10))
					.filter(n => Number.isFinite(n) && n > 0);
				return nums.length ? Math.max(...nums) : 1;
			}

			function getPagesButtonLabel() {
				if (isCollectionPage()) return 'Get Collection';
				if (isPackPage()) return 'Get Pack';
				return 'Pages';
			}

			function syncPagesButtonLabel() {
				const action = document.getElementById('splice-get-pack-action');
				const btnGet = document.getElementById('splice-get-pack-btn');
				if (!action || !btnGet || btnGet.classList.contains('loading') || btnGet.classList.contains('success')) return;
				const label = getPagesButtonLabel();
				const span = action.querySelector('span');
				if (!span || span.textContent !== label) {
					action.innerHTML = `${ICON_DOWNLOAD} <span>${label}</span>`;
				}
				// Page count selector only on search-like pages, not Pack/Collection
				if (isPackOrCollectionPage()) btnGet.classList.remove('has-stepper');
				else btnGet.classList.add('has-stepper');
			}

			function getListedSampleTotal(maxPages) {
				const scopes = [
					document.querySelector('sounds-pack-container'),
					document.querySelector('sounds-collection-container'),
					document.querySelector('core-entity-header'),
					document.querySelector('h1')?.parentElement
				].filter(Boolean);
				for (const scope of scopes) {
					const m = (scope.textContent || '').match(/([\d,]+)\s*(?:sounds?|samples?|files?)/i);
					if (m) {
						const n = parseInt(m[1].replace(/,/g, ''), 10);
						if (Number.isFinite(n) && n > 0) return n;
					}
				}
				const rows = document.querySelectorAll('core-asset-list-row').length;
				return Math.max(1, (maxPages || 1) * Math.max(rows, 1));
			}

			function setBulkProgress(done, total) {
				const btn = document.getElementById('splice-get-pack-btn');
				const action = document.getElementById('splice-get-pack-action');
				if (!btn || !action) return;
				btn.classList.add('loading');
				btn.classList.remove('success', 'has-stepper');
				action.innerHTML = `<span>Downloading ${done}/${total}</span>`;
				let cancel = document.getElementById('splice-get-pack-cancel');
				if (!cancel) {
					cancel = document.createElement('button');
					cancel.type = 'button';
					cancel.id = 'splice-get-pack-cancel';
					cancel.textContent = 'Cancel';
					cancel.onclick = (e) => {
						e.preventDefault();
						e.stopPropagation();
						window.isGetPackCancelled = true;
						cancel.textContent = 'Cancelling…';
						cancel.disabled = true;
					};
					btn.appendChild(cancel);
				}
			}

			function showBulkDownloaded() {
				const btn = document.getElementById('splice-get-pack-btn');
				const action = document.getElementById('splice-get-pack-action');
				const cancel = document.getElementById('splice-get-pack-cancel');
				if (cancel) cancel.remove();
				if (!btn || !action) return;
				btn.classList.remove('loading', 'has-stepper');
				btn.classList.add('success');
				action.innerHTML = `${ICON_CHECK} <span>Downloaded</span>`;
			}

			function restoreBulkButton() {
				const btn = document.getElementById('splice-get-pack-btn');
				const cancel = document.getElementById('splice-get-pack-cancel');
				if (cancel) cancel.remove();
				if (btn) btn.classList.remove('loading', 'success');
				syncPagesButtonLabel();
				renderButton();
			}

			function getRawFilenameFromRow(row) {
				const el = row.querySelector('.filename');
				if (!el) return null;
				return el.textContent.trim();
			}

			function getFilenameFromRow(row) {
				const name = getRawFilenameFromRow(row);
				if (!name) return null;
				const kind = getAssetKind(name);
				if (kind === 'midi' || kind === 'preset') return name;
				let out = name.replace(/\.(wav|aiff|flac|m4a)$/i, '.mp3');
				return out.toLowerCase().endsWith('.mp3') ? out : out + '.mp3';
			}

			function toWavFilename(name) {
				const base = String(name || `audio_${Date.now()}`)
					.replace(/\.(mp3|wav|aiff|aif|flac|m4a|mid|midi|serumpreset|fxp|xml|nksn|h2p)$/i, '');
				return `${base}.wav`;
			}

			function getAssetKind(name, asset = null) {
				const n = (name || asset?.name || '').toLowerCase();
				const typeSlug = (asset?.asset_type_slug || asset?.__typename || '').toLowerCase();
				if (typeSlug.includes('midi') || /\.(mid|midi)$/i.test(n)) return 'midi';
				if (typeSlug.includes('preset') || /\.(serumpreset|fxp|preset|vital|json|xml|nksn|h2p)$/i.test(n)) return 'preset';
				return 'sample';
			}

			function normalizeAssetKey(name) {
				return (name || '').toLowerCase().replace(/\.(serumpreset|mid|midi|wav|mp3|aiff|flac|fxp|m4a)$/i, '');
			}

			function cacheAssetFromGraphql(asset) {
				if (!asset || !asset.name) return;
				const entry = {
					uuid: asset.uuid,
					name: asset.name,
					__typename: asset.__typename,
					asset_type_slug: asset.asset_type_slug,
					files: Array.isArray(asset.files) ? asset.files : [],
					licensed: !!asset.licensed,
					device: asset.device || null
				};
				const keys = [asset.name.toLowerCase(), normalizeAssetKey(asset.name)];
				if (asset.uuid) keys.push(asset.uuid);
				const prev = window.spyAssetCache.get(normalizeAssetKey(asset.name));
				keys.filter(Boolean).forEach(k => window.spyAssetCache.set(k, entry));
				if (!prev || (entry.files?.length && entry.files.length !== (prev.files?.length || 0))) {
					const fileSummary = (entry.files || []).map(f => ({
						slug: f?.asset_file_type_slug,
						hasUrl: !!f?.url,
						name: f?.name,
						path: f?.path,
						url: f?.url || null
					}));
					console.log('[Spy Debug] Cached asset from network', entry.name, entry.__typename || entry.asset_type_slug, fileSummary);
				}
			}

			function walkGraphqlForAssets(node, depth = 0) {
				if (!node || typeof node !== 'object' || depth > 12) return;
				if (Array.isArray(node)) { node.forEach(n => walkGraphqlForAssets(n, depth + 1)); return; }
				if (node.name && (Array.isArray(node.files) || node.__typename || node.uuid)) cacheAssetFromGraphql(node);
				for (const key of Object.keys(node)) {
					try { walkGraphqlForAssets(node[key], depth + 1); } catch (_) {}
				}
			}

			function findCachedAsset(name) {
				if (!name) return null;
				const lower = name.toLowerCase();
				const norm = normalizeAssetKey(name);
				if (window.spyAssetCache.has(lower)) return window.spyAssetCache.get(lower);
				if (window.spyAssetCache.has(norm)) return window.spyAssetCache.get(norm);
				for (const asset of window.spyAssetCache.values()) {
					if (normalizeAssetKey(asset.name) === norm) return asset;
				}
				return null;
			}

			function getGraphqlEndpoint() {
				if (window.graphQLEndpoint) return window.graphQLEndpoint;
				if (window.environment === 'production' || !window.environment) return 'https://surfaces-graphql.splice.com/graphql';
				return 'https://surfaces-graphql-preprod.splice.com/graphql';
			}

			function getAccessTokenFromStorage() {
				for (let i = 0; i < localStorage.length; i++) {
					const key = localStorage.key(i);
					const raw = localStorage.getItem(key);
					if (!raw || raw.length < 20) continue;
					try {
						const parsed = JSON.parse(raw);
						const token = parsed?.body?.access_token || parsed?.access_token || parsed?.accessToken;
						if (token && typeof token === 'string' && token.length > 20) return token;
					} catch (_) {}
				}
				return null;
			}

			async function queryGraphql(query, variables = {}) {
				const endpoint = getGraphqlEndpoint();
				const token = getAccessTokenFromStorage();
				const headers = {
					'content-type': 'application/json',
					'apollographql-client-name': 'splice-desktop-main'
				};
				if (token) headers.Authorization = `Bearer ${token}`;
				console.log('[Spy Debug] GraphQL request', endpoint, { hasToken: !!token, variables });
				const res = await fetch(endpoint, {
					method: 'POST',
					headers,
					credentials: 'include',
					body: JSON.stringify({ query, variables })
				});
				const json = await res.json();
				console.log('[Spy Debug] GraphQL response status', res.status, {
					errors: json.errors || null,
					keys: json.data ? Object.keys(json.data) : null
				});
				walkGraphqlForAssets(json);
				return json;
			}

			async function lookupSelectedAsset(name) {
				if (!name) return null;
				const cached = findCachedAsset(name);
				if (cached?.files?.length) return cached;

				const queryName = name.replace(/\.(SerumPreset|mid|midi)$/i, '');
				const isMidi = /\.(mid|midi)$/i.test(name);
				const assetType = isMidi ? 'midi' : 'preset';
				const query = `
					query SpyAssetLookup($query: String, $asset_type_slug: AssetTypeSlug) {
						assetsSearch(filter: { query: $query, asset_type_slug: $asset_type_slug }, limit: 10) {
							items {
								... on IAsset {
									uuid
									name
									licensed
									asset_type_slug
									files { name hash path asset_file_type_slug url uuid }
								}
								... on PresetAsset {
									__typename
									device { name uuid }
								}
								... on MidiAsset {
									__typename
								}
								... on SampleAsset {
									__typename
								}
							}
						}
					}
				`;
				try {
					const json = await queryGraphql(query, { query: queryName, asset_type_slug: assetType });
					const items = json?.data?.assetsSearch?.items || [];
					console.log('[Spy Debug] Lookup items', items.map(i => ({
						name: i?.name,
						uuid: i?.uuid,
						typename: i?.__typename,
						files: (i?.files || []).map(f => ({ slug: f?.asset_file_type_slug, hasUrl: !!f?.url, url: f?.url }))
					})));
					const match = items.find(i => normalizeAssetKey(i?.name) === normalizeAssetKey(name)) || items[0] || null;
					if (match) cacheAssetFromGraphql(match);
					return findCachedAsset(name) || match;
				} catch (err) {
					console.error('[Spy Debug] Active GraphQL lookup failed', err);
					return findCachedAsset(name);
				}
			}

			function getSourceFile(asset) {
				if (!asset?.files?.length) return null;
				return asset.files.find(f => f && f.asset_file_type_slug === 'source' && f.url)
					|| asset.files.find(f => f && f.url && !/preview/i.test(f.asset_file_type_slug || '') && !/preview/i.test(f.path || ''))
					|| null;
			}

			function getPreviewFile(asset) {
				if (!asset?.files?.length) return null;
				return asset.files.find(f => f && f.url && (f.asset_file_type_slug === 'preview_mp3' || /preview/i.test(f.path || '') || /preview/i.test(f.url || ''))) || null;
			}

			function extractNgAssetFromRow(row) {
				const found = [];
				const seen = new Set();
				const pushAsset = (val) => {
					if (!val?.name || seen.has(val)) return;
					seen.add(val);
					found.push({
						name: val.name,
						uuid: val.uuid,
						__typename: val.__typename,
						asset_type_slug: val.asset_type_slug,
						licensed: val.licensed,
						files: val.files,
						device: val.device,
						keys: Object.keys(val).slice(0, 40)
					});
				};
				const visit = (val, depth = 0) => {
					if (!val || depth > 5 || typeof val !== 'object') return;
					if (found.length > 12) return;
					if (val.preset) pushAsset(val.preset);
					if (val.sample) pushAsset(val.sample);
					if (val.midi) pushAsset(val.midi);
					if (val.asset) pushAsset(val.asset);
					if (val.name && (val.uuid || val.files || val.__typename)) pushAsset(val);
					if (Array.isArray(val)) {
						for (const item of val.slice(0, 25)) visit(item, depth + 1);
						return;
					}
					for (const key of Object.keys(val).slice(0, 50)) {
						if (key.startsWith('ɵ') || (key.startsWith('__') && key !== '__typename' && key !== '__ngContext__')) continue;
						try { visit(val[key], depth + 1); } catch (_) {}
					}
				};

				let el = row;
				for (let i = 0; i < 10 && el; i++) {
					for (const key of ['preset', 'sample', 'midi', 'asset', 'item', 'data']) {
						try { if (el[key]) pushAsset(el[key]); } catch (_) {}
					}
					try { visit(el.__ngContext__); } catch (_) {}
					try {
						if (typeof ng !== 'undefined') {
							const comp = ng.getComponent?.(el);
							if (comp) visit(comp);
							const ctx = ng.getContext?.(el);
							if (ctx) visit(ctx);
						}
					} catch (_) {}
					el = el.parentElement;
				}
				return found;
			}

			function debugSelectedAsset(row, extra = {}) {
				const name = getRawFilenameFromRow(row);
				const cached = findCachedAsset(name);
				const ngAssets = extractNgAssetFromRow(row);
				const kind = getAssetKind(name, cached || ngAssets[0]);
				const files = cached?.files || ngAssets.find(a => a.files?.length)?.files || [];
				const source = getSourceFile(cached) || getSourceFile({ files });
				const preview = getPreviewFile(cached) || getPreviewFile({ files });
				const cacheKeys = [...window.spyAssetCache.keys()].slice(0, 30);

				console.log('%c[Spy Debug] Selected asset', 'color: #fbbf24; font-weight: bold;');
				console.table([{
					name,
					kind,
					cached: !!cached,
					uuid: cached?.uuid || ngAssets[0]?.uuid || null,
					typename: cached?.__typename || ngAssets[0]?.__typename || null,
					licensed: cached?.licensed ?? ngAssets[0]?.licensed ?? null,
					filesCount: files.length,
					hasSourceUrl: !!source?.url,
					hasPreviewUrl: !!preview?.url,
					sourceUrl: source?.url || null,
					previewUrl: preview?.url || null,
					spyState: window.spyData.state,
					hasAudioBuffer: !!window.spyData.audioBuffer,
					hasFileBuffer: !!window.spyData.fileBuffer,
					cacheSize: window.spyAssetCache.size
				}]);
				console.log('[Spy Debug] files[]', files);
				console.log('[Spy Debug] ng-extracted candidates', ngAssets);
				console.log('[Spy Debug] cache keys (first 30)', cacheKeys);
				console.log('[Spy Debug] spyData', { ...window.spyData, buffer: !!window.spyData.buffer, audioBuffer: !!window.spyData.audioBuffer, fileBuffer: !!window.spyData.fileBuffer && window.spyData.fileBuffer.byteLength });
				console.log('[Spy Debug] extras', extra);
				return { name, kind, cached, ngAssets, files, source, preview };
			}

			window.spyDebugSelected = function() {
				const row = window.spyData.lastFocusedRow || document.querySelector('core-asset-list-row.focused, .focused');
				if (!row) {
					console.warn('[Spy Debug] No focused row. Select a preset/sample first.');
					return null;
				}
				return debugSelectedAsset(row, { manual: true });
			};

			async function applyResolvedAsset(row, asset, name) {
				const kind = getAssetKind(name, asset);
				const source = getSourceFile(asset);
				const preview = getPreviewFile(asset);
				window.spyData.assetType = kind;
				window.spyData.fileName = source?.name || name || null;
				window.spyData.assetSourceUrl = source?.url || null;
				window.spyData.fileBuffer = null;

				console.log('[Spy Debug] Resolved after lookup', {
					name,
					kind,
					uuid: asset?.uuid,
					licensed: asset?.licensed,
					files: (asset?.files || []).map(f => ({ slug: f?.asset_file_type_slug, hasUrl: !!f?.url, url: f?.url, path: f?.path })),
					hasSourceUrl: !!source?.url,
					hasPreviewUrl: !!preview?.url
				});

				if ((kind === 'midi' || kind === 'preset') && source?.url) {
					console.log('[Spy Debug] Prefetching SOURCE file...', source.url);
					try {
						const r = await fetch(source.url);
						console.log('[Spy Debug] Source fetch status', r.status, r.headers.get('content-type'));
						const buf = await r.arrayBuffer();
						if (window.spyData.lastFocusedRow !== row) return;
						window.spyData.fileBuffer = buf;
						console.log('[Spy Debug] Source file ready', buf.byteLength, 'bytes');
						updateState(SpyState.READY, { buffer: window.spyData.buffer, audioBuffer: window.spyData.audioBuffer, ext: kind });
					} catch (err) {
						console.warn('[Spy] Source file prefetch failed:', err);
					}
					return;
				}

				if ((kind === 'midi' || kind === 'preset') && !source?.url) {
					console.warn('%c[Spy Debug] No source URL for this preset/MIDI — Splice did not expose the real file.', 'color: #f87171;');
					if (preview?.url) console.log('[Spy Debug] Preview URL only:', preview.url);
					if (window.spyData.lastFocusedRow === row && !window.spyData.audioBuffer) {
						window.spyData.state = SpyState.READY;
						renderButton();
					}
				}
			}

			function resolveRowAsset(row) {
				const debug = debugSelectedAsset(row);
				const name = debug.name;
				if (debug.ngAssets?.length) {
					for (const candidate of debug.ngAssets) {
						if (candidate.name || candidate.uuid) cacheAssetFromGraphql(candidate);
					}
				}

				const kind = debug.kind;
				window.spyData.assetType = kind;
				window.spyData.fileName = name;
				window.spyData.assetSourceUrl = debug.source?.url || null;
				window.spyData.fileBuffer = null;

				if (kind === 'midi' || kind === 'preset') {
					lookupSelectedAsset(name).then(asset => {
						if (window.spyData.lastFocusedRow !== row) return;
						applyResolvedAsset(row, asset, name);
						debugSelectedAsset(row, { afterLookup: true });
					});
				}
			}

			async function saveBinaryFile(relativePath, buffer) {
				const { ipcRenderer } = require('electron');
				return ipcRenderer.invoke('antigravity-save-file', relativePath, buffer);
			}

			async function downloadRowAssetFile(row, packName) {
				const name = getRawFilenameFromRow(row);
				const asset = findCachedAsset(name);
				const kind = getAssetKind(name, asset);
				if (kind === 'sample') return false;
				const source = getSourceFile(asset);
				if (!source?.url) {
					console.warn(`[Spy] No source URL for ${kind} "${name}". Splice usually only exposes preview audio until licensed.`);
					return false;
				}
				try {
					const res = await fetch(source.url);
					if (!res.ok) throw new Error(`HTTP ${res.status}`);
					const buf = await res.arrayBuffer();
					const filename = source.name || name || `asset_${Date.now()}`;
					const fullPath = packName ? require('path').join(packName, filename) : filename;
					const result = await saveBinaryFile(fullPath, buf);
					return !!(result && result.success);
				} catch (err) {
					console.error(`[Spy] Failed to download ${kind} file:`, err);
					return false;
				}
			}

			function getPackName() {
				const h1 = document.querySelector('h1, .sounds-pack-header h1, core-entity-header h1');
				if (h1 && h1.textContent) return h1.textContent.trim().replace(/[^a-z0-9 _-]/gi, '_');
				const titleTitle = document.title.split('|')[0].trim();
				return titleTitle ? titleTitle.replace(/[^a-z0-9 _-]/gi, '_') : 'Splice_Downloads';
			}

			window.getPack = async function() {
				const btn = document.getElementById('splice-get-pack-btn');
				const action = document.getElementById('splice-get-pack-action');
				const pageInput = document.getElementById('splice-get-pack-pages');
				if (!btn || !action) return;
				if (btn.classList.contains('loading') || btn.classList.contains('success')) return;

				const autoAllPages = isPackOrCollectionPage();
				const selectedCount = pageInput ? parseInt(pageInput.value, 10) || 1 : 1;
				let maxPages = autoAllPages ? getDetectedTotalPages() : selectedCount;
				const packName = getPackName();
				let done = 0;
				let total = getListedSampleTotal(maxPages);

				window.isGetPackCancelled = false;
				setBulkProgress(done, total);
				renderButton();
				
				try {
					const getSelectedPage = () => {
						const sel = document.querySelector('.page-select-link.selected');
						return sel ? parseInt(sel.textContent.trim(), 10) : 1;
					};

					const goToPage = async (expectedNextPage) => {
						const targetLink = Array.from(document.querySelectorAll('.page-select-link'))
							.find(l => l.textContent.trim() === expectedNextPage.toString());
						if (targetLink) {
							targetLink.click();
						} else {
							const nextBtn = document.querySelector('[aria-label="Next Page"], [data-qa="pagination.next-button"], [data-qa="next-button-event"]');
							if (nextBtn && !nextBtn.disabled && !nextBtn.classList.contains('disabled') && nextBtn.getAttribute('aria-disabled') !== 'true') {
								nextBtn.click();
							} else {
								return false;
							}
						}
						let wait = 0;
						while (getSelectedPage() !== expectedNextPage && wait < 20) {
							await new Promise(r => setTimeout(r, 250));
							wait++;
						}
						await new Promise(r => setTimeout(r, 2000));
						return getSelectedPage() === expectedNextPage;
					};

					console.log(`[Spy] Starting batch download. autoAll=${autoAllPages}, pages=${maxPages}, total=${total}, current=${getSelectedPage()}`);

					if (getSelectedPage() !== 1) {
						console.log('[Spy] Not on page 1. Navigating to page 1...');
						const page1 = Array.from(document.querySelectorAll('.page-select-link')).find(l => l.textContent.trim() === '1');
						if (page1) {
							page1.click();
							let wait = 0;
							while (getSelectedPage() !== 1 && wait < 20) {
								await new Promise(r => setTimeout(r, 250));
								wait++;
							}
							await new Promise(r => setTimeout(r, 1500));
						} else {
							console.log('[Spy] Could not find page 1 link!');
						}
					}

					let currentPage = 1;

					while (!window.isGetPackCancelled) {
						if (autoAllPages) maxPages = Math.max(maxPages, getDetectedTotalPages());
						if (!autoAllPages && currentPage > maxPages) break;

						console.log(`[Spy] Processing page ${currentPage}/${autoAllPages ? maxPages : selectedCount}`);
						let rows = [];
						let waitAttempts = 0;
						while (rows.length === 0 && waitAttempts < 10) {
							rows = Array.from(document.querySelectorAll('core-asset-list-row'));
							if (rows.length === 0) await new Promise(r => setTimeout(r, 500));
							waitAttempts++;
						}

						if (rows.length) {
							total = Math.max(total, getListedSampleTotal(maxPages), maxPages * rows.length);
							setBulkProgress(done, total);
						}

						for (const row of rows) {
							if (window.isGetPackCancelled) break;
							row.scrollIntoView({ behavior: 'auto', block: 'center' });
							await new Promise(r => setTimeout(r, 80));

							const rawName = getRawFilenameFromRow(row);
							const kind = getAssetKind(rawName, findCachedAsset(rawName));

							// MIDI / presets: download source file when Splice exposes a URL
							if (kind === 'midi' || kind === 'preset') {
								const saved = await downloadRowAssetFile(row, packName);
								if (saved) {
									done++;
									if (done > total) total = done;
									setBulkProgress(done, total);
								}
								continue;
							}

							const playBtn = row.querySelector('[data-qa="playPlaybackButton"]');
							if (!playBtn) continue;
							window.spyData.buffer = null;
							window.spyData.audioBuffer = null;
							const opts = { bubbles: true, cancelable: true, view: window };
							row.dispatchEvent(new MouseEvent('click', opts));
							playBtn.dispatchEvent(new MouseEvent('click', opts));
							
							let attempts = 0;
							while (!window.spyData.audioBuffer && attempts < 25) {
								if (window.isGetPackCancelled) break;
								await new Promise(r => setTimeout(r, 200));
								attempts++;
							}
							
							if (window.spyData.audioBuffer && !window.isGetPackCancelled) {
								const filename = toWavFilename(getRawFilenameFromRow(row) || getFilenameFromRow(row));
								
								const wavBuffer = audioBufferToWav(window.spyData.audioBuffer);
								const fullPath = require('path').join(packName, filename);
								
								console.log(`[Spy] Saving batch WAV: ${fullPath}`);
								const result = await saveBinaryFile(fullPath, wavBuffer);
								if (!result || !result.success) console.error(`[Spy] Batch save failed for ${filename}:`, result);
								else {
									done++;
									if (done > total) total = done;
									setBulkProgress(done, total);
								}
							}
						}

						if (window.isGetPackCancelled) break;

						const expectedNextPage = currentPage + 1;
						const nextBtn = document.querySelector('[aria-label="Next Page"], [data-qa="pagination.next-button"], [data-qa="next-button-event"]');
						const nextEnabled = !!(nextBtn && !nextBtn.disabled && !nextBtn.classList.contains('disabled') && nextBtn.getAttribute('aria-disabled') !== 'true');
						const detected = getDetectedTotalPages();
						const shouldContinue = autoAllPages
							? (expectedNextPage <= detected || nextEnabled)
							: expectedNextPage <= maxPages;

						if (!shouldContinue) break;

						console.log(`[Spy] Moving to page ${expectedNextPage}`);
						const moved = await goToPage(expectedNextPage);
						if (!moved) {
							console.log('[Spy] No more pages or next navigation failed');
							break;
						}
						currentPage = expectedNextPage;
					}

					if (!window.isGetPackCancelled) {
						showBulkDownloaded();
						await new Promise(r => setTimeout(r, 2000));
					}
				} finally {
					restoreBulkButton();
					console.log('[Spy] Batch download finished or cancelled.');
				}
			};

			window.downloadLastAudio = async function(customFilename = null) {
				if (!customFilename) customFilename = window.spyData.lastClickedFilename;
				
				console.log('[Spy] downloadLastAudio (MP3) triggered.', { customFilename, hasBuffer: !!window.spyData.buffer });
				
				const localPath = window.spyData.localPath || document.body.getAttribute('data-spy-last-wav-path');
				if (localPath) {
					try {
						const fs = require('fs'), path = require('path'), os = require('os');
						const dest = path.join(os.homedir(), 'Downloads', customFilename || `splice_${Date.now()}.wav`);
						console.log(`[Spy] Copying local file ${localPath} to ${dest}`);
						fs.copyFileSync(localPath, dest);
						const btn = document.getElementById('splice-spy-btn');
						if (btn) { const old = btn.innerHTML; btn.innerHTML = '<span>Saved!</span>'; setTimeout(() => btn.innerHTML = old, 2000); }
						return;
					} catch(e) {
						console.error(`[Spy] Error copying local file:`, e);
					}
				}
				if (!window.spyData.buffer) {
					console.error('[Spy] Cannot download: window.spyData.buffer is null.');
					return;
				}
				const { ipcRenderer } = require('electron');
				console.log(`[Spy] Saving MP3: ${customFilename}, Buffer size: ${window.spyData.buffer.byteLength}`);
				const result = await ipcRenderer.invoke('antigravity-save-file', customFilename || 'audio.mp3', window.spyData.buffer);
				console.log(`[Spy] IPC Save result (MP3):`, result);
				
				const btn = document.getElementById('splice-spy-btn');
				if (btn) { 
					const old = btn.innerHTML; 
					if (result && result.success) btn.innerHTML = '<span>Saved!</span>';
					else btn.innerHTML = '<span>Error!</span>';
					setTimeout(() => btn.innerHTML = old, 2000); 
				}
			};

			function audioBufferToWav(buffer) {
				const numChannels = buffer.numberOfChannels;
				const sampleRate = buffer.sampleRate;
				const format = 1; // PCM
				const bitDepth = 16;
				
				let result;
				if (numChannels === 2) {
					const channelData0 = buffer.getChannelData(0);
					const channelData1 = buffer.getChannelData(1);
					const length = channelData0.length * 4;
					result = new Float32Array(length / 2);
					for (let i = 0; i < channelData0.length; i++) {
						result[i * 2] = channelData0[i];
						result[i * 2 + 1] = channelData1[i];
					}
				} else {
					result = buffer.getChannelData(0);
				}
				
				const bytesPerSample = bitDepth / 8;
				const blockAlign = numChannels * bytesPerSample;
				const wavBuffer = new ArrayBuffer(44 + result.length * bytesPerSample);
				const view = new DataView(wavBuffer);
				
				function writeString(view, offset, string) {
					for (let i = 0; i < string.length; i++) {
						view.setUint8(offset + i, string.charCodeAt(i));
					}
				}
				
				writeString(view, 0, 'RIFF');
				view.setUint32(4, 36 + result.length * bytesPerSample, true);
				writeString(view, 8, 'WAVE');
				writeString(view, 12, 'fmt ');
				view.setUint32(16, 16, true);
				view.setUint16(20, format, true);
				view.setUint16(22, numChannels, true);
				view.setUint32(24, sampleRate, true);
				view.setUint32(28, sampleRate * blockAlign, true);
				view.setUint16(32, blockAlign, true);
				view.setUint16(34, bitDepth, true);
				writeString(view, 36, 'data');
				view.setUint32(40, result.length * bytesPerSample, true);
				
				let offset = 44;
				for (let i = 0; i < result.length; i++, offset += bytesPerSample) {
					let s = Math.max(-1, Math.min(1, result[i]));
					view.setInt16(offset, s < 0 ? s * 0x8000 : s * 0x7FFF, true);
				}
				return wavBuffer;
			}

			window.downloadLastAudioWav = async function(customFilename = null) {
				if (!customFilename) customFilename = window.spyData.lastClickedFilename || window.spyData.fileName;
				const btn = document.getElementById('splice-spy-btn-wav');
				const flash = (ok) => {
					if (!btn) return;
					const old = btn.innerHTML;
					btn.innerHTML = ok ? '<span>Saved!</span>' : '<span>Error!</span>';
					setTimeout(() => btn.innerHTML = old, 2000);
				};

				// Prefer real MIDI/preset source file when available
				if (window.spyData.fileBuffer || window.spyData.assetSourceUrl) {
					try {
						let buffer = window.spyData.fileBuffer;
						if (!buffer && window.spyData.assetSourceUrl) {
							const res = await fetch(window.spyData.assetSourceUrl);
							if (!res.ok) throw new Error(`HTTP ${res.status}`);
							buffer = await res.arrayBuffer();
							window.spyData.fileBuffer = buffer;
						}
						const filename = customFilename || window.spyData.fileName || `asset_${Date.now()}`;
						const fullPath = require('path').join(getPackName(), filename);
						console.log(`[Spy] Saving selected ${window.spyData.assetType} file: ${fullPath}`);
						const result = await saveBinaryFile(fullPath, buffer);
						flash(result && result.success);
						return;
					} catch (err) {
						console.error('[Spy] Selected file download failed:', err);
						flash(false);
						return;
					}
				}

				console.log('[Spy] downloadLastAudioWav triggered.', { customFilename, hasAudioBuffer: !!window.spyData.audioBuffer });
				
				if (!window.spyData.audioBuffer) {
					console.error('[Spy] Cannot download: no source file or audioBuffer available.');
					flash(false);
					return;
				}
				
				const wavBuffer = audioBufferToWav(window.spyData.audioBuffer);
				const filename = toWavFilename(customFilename || 'audio');
				const fullPath = require('path').join(getPackName(), filename);
				
				console.log(`[Spy] Attempting to save individual WAV: ${fullPath}, Buffer size: ${wavBuffer.byteLength}`);
				const result = await saveBinaryFile(fullPath, wavBuffer);
				console.log(`[Spy] IPC Save result:`, result);
				flash(result && result.success);
			};

			function clampPageCount() {
				const pages = document.getElementById('splice-get-pack-pages');
				if (!pages) return;
				pages.value = String(Math.max(1, parseInt(pages.value, 10) || 1));
			}

			function adjustPageCount(delta) {
				const pages = document.getElementById('splice-get-pack-pages');
				if (!pages) return;
				pages.value = String(Math.max(1, (parseInt(pages.value, 10) || 1) + delta));
			}

			function injectButton() {
				if (document.getElementById('splice-spy-btn')) return;
				const container = document.createElement('div');
				container.id = 'splice-spy-container';
				Object.assign(container.style, { position: 'fixed', bottom: '82px', right: '22px', zIndex: '999999' });
				
				const infoBtn = document.createElement('button');
				infoBtn.innerHTML = '<svg width="18" height="18" viewBox="0 0 18 18" fill="none" stroke="currentColor"><rect x="3" y="3" width="12" height="12" rx="2" /><path d="M11 9h2M10 6h3M10 12h3M5 12l3-3-3-3" /></svg>';
				Object.assign(infoBtn.style, { background: 'none', border: 'none', cursor: 'pointer', color: 'rgba(255,255,255,0.5)', display: 'flex', alignItems: 'center' });
				infoBtn.onclick = () => require('electron').ipcRenderer.send('antigravity-toggle-devtools');

				const btnWav = document.createElement('button');
				btnWav.id = 'splice-spy-btn-wav';
				btnWav.className = 'spy-btn-class spy-d-none';
				btnWav.style.backgroundColor = '#8B5CF6';
				btnWav.innerHTML = `${ICON_DOWNLOAD} <span>Selected</span> <div class="spy-spinner"></div>`;
				btnWav.onclick = () => window.downloadLastAudioWav();

				const btn = document.createElement('button');
				btn.id = 'splice-spy-btn';
				btn.className = 'spy-btn-class spy-d-none';
				btn.innerHTML = `${ICON_DOWNLOAD} <span>Selected</span> <div class="spy-spinner"></div>`;
				btn.onclick = () => window.downloadLastAudio();

				const wrapper = document.createElement('div');
				wrapper.className = 'splice-get-pack-btn-wrapper';

				const packBtn = document.createElement('div');
				packBtn.id = 'splice-get-pack-btn';

				const action = document.createElement('button');
				action.type = 'button';
				action.id = 'splice-get-pack-action';
				action.innerHTML = `${ICON_DOWNLOAD} <span>Pages</span>`;
				action.onclick = () => window.getPack();

				const stepper = document.createElement('div');
				stepper.className = 'spy-page-stepper';
				stepper.title = 'Pages to download';

				const pageInput = document.createElement('input');
				pageInput.type = 'number';
				pageInput.id = 'splice-get-pack-pages';
				pageInput.value = '1';
				pageInput.min = '1';
				pageInput.addEventListener('change', clampPageCount);
				pageInput.addEventListener('blur', clampPageCount);

				const arrows = document.createElement('div');
				arrows.className = 'spy-page-arrows';

				const upBtn = document.createElement('button');
				upBtn.type = 'button';
				upBtn.setAttribute('aria-label', 'Increase pages');
				upBtn.innerHTML = ICON_CHEVRON_UP;
				upBtn.onclick = (e) => { e.preventDefault(); e.stopPropagation(); adjustPageCount(1); };

				const downBtn = document.createElement('button');
				downBtn.type = 'button';
				downBtn.setAttribute('aria-label', 'Decrease pages');
				downBtn.innerHTML = ICON_CHEVRON_DOWN;
				downBtn.onclick = (e) => { e.preventDefault(); e.stopPropagation(); adjustPageCount(-1); };

				arrows.append(upBtn, downBtn);
				stepper.append(pageInput, arrows);
				packBtn.append(action, stepper);
				wrapper.appendChild(packBtn);

				container.append(wrapper, btn, btnWav, infoBtn);
				document.body.appendChild(container);
				renderButton();

				require('electron').ipcRenderer.on('antigravity-devtools-state', (e, open) => {
					infoBtn.style.color = open ? '#aaff00' : 'rgba(255,255,255,0.5)';
				});
			}
			if (document.body) injectButton(); else document.addEventListener('DOMContentLoaded', injectButton);

			const FILE_URL_RE = /\.(mp3|wav|m4a|aac|aiff|flac|mid|midi|serumpreset|fxp)(\?|$)/i;
			function ingestNetworkPayload(reqUrl, bodyText) {
				if (!bodyText || typeof bodyText !== 'string') return;
				const url = (reqUrl || '').toLowerCase();
				if (!(url.includes('graphql') || bodyText.includes('assetsSearch') || bodyText.includes('PresetAsset') || bodyText.includes('asset_file_type_slug'))) return;
				try {
					const data = JSON.parse(bodyText);
					const before = window.spyAssetCache.size;
					walkGraphqlForAssets(data);
					console.log('[Spy Debug] Ingested network JSON', reqUrl, 'cache', before, '->', window.spyAssetCache.size);
				} catch (err) {
					console.warn('[Spy Debug] Failed to parse network JSON', reqUrl, err);
				}
			}

			const originalFetch = window.fetch;
			window.fetch = async (...args) => {
				const reqUrl = args[0]?.url || args[0]?.toString() || '';
				const url = reqUrl.toLowerCase();
				if (url.match(/\.(mp3|wav|m4a|aac|aiff|flac)(\?|$)/)) {
					if (window.spyData.state !== SpyState.READY) updateState(SpyState.LOADING);
				}
				const response = await originalFetch.apply(window, args);
				try {
					const clone = response.clone();
					const contentType = (clone.headers.get('content-type') || '').toLowerCase();
					if (contentType.includes('json') || url.includes('graphql')) {
						clone.text().then(text => ingestNetworkPayload(reqUrl, text)).catch(err => console.warn('[Spy Debug] fetch body read failed', err));
					} else if (FILE_URL_RE.test(url) || /midi|serumpreset|octet-stream/i.test(contentType)) {
						clone.arrayBuffer().then(buf => {
							const nameFromUrl = decodeURIComponent((reqUrl.split('?')[0].split('/').pop() || ''));
							if (!nameFromUrl) return;
							const kind = getAssetKind(nameFromUrl);
							if (kind === 'midi' || kind === 'preset') {
								cacheAssetFromGraphql({
									name: nameFromUrl,
									asset_type_slug: kind,
									files: [{ name: nameFromUrl, url: reqUrl, asset_file_type_slug: 'source' }]
								});
								if (window.spyData.fileName && normalizeAssetKey(window.spyData.fileName) === normalizeAssetKey(nameFromUrl)) {
									window.spyData.fileBuffer = buf;
									window.spyData.assetSourceUrl = reqUrl;
									window.spyData.assetType = kind;
									updateState(SpyState.READY, { buffer: window.spyData.buffer, audioBuffer: window.spyData.audioBuffer, ext: kind });
								}
							}
						}).catch(() => {});
					}
				} catch (_) {}
				return response;
			};

			// Apollo/Angular may use XHR instead of fetch
			(function hookXHR() {
				const open = XMLHttpRequest.prototype.open;
				const send = XMLHttpRequest.prototype.send;
				XMLHttpRequest.prototype.open = function(method, url, ...rest) {
					this.__spyUrl = url?.toString?.() || '';
					return open.call(this, method, url, ...rest);
				};
				XMLHttpRequest.prototype.send = function(...args) {
					this.addEventListener('load', () => {
						try {
							if (this.responseType && this.responseType !== '' && this.responseType !== 'text' && this.responseType !== 'json') return;
							const text = typeof this.response === 'string' ? this.response : this.responseText;
							ingestNetworkPayload(this.__spyUrl, text);
						} catch (_) {}
					});
					return send.apply(this, args);
				};
				console.log('[Spy Debug] XHR hook installed');
			})();

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
				if (this.buffer?._spyOriginalData) updateState(SpyState.READY, { buffer: this.buffer._spyOriginalData, audioBuffer: this.buffer });
				return originalStart.apply(this, args);
			};
		</script>
EOF
    # Insert script after <head> using node for portability
    node -e "const fs = require('fs'); const script = fs.readFileSync('script.tmp', 'utf8'); const p = process.argv[1]; let html = fs.readFileSync(p, 'utf8'); fs.writeFileSync(p, html.replace('<head>', '<head>\n' + script));" "$INDEX_HTML"
    rm script.tmp
    echo -e "${GREEN}✓ index.html patched${NC}"
fi

echo -e "\n${GREEN}Modification Complete!${NC}"
echo -e "${CYAN}Note: Your original app.asar has been renamed to app.asar.bak for safety.${NC}"

if [ "$REOPEN_SPLICE" = "1" ] && [[ "$TARGET_PATH" == *.app ]]; then
    echo -e "${CYAN}Reopening Splice...${NC}"
    open "$TARGET_PATH"
    echo -e "${GREEN}✓ Splice relaunched${NC}"
else
    echo -e "${YELLOW}Please restart Splice to see the changes.${NC}"
fi
