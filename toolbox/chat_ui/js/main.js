/**
 * Claude Code MATLAB Integration - Main JavaScript Entry Point
 *
 * This file implements the required setup() function for MATLAB's uihtml component
 * and manages bidirectional communication between JavaScript and MATLAB.
 */

// Global reference to MATLAB bridge
window.matlabBridge = null;

// Chat state
window.chatState = {
    messages: [],
    isStreaming: false,
    sessionId: null,
    currentStreamMessage: null
};

/**
 * Required setup function called by MATLAB's uihtml component
 * @param {Object} htmlComponent - The MATLAB HTML component interface
 */
function setup(htmlComponent) {
    try {
        // Store reference globally
        window.matlabBridge = htmlComponent;

        // Listen for events from MATLAB via sendEventToHTMLSource
        // These are custom events with the event name as the type
        htmlComponent.addEventListener('showMessage', handleShowMessage);
        htmlComponent.addEventListener('startStreaming', handleStartStreaming);
        htmlComponent.addEventListener('streamChunk', handleStreamChunk);
        htmlComponent.addEventListener('endStreaming', handleEndStreaming);
        htmlComponent.addEventListener('showError', handleShowError);
        htmlComponent.addEventListener('updateStatus', handleUpdateStatus);
        htmlComponent.addEventListener('codeResult', handleCodeResult);
        htmlComponent.addEventListener('showImage', handleShowImage);
        htmlComponent.addEventListener('setTheme', handleSetTheme);
        htmlComponent.addEventListener('loadSettings', handleLoadSettings);
        htmlComponent.addEventListener('statusBarUpdate', handleStatusBarUpdate);

        // Initialize UI event handlers
        initializeUI();

        // Initialize session timer for status bar
        initSessionTimer();

        // Show welcome message
        showWelcomeMessage();

        // Notify MATLAB that UI is ready
        htmlComponent.sendEventToMATLAB('uiReady', {
            timestamp: Date.now()
        });
    } catch (err) {
        // Log any setup errors - this helps debug MATLAB uihtml warnings
        console.error('setup() error:', err.message, err.stack);
    }
}

/**
 * Handle showMessage event from MATLAB
 */
function handleShowMessage(event) {
    const data = event.Data;
    if (data.role === 'user') {
        addUserMessage(data.content);
    } else if (data.role === 'assistant') {
        addAssistantMessage(data.content, true);
    } else if (data.role === 'error') {
        showError(data.content);
    }
}

/**
 * Handle startStreaming event from MATLAB
 */
function handleStartStreaming(event) {
    setStreamingState(true);
    startStreamingMessage();
}

/**
 * Handle streamChunk event from MATLAB
 */
function handleStreamChunk(event) {
    const data = event.Data;
    appendToStreamingMessage(data.text);
}

/**
 * Handle endStreaming event from MATLAB
 */
function handleEndStreaming(event) {
    finalizeStreamingMessage();
    setStreamingState(false);
}

/**
 * Handle showError event from MATLAB
 */
function handleShowError(event) {
    const data = event.Data;
    showError(data.message);
    setStreamingState(false);
}

/**
 * Handle updateStatus event from MATLAB
 */
function handleUpdateStatus(event) {
    const data = event.Data;
    updateStatus(data.status, data.message);
}

/**
 * Handle codeResult event from MATLAB
 */
function handleCodeResult(event) {
    const data = event.Data;
    showCodeResult(data.blockId, data.output, !data.success);
}

/**
 * Handle showImage event from MATLAB
 */
function handleShowImage(event) {
    const data = event.Data;
    appendImageToStreamingMessage(data);
}

/**
 * Initialize UI event handlers
 */
function initializeUI() {
    // Send button
    const sendBtn = document.getElementById('send-btn');
    sendBtn.addEventListener('click', sendMessage);

    // Clear button
    const clearBtn = document.getElementById('clear-btn');
    clearBtn.addEventListener('click', clearChat);

    // Text input
    const userInput = document.getElementById('user-input');
    userInput.addEventListener('keydown', handleKeyDown);

    // Auto-resize textarea
    userInput.addEventListener('input', autoResizeTextarea);

    // Initialize settings manager
    SettingsManager.init();
}

/**
 * Clear the chat history and reset conversation
 */
function clearChat() {
    // Don't allow clearing while streaming
    if (window.chatState.isStreaming) {
        return;
    }

    // Clear message history in UI
    const history = document.getElementById('message-history');
    history.innerHTML = '';

    // Reset local state
    window.chatState.messages = [];
    window.chatState.currentStreamMessage = null;

    // Show welcome message again
    showWelcomeMessage();

    // Notify MATLAB to clear Python conversation state
    if (window.matlabBridge) {
        window.matlabBridge.sendEventToMATLAB('clearChat', {
            timestamp: Date.now()
        });
    }
}

/**
 * Handle keyboard events in the input field
 * @param {KeyboardEvent} event
 */
function handleKeyDown(event) {
    // Enter to send, Shift+Enter for new line
    if (event.key === 'Enter' && !event.shiftKey) {
        event.preventDefault();
        sendMessage();
    }
}

/**
 * Auto-resize textarea based on content
 */
function autoResizeTextarea() {
    const textarea = document.getElementById('user-input');
    textarea.style.height = 'auto';
    textarea.style.height = Math.min(textarea.scrollHeight, 200) + 'px';
}

/**
 * Send a message to Claude via MATLAB
 */
function sendMessage() {
    const input = document.getElementById('user-input');
    const message = input.value.trim();

    if (!message || window.chatState.isStreaming) {
        return;
    }

    // Clear input
    input.value = '';
    input.style.height = 'auto';

    // Set loading state
    setStreamingState(true);
    updateStatus('loading', 'Thinking...');

    // Send to MATLAB
    if (window.matlabBridge) {
        window.matlabBridge.sendEventToMATLAB('userMessage', {
            content: message,
            timestamp: Date.now()
        });
    }
}

/**
 * Update streaming state
 * @param {boolean} isStreaming
 */
function setStreamingState(isStreaming) {
    window.chatState.isStreaming = isStreaming;

    const sendBtn = document.getElementById('send-btn');
    sendBtn.disabled = isStreaming;

    const statusDot = document.getElementById('status-dot');
    if (isStreaming) {
        statusDot.classList.add('loading');
    } else {
        statusDot.classList.remove('loading');
        updateStatus('ready', 'Ready');
    }
}

/**
 * Update status indicator
 * @param {string} status - 'ready', 'loading', 'streaming', 'error'
 * @param {string} message - Status message
 */
function updateStatus(status, message) {
    const statusDot = document.getElementById('status-dot');
    const statusText = document.getElementById('status-text');

    statusDot.classList.remove('loading', 'error');

    if (status === 'loading' || status === 'streaming') {
        statusDot.classList.add('loading');
    } else if (status === 'error') {
        statusDot.classList.add('error');
    }

    statusText.textContent = message;
}

/**
 * Show error message
 * @param {string} message
 */
function showError(message) {
    updateStatus('error', 'Error');

    const history = document.getElementById('message-history');
    const errorDiv = document.createElement('div');
    errorDiv.className = 'error-message';
    errorDiv.textContent = message;
    history.appendChild(errorDiv);

    scrollToBottom();
}

/**
 * Show welcome message
 */
function showWelcomeMessage() {
    const history = document.getElementById('message-history');

    const welcome = document.createElement('div');
    welcome.className = 'welcome-message';
    welcome.innerHTML = `
        <h2>Welcome to Claude Code</h2>
        <p>Ask questions about your MATLAB code, get help with Simulink models, or request code changes.</p>
    `;

    history.appendChild(welcome);
}

/**
 * Scroll message history to bottom
 */
function scrollToBottom() {
    const history = document.getElementById('message-history');
    history.scrollTop = history.scrollHeight;
}

/**
 * Handle setTheme event from MATLAB
 * @param {Event} event - Contains theme data ('light' or 'dark')
 */
function handleSetTheme(event) {
    const data = event.Data;
    const theme = data.theme || 'light';
    setTheme(theme);
}

/**
 * Set the UI theme to match MATLAB
 * @param {string} theme - 'light' or 'dark'
 */
function setTheme(theme) {
    if (theme === 'dark') {
        document.documentElement.setAttribute('data-theme', 'dark');
    } else {
        document.documentElement.removeAttribute('data-theme');
    }
}

// ============================================================================
// Settings Manager
// ============================================================================

/**
 * SettingsManager handles the settings modal and communication with MATLAB
 */
const SettingsManager = {
    modal: null,
    isOpen: false,

    /**
     * Initialize settings manager - bind event listeners
     */
    init() {
        try {
            this.modal = document.getElementById('settings-modal');
            if (!this.modal) {
                console.error('SettingsManager: modal element not found');
                return;
            }

            // Settings button opens modal
            const settingsBtn = document.getElementById('settings-btn');
            if (settingsBtn) {
                settingsBtn.addEventListener('click', () => this.open());
            }

            // Close button (X in header)
            const closeBtn = document.getElementById('modal-close-btn');
            if (closeBtn) {
                closeBtn.addEventListener('click', () => this.close());
            }

            // Close on overlay click (outside modal)
            this.modal.addEventListener('click', (e) => {
                if (e.target === this.modal) {
                    this.close();
                }
            });

            // Close on Escape key
            document.addEventListener('keydown', (e) => {
                if (e.key === 'Escape' && this.isOpen) {
                    this.close();
                }
            });

            // Live-apply settings on change - use helper to safely bind
            this._bindChangeHandler('model-select');
            this._bindChangeHandler('theme-select');
            this._bindChangeHandler('execution-mode-select');
            this._bindChangeHandler('headless-mode-checkbox');
            this._bindChangeHandler('logging-enabled-checkbox');
            this._bindChangeHandler('log-level-select');
            this._bindChangeHandler('log-sensitive-checkbox');
        } catch (err) {
            console.error('SettingsManager.init error:', err);
        }
    },

    /**
     * Helper to safely bind change handlers
     */
    _bindChangeHandler(elementId) {
        const el = document.getElementById(elementId);
        if (el) {
            el.addEventListener('change', () => this.applySettings());
        }
    },

    /**
     * Open the settings modal and request current settings from MATLAB
     */
    open() {
        try {
            if (this.isOpen || !this.modal) return;

            this.modal.style.display = 'flex';
            this.isOpen = true;

            // Request current settings from MATLAB
            if (window.matlabBridge) {
                window.matlabBridge.sendEventToMATLAB('requestSettings', {
                    timestamp: Date.now()
                });
            }
        } catch (err) {
            console.error('SettingsManager.open error:', err);
        }
    },

    /**
     * Close the settings modal
     */
    close() {
        try {
            if (this.modal) {
                this.modal.style.display = 'none';
            }
            this.isOpen = false;
        } catch (err) {
            console.error('SettingsManager.close error:', err);
        }
    },

    /**
     * Load settings into the form from MATLAB response
     * @param {Object} settings - Settings object from MATLAB
     */
    loadSettings(settings) {
        try {
            if (!settings || typeof settings !== 'object') {
                console.warn('SettingsManager.loadSettings: invalid settings object');
                return;
            }

            // Model selection
            const modelSelect = document.getElementById('model-select');
            if (modelSelect && settings.model) {
                modelSelect.value = settings.model;
            }

            // Theme selection
            const themeSelect = document.getElementById('theme-select');
            if (themeSelect && settings.theme) {
                themeSelect.value = settings.theme;
            }

            // Code execution mode
            const executionSelect = document.getElementById('execution-mode-select');
            if (executionSelect && settings.codeExecutionMode) {
                executionSelect.value = settings.codeExecutionMode;
            }

            // Headless mode (default to true/checked)
            const headlessCheckbox = document.getElementById('headless-mode-checkbox');
            if (headlessCheckbox) {
                headlessCheckbox.checked = settings.headlessMode !== false;
            }

            // Logging settings
            const loggingCheckbox = document.getElementById('logging-enabled-checkbox');
            if (loggingCheckbox) {
                loggingCheckbox.checked = settings.loggingEnabled !== false;
            }

            const logLevelSelect = document.getElementById('log-level-select');
            if (logLevelSelect && settings.logLevel) {
                logLevelSelect.value = settings.logLevel;
            }

            const logSensitiveCheckbox = document.getElementById('log-sensitive-checkbox');
            if (logSensitiveCheckbox) {
                logSensitiveCheckbox.checked = settings.logSensitiveData !== false;
            }
        } catch (err) {
            console.error('SettingsManager.loadSettings error:', err);
        }
    },

    /**
     * Apply settings immediately - called on any form element change
     */
    applySettings() {
        try {
            // Get elements with null checks (avoid optional chaining for MATLAB compatibility)
            const modelEl = document.getElementById('model-select');
            const themeEl = document.getElementById('theme-select');
            const execEl = document.getElementById('execution-mode-select');
            const headlessEl = document.getElementById('headless-mode-checkbox');
            const loggingEl = document.getElementById('logging-enabled-checkbox');
            const logLevelEl = document.getElementById('log-level-select');
            const logSensitiveEl = document.getElementById('log-sensitive-checkbox');

            const settings = {
                model: modelEl ? modelEl.value : 'claude-sonnet-4-5-20250514',
                theme: themeEl ? themeEl.value : 'dark',
                codeExecutionMode: execEl ? execEl.value : 'prompt',
                headlessMode: headlessEl ? headlessEl.checked : true,
                loggingEnabled: loggingEl ? loggingEl.checked : true,
                logLevel: logLevelEl ? logLevelEl.value : 'INFO',
                logSensitiveData: logSensitiveEl ? logSensitiveEl.checked : true
            };

            // Apply theme immediately
            setTheme(settings.theme);

            // Send to MATLAB for persistence
            if (window.matlabBridge) {
                window.matlabBridge.sendEventToMATLAB('saveSettings', settings);
            }
        } catch (err) {
            console.error('SettingsManager.applySettings error:', err);
        }
    }
};

/**
 * Handle loadSettings event from MATLAB
 * @param {Event} event - Contains settings data
 */
function handleLoadSettings(event) {
    try {
        const data = event && event.Data ? event.Data : {};
        SettingsManager.loadSettings(data);
    } catch (err) {
        console.error('handleLoadSettings error:', err);
    }
}

// ============================================================================
// Status Bar
// ============================================================================

/**
 * Initialize session timer for status bar
 */
function initSessionTimer() {
    // Record session start time
    window.sessionStartTime = Date.now();

    // Update time immediately
    updateSessionTime();

    // Update every minute
    setInterval(updateSessionTime, 60000);
}

/**
 * Update session time display in status bar
 */
function updateSessionTime() {
    try {
        if (!window.sessionStartTime) return;

        var elapsedMs = Date.now() - window.sessionStartTime;
        var elapsedMinutes = Math.floor(elapsedMs / 60000);

        var timeEl = document.getElementById('sb-time');
        if (timeEl) {
            if (elapsedMinutes < 60) {
                timeEl.textContent = elapsedMinutes + 'm';
            } else {
                var hours = Math.floor(elapsedMinutes / 60);
                var mins = elapsedMinutes % 60;
                timeEl.textContent = hours + 'h ' + mins + 'm';
            }
        }
    } catch (err) {
        console.error('updateSessionTime error:', err);
    }
}

/**
 * Handle statusBarUpdate event from MATLAB
 * @param {Event} event - Contains status bar data
 */
function handleStatusBarUpdate(event) {
    try {
        var data = event && event.Data ? event.Data : {};

        // Update model name
        if (data.model !== undefined) {
            var modelEl = document.getElementById('sb-model');
            if (modelEl) {
                modelEl.textContent = data.model;
            }
        }

        // Update project name
        if (data.project !== undefined) {
            var projectEl = document.getElementById('sb-project');
            if (projectEl) {
                projectEl.textContent = data.project;
            }
        }

        // Update branch name
        if (data.branch !== undefined) {
            var branchEl = document.getElementById('sb-branch');
            if (branchEl) {
                branchEl.textContent = data.branch;
            }
        }

        // Update diff stats
        if (data.additions !== undefined || data.deletions !== undefined) {
            var additionsEl = document.querySelector('#sb-diff .sb-additions');
            var deletionsEl = document.querySelector('#sb-diff .sb-deletions');
            if (additionsEl && data.additions !== undefined) {
                additionsEl.textContent = '+' + data.additions;
            }
            if (deletionsEl && data.deletions !== undefined) {
                deletionsEl.textContent = '-' + data.deletions;
            }
        }

        // Update token count
        if (data.tokens !== undefined) {
            var tokensEl = document.getElementById('sb-tokens');
            if (tokensEl) {
                // Format large numbers with k suffix
                var tokenCount = data.tokens;
                if (tokenCount >= 1000) {
                    tokensEl.textContent = (tokenCount / 1000).toFixed(1) + 'k tokens';
                } else {
                    tokensEl.textContent = tokenCount + ' tokens';
                }
            }
        }
    } catch (err) {
        console.error('handleStatusBarUpdate error:', err);
    }
}
