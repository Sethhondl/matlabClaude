/**
 * Derivux MATLAB Integration - Main JavaScript Entry Point
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
    currentStreamMessage: null,
    initiatingTabId: null  // Tab that initiated current async request
};

// Interrupt state for double-ESC detection
window.interruptState = {
    lastEscTime: 0,
    THRESHOLD_MS: 1000,  // 1 second window for double-ESC
    hintTimeout: null
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
        htmlComponent.addEventListener('authStatusUpdate', handleAuthStatusUpdate);
        htmlComponent.addEventListener('apiKeyValidationResult', handleApiKeyValidationResult);
        htmlComponent.addEventListener('cliLoginResult', handleCliLoginResult);
        htmlComponent.addEventListener('tabStatusUpdate', handleTabStatusUpdate);
        htmlComponent.addEventListener('interruptComplete', handleInterruptComplete);

        // Initialize UI event handlers
        initializeUI();

        // Initialize tab manager for multi-session support
        TabManager.init();

        // Initialize session timer for status bar
        initSessionTimer();

        // Note: Welcome message is shown by TabManager.init() when creating the first tab

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

    // Use initiating tab, not active tab (for session isolation)
    var initiatingTabId = window.chatState.initiatingTabId || TabManager.getActiveTabId();
    var activeTabId = TabManager.getActiveTabId();

    // Only start visible streaming if we're on the initiating tab
    if (initiatingTabId === activeTabId) {
        startStreamingMessage();
    } else {
        // Mark background tab as streaming
        TabManager.startBackgroundStreaming(initiatingTabId);
    }

    // Update initiating tab's status to working
    if (initiatingTabId) {
        TabManager.updateTabStatus(initiatingTabId, 'working');
        TabManager.saveStreamingState();
    }
}

/**
 * Handle streamChunk event from MATLAB
 */
function handleStreamChunk(event) {
    var data = event.Data;

    // Use initiating tab for session isolation
    var initiatingTabId = window.chatState.initiatingTabId;
    var activeTabId = TabManager.getActiveTabId();

    if (!initiatingTabId || initiatingTabId === activeTabId) {
        // We're on the initiating tab - append to visible streaming message
        appendToStreamingMessage(data.text);
    } else {
        // We've switched to a different tab - store in initiating tab's background state
        TabManager.appendToBackgroundTab(initiatingTabId, data.text);
    }

    // Save streaming state to the appropriate tab
    TabManager.saveStreamingState();
}

/**
 * Handle endStreaming event from MATLAB
 */
function handleEndStreaming(event) {
    // Use initiating tab for session isolation
    var initiatingTabId = window.chatState.initiatingTabId;
    var activeTabId = TabManager.getActiveTabId();

    if (!initiatingTabId || initiatingTabId === activeTabId) {
        // We're on the initiating tab - finalize visible streaming message
        finalizeStreamingMessage();
    } else {
        // We've switched to a different tab - finalize in background tab's state
        TabManager.finalizeBackgroundTab(initiatingTabId);
    }

    setStreamingState(false);

    // Reset interrupt manager state
    InterruptManager.reset();

    // Update initiating tab's status to ready
    if (initiatingTabId) {
        TabManager.updateTabStatus(initiatingTabId, 'ready');
        TabManager.saveStreamingState();
    }

    // Clear initiating tab ID after completion
    window.chatState.initiatingTabId = null;
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

    // Initialize authentication manager
    AuthManager.init();

    // Initialize execution mode manager
    ExecutionModeManager.init();

    // Initialize interrupt manager for double-ESC detection
    InterruptManager.init();

    // Global keyboard shortcut: Backtick (`) to cycle execution modes
    document.addEventListener('keydown', function(event) {
        // Only trigger on backtick key
        if (event.key !== '`') return;

        // Don't trigger if user is typing in an input/textarea
        var activeTag = document.activeElement.tagName.toLowerCase();
        if (activeTag === 'input' || activeTag === 'textarea') return;

        // Don't trigger if a modal is open
        if (SettingsManager.isOpen) return;

        event.preventDefault();
        ExecutionModeManager.cycleMode();
    });
}

/**
 * Clear the chat history and reset conversation
 */
function clearChat() {
    // Don't allow clearing while streaming
    if (window.chatState.isStreaming) {
        return;
    }

    // Use TabManager to clear the active tab
    var activeTabId = TabManager.getActiveTabId();
    if (activeTabId) {
        TabManager._clearTabContent(activeTabId);
    } else {
        // Fallback: direct clear (shouldn't happen)
        var history = document.getElementById('message-history');
        history.innerHTML = '';
        window.chatState.messages = [];
        window.chatState.currentStreamMessage = null;
        showWelcomeMessage();

        if (window.matlabBridge) {
            window.matlabBridge.sendEventToMATLAB('clearChat', {
                timestamp: Date.now()
            });
        }
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

    // Capture which tab initiated this request (before any state changes)
    var initiatingTabId = TabManager.getActiveTabId();
    window.chatState.initiatingTabId = initiatingTabId;

    // Set loading state
    setStreamingState(true);
    updateStatus('loading', 'Thinking...');

    // Send to MATLAB with initiating tab ID
    if (window.matlabBridge) {
        window.matlabBridge.sendEventToMATLAB('userMessage', {
            content: message,
            tabId: initiatingTabId,
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
        <h2>Welcome to Derivux</h2>
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
            this._bindChangeHandler('headless-mode-checkbox');
            this._bindChangeHandler('logging-enabled-checkbox');
            this._bindChangeHandler('log-level-select');
            this._bindChangeHandler('log-sensitive-checkbox');

            // Special handler for bypass cycling checkbox - shows warning when enabled
            this._bindBypassCyclingCheckbox();
        } catch (err) {
            console.error('SettingsManager.init error:', err);
        }
    },

    /**
     * Bind special handler for bypass cycling checkbox with warning
     */
    _bindBypassCyclingCheckbox() {
        var checkbox = document.getElementById('allow-bypass-cycling-checkbox');
        if (checkbox) {
            checkbox.addEventListener('change', function() {
                if (checkbox.checked) {
                    // Show warning when enabling
                    var confirmed = confirm(
                        '⚠️ WARNING: Enable Bypass Mode Cycling\n\n' +
                        'You are about to allow cycling to Bypass mode.\n\n' +
                        'Bypass mode removes ALL safety restrictions:\n' +
                        '• No approval prompts before code execution\n' +
                        '• Blocked functions (eval, delete, system) are ALLOWED\n' +
                        '• Destructive operations are permitted\n\n' +
                        'Only enable this if you understand the risks.\n\n' +
                        'Are you sure you want to allow bypass mode cycling?'
                    );
                    if (!confirmed) {
                        checkbox.checked = false;
                        return;
                    }
                }
                SettingsManager.applySettings();
            });
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

            // Allow bypass mode cycling (default to false for safety)
            const bypassCyclingCheckbox = document.getElementById('allow-bypass-cycling-checkbox');
            if (bypassCyclingCheckbox) {
                bypassCyclingCheckbox.checked = settings.allowBypassModeCycling === true;
            }

            // Update ExecutionModeManager with the bypass cycling setting
            ExecutionModeManager.setBypassCyclingAllowed(settings.allowBypassModeCycling === true);
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
            const headlessEl = document.getElementById('headless-mode-checkbox');
            const loggingEl = document.getElementById('logging-enabled-checkbox');
            const logLevelEl = document.getElementById('log-level-select');
            const logSensitiveEl = document.getElementById('log-sensitive-checkbox');

            // Get bypass cycling checkbox
            var bypassCyclingEl = document.getElementById('allow-bypass-cycling-checkbox');
            var allowBypassCycling = bypassCyclingEl ? bypassCyclingEl.checked : false;

            const settings = {
                model: modelEl ? modelEl.value : 'claude-sonnet-4-5-20250514',
                theme: themeEl ? themeEl.value : 'dark',
                codeExecutionMode: ExecutionModeManager.getCurrentMode(),
                headlessMode: headlessEl ? headlessEl.checked : true,
                loggingEnabled: loggingEl ? loggingEl.checked : true,
                logLevel: logLevelEl ? logLevelEl.value : 'INFO',
                logSensitiveData: logSensitiveEl ? logSensitiveEl.checked : true,
                allowBypassModeCycling: allowBypassCycling
            };

            // Update ExecutionModeManager with the bypass cycling setting
            ExecutionModeManager.setBypassCyclingAllowed(allowBypassCycling);

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
        AuthManager.loadAuthSettings(data);

        // Load execution mode from settings
        if (data.codeExecutionMode) {
            ExecutionModeManager.loadMode(data.codeExecutionMode);
        }
    } catch (err) {
        console.error('handleLoadSettings error:', err);
    }
}

// ============================================================================
// Authentication Manager
// ============================================================================

/**
 * AuthManager handles authentication tab, method selection, and API key management
 */
const AuthManager = {
    currentMethod: 'api_key',

    /**
     * Initialize authentication manager
     */
    init() {
        try {
            // Tab switching
            this._initTabs();

            // Auth method radio buttons
            this._initAuthMethodSelection();

            // API key controls
            this._initApiKeyControls();

            // Subscription controls
            this._initSubscriptionControls();

        } catch (err) {
            console.error('AuthManager.init error:', err);
        }
    },

    /**
     * Initialize tab switching functionality
     */
    _initTabs() {
        var tabs = document.querySelectorAll('.settings-tab');
        for (var i = 0; i < tabs.length; i++) {
            tabs[i].addEventListener('click', function(e) {
                var tabName = e.target.getAttribute('data-tab');
                AuthManager._switchTab(tabName);
            });
        }
    },

    /**
     * Switch to a specific tab
     */
    _switchTab(tabName) {
        // Update tab buttons
        var tabs = document.querySelectorAll('.settings-tab');
        for (var i = 0; i < tabs.length; i++) {
            if (tabs[i].getAttribute('data-tab') === tabName) {
                tabs[i].classList.add('active');
            } else {
                tabs[i].classList.remove('active');
            }
        }

        // Update tab content
        var contents = document.querySelectorAll('.settings-tab-content');
        for (var j = 0; j < contents.length; j++) {
            if (contents[j].id === 'tab-' + tabName) {
                contents[j].classList.add('active');
            } else {
                contents[j].classList.remove('active');
            }
        }

        // If switching to auth tab, refresh status
        if (tabName === 'authentication') {
            this.refreshAuthStatus();
        }
    },

    /**
     * Initialize auth method radio button selection
     */
    _initAuthMethodSelection() {
        var radios = document.querySelectorAll('input[name="auth-method"]');
        for (var i = 0; i < radios.length; i++) {
            radios[i].addEventListener('change', function(e) {
                AuthManager._onAuthMethodChange(e.target.value);
            });
        }
    },

    /**
     * Handle auth method change
     */
    _onAuthMethodChange(method) {
        this.currentMethod = method;

        // Show/hide appropriate sections
        var subSection = document.getElementById('auth-subscription-section');
        var apiSection = document.getElementById('auth-apikey-section');

        if (method === 'subscription') {
            if (subSection) subSection.style.display = 'block';
            if (apiSection) apiSection.style.display = 'none';
        } else {
            if (subSection) subSection.style.display = 'none';
            if (apiSection) apiSection.style.display = 'block';
        }

        // Save to MATLAB
        this._saveAuthMethod(method);
    },

    /**
     * Initialize API key controls
     */
    _initApiKeyControls() {
        // Toggle visibility button
        var toggleBtn = document.getElementById('toggle-key-visibility');
        if (toggleBtn) {
            toggleBtn.addEventListener('click', function() {
                var input = document.getElementById('api-key-input');
                if (input) {
                    if (input.type === 'password') {
                        input.type = 'text';
                    } else {
                        input.type = 'password';
                    }
                }
            });
        }

        // Validate button
        var validateBtn = document.getElementById('validate-key-btn');
        if (validateBtn) {
            validateBtn.addEventListener('click', function() {
                AuthManager._validateApiKey();
            });
        }

        // Clear button
        var clearBtn = document.getElementById('clear-key-btn');
        if (clearBtn) {
            clearBtn.addEventListener('click', function() {
                AuthManager._clearApiKey();
            });
        }
    },

    /**
     * Initialize subscription controls
     */
    _initSubscriptionControls() {
        // Login button
        var loginBtn = document.getElementById('cli-login-btn');
        if (loginBtn) {
            loginBtn.addEventListener('click', function() {
                AuthManager._startCliLogin();
            });
        }

        // Check status button
        var checkBtn = document.getElementById('check-status-btn');
        if (checkBtn) {
            checkBtn.addEventListener('click', function() {
                AuthManager.refreshAuthStatus();
            });
        }
    },

    /**
     * Validate the entered API key
     */
    _validateApiKey() {
        var input = document.getElementById('api-key-input');
        if (!input || !input.value.trim()) {
            this._updateApiKeyStatus('error', 'Please enter an API key');
            return;
        }

        var apiKey = input.value.trim();

        // Update UI to show validating
        this._updateApiKeyStatus('loading', 'Validating...');

        // Send to MATLAB for validation and storage
        if (window.matlabBridge) {
            window.matlabBridge.sendEventToMATLAB('validateApiKey', {
                apiKey: apiKey,
                timestamp: Date.now()
            });
        }
    },

    /**
     * Clear the stored API key
     */
    _clearApiKey() {
        var input = document.getElementById('api-key-input');
        if (input) {
            input.value = '';
        }

        // Send to MATLAB to clear
        if (window.matlabBridge) {
            window.matlabBridge.sendEventToMATLAB('clearApiKey', {
                timestamp: Date.now()
            });
        }

        this._updateApiKeyStatus('none', 'No API key configured');
    },

    /**
     * Start CLI login process
     */
    _startCliLogin() {
        // Update UI - show we're checking/installing
        this._updateSubscriptionStatus('loading', 'Checking Claude CLI...');

        // Send to MATLAB
        if (window.matlabBridge) {
            window.matlabBridge.sendEventToMATLAB('cliLogin', {
                timestamp: Date.now()
            });
        }
    },

    /**
     * Save auth method to MATLAB
     */
    _saveAuthMethod(method) {
        if (window.matlabBridge) {
            window.matlabBridge.sendEventToMATLAB('setAuthMethod', {
                method: method,
                timestamp: Date.now()
            });
        }
    },

    /**
     * Refresh authentication status from MATLAB
     */
    refreshAuthStatus() {
        if (window.matlabBridge) {
            window.matlabBridge.sendEventToMATLAB('requestAuthStatus', {
                timestamp: Date.now()
            });
        }
    },

    /**
     * Load auth settings from MATLAB response
     */
    loadAuthSettings(settings) {
        if (!settings) return;

        // Set auth method
        if (settings.authMethod) {
            this.currentMethod = settings.authMethod;

            // Update radio buttons
            var radios = document.querySelectorAll('input[name="auth-method"]');
            for (var i = 0; i < radios.length; i++) {
                radios[i].checked = (radios[i].value === settings.authMethod);
            }

            // Show appropriate section
            this._onAuthMethodChange(settings.authMethod);
        }

        // Update API key status if provided
        if (settings.hasApiKey !== undefined) {
            if (settings.hasApiKey) {
                var maskedKey = settings.apiKeyMasked || '****';
                this._updateApiKeyStatus('success', 'API key configured: ' + maskedKey);

                // Set masked value in input
                var input = document.getElementById('api-key-input');
                if (input && settings.apiKeyMasked) {
                    input.value = settings.apiKeyMasked;
                }
            } else {
                this._updateApiKeyStatus('none', 'No API key configured');
            }
        }

        // Update subscription status if provided
        if (settings.cliAuthenticated !== undefined) {
            if (settings.cliAuthenticated) {
                var email = settings.cliEmail || '';
                var statusText = email ? 'Authenticated as ' + email : 'Authenticated via Claude CLI';
                this._updateSubscriptionStatus('success', statusText);
            } else {
                this._updateSubscriptionStatus('none', 'Not logged in. Click "Login with Claude" to authenticate.');
            }
        }
    },

    /**
     * Handle auth status update from MATLAB
     */
    handleAuthStatusUpdate(data) {
        if (!data) return;

        // Update subscription status
        if (data.cliAuthenticated !== undefined) {
            if (data.cliAuthenticated) {
                var email = data.cliEmail || '';
                var statusText = email ? 'Authenticated as ' + email : 'Authenticated via Claude CLI';
                this._updateSubscriptionStatus('success', statusText);
            } else {
                var message = data.cliMessage || 'Not logged in';
                this._updateSubscriptionStatus('none', message);
            }
        }

        // Update API key status
        if (data.hasApiKey !== undefined) {
            if (data.hasApiKey) {
                var masked = data.apiKeyMasked || '****';
                this._updateApiKeyStatus('success', 'API key configured: ' + masked);
            } else {
                this._updateApiKeyStatus('none', 'No API key configured');
            }
        }

        // Update status bar
        if (data.authMethod) {
            this._updateStatusBarAuth(data.authMethod);
        }
    },

    /**
     * Handle API key validation result
     */
    handleApiKeyValidationResult(data) {
        if (!data) return;

        if (data.valid) {
            this._updateApiKeyStatus('success', data.message || 'API key validated');
        } else {
            this._updateApiKeyStatus('error', data.message || 'Invalid API key');
        }
    },

    /**
     * Handle CLI login result
     */
    handleCliLoginResult(data) {
        if (!data) return;

        if (data.started) {
            // Show success status - browser should be opening
            if (data.installing) {
                this._updateSubscriptionStatus('success', data.message || 'Claude CLI installed! Completing authentication...');
            } else {
                this._updateSubscriptionStatus('loading', data.message || 'Please complete authentication in your browser...');
            }
        } else if (data.installing && !data.started) {
            // Still installing or checking
            this._updateSubscriptionStatus('loading', data.message || 'Installing Claude CLI...');
        } else {
            // Show error with the message (which may include installation instructions)
            this._updateSubscriptionStatus('error', data.message || 'Login failed');
        }
    },

    /**
     * Update subscription status display
     */
    _updateSubscriptionStatus(status, message) {
        var icon = document.getElementById('subscription-status-icon');
        var text = document.getElementById('subscription-status-text');

        if (icon) {
            icon.className = 'auth-status-icon';
            if (status === 'success') {
                icon.textContent = '\u2713';  // checkmark
                icon.classList.add('auth-status-success');
            } else if (status === 'error') {
                icon.textContent = '\u2717';  // X
                icon.classList.add('auth-status-error');
            } else if (status === 'loading') {
                icon.textContent = '\u21BB';  // circular arrow
                icon.classList.add('auth-status-loading');
            } else {
                icon.textContent = '-';
                icon.classList.add('auth-status-none');
            }
        }

        if (text) {
            text.textContent = message;
        }
    },

    /**
     * Update API key status display
     */
    _updateApiKeyStatus(status, message) {
        var icon = document.getElementById('apikey-status-icon');
        var text = document.getElementById('apikey-status-text');

        if (icon) {
            icon.className = 'auth-status-icon';
            if (status === 'success') {
                icon.textContent = '\u2713';  // checkmark
                icon.classList.add('auth-status-success');
            } else if (status === 'error') {
                icon.textContent = '\u2717';  // X
                icon.classList.add('auth-status-error');
            } else if (status === 'loading') {
                icon.textContent = '\u21BB';  // circular arrow
                icon.classList.add('auth-status-loading');
            } else {
                icon.textContent = '-';
                icon.classList.add('auth-status-none');
            }
        }

        if (text) {
            text.textContent = message;
        }
    },

    /**
     * Update status bar auth segment
     */
    _updateStatusBarAuth(method) {
        var authEl = document.getElementById('sb-auth');
        if (authEl) {
            authEl.classList.remove('sb-auth-sub', 'sb-auth-api');
            if (method === 'api_key') {
                authEl.textContent = 'API';
                authEl.classList.add('sb-auth-api');
            } else {
                authEl.textContent = 'Sub';
                authEl.classList.add('sb-auth-sub');
            }
        }
    }
};

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

        // Update auth method
        if (data.authMethod !== undefined) {
            var authEl = document.getElementById('sb-auth');
            if (authEl) {
                authEl.classList.remove('sb-auth-sub', 'sb-auth-api');
                if (data.authMethod === 'api_key') {
                    authEl.textContent = 'API';
                    authEl.classList.add('sb-auth-api');
                } else {
                    authEl.textContent = 'Sub';
                    authEl.classList.add('sb-auth-sub');
                }
            }
        }

        // Update execution mode
        if (data.executionMode !== undefined) {
            ExecutionModeManager.loadMode(data.executionMode);
        }
    } catch (err) {
        console.error('handleStatusBarUpdate error:', err);
    }
}

/**
 * Handle authStatusUpdate event from MATLAB
 * @param {Event} event - Contains auth status data
 */
function handleAuthStatusUpdate(event) {
    try {
        var data = event && event.Data ? event.Data : {};
        AuthManager.handleAuthStatusUpdate(data);
    } catch (err) {
        console.error('handleAuthStatusUpdate error:', err);
    }
}

/**
 * Handle apiKeyValidationResult event from MATLAB
 * @param {Event} event - Contains validation result data
 */
function handleApiKeyValidationResult(event) {
    try {
        var data = event && event.Data ? event.Data : {};
        AuthManager.handleApiKeyValidationResult(data);
    } catch (err) {
        console.error('handleApiKeyValidationResult error:', err);
    }
}

/**
 * Handle cliLoginResult event from MATLAB
 * @param {Event} event - Contains login result data
 */
function handleCliLoginResult(event) {
    try {
        var data = event && event.Data ? event.Data : {};
        AuthManager.handleCliLoginResult(data);
    } catch (err) {
        console.error('handleCliLoginResult error:', err);
    }
}

/**
 * Handle tabStatusUpdate event from MATLAB
 * @param {Event} event - Contains tab status data {tabId, status}
 */
function handleTabStatusUpdate(event) {
    try {
        var data = event && event.Data ? event.Data : {};
        if (data.tabId && data.status) {
            TabManager.handleStatusUpdate(data.tabId, data.status);
        }
    } catch (err) {
        console.error('handleTabStatusUpdate error:', err);
    }
}

// ============================================================================
// Execution Mode Manager
// ============================================================================

/**
 * ExecutionModeManager handles the execution mode indicator in the status bar.
 * Mode can be changed by clicking the status bar or pressing backtick key.
 */
var ExecutionModeManager = {
    // Mode configuration: id, label, CSS class, tooltip, color description
    EXEC_MODES: [
        { id: 'plan', label: 'Plan', cssClass: 'sb-exec-plan', tooltip: 'Plan mode - interview/planning, no code execution' },
        { id: 'prompt', label: 'Normal', cssClass: 'sb-exec-prompt', tooltip: 'Normal mode - prompts before each code execution' },
        { id: 'auto', label: 'Auto', cssClass: 'sb-exec-auto', tooltip: 'Auto mode - executes code automatically (security blocks active)' },
        { id: 'bypass', label: 'Bypass', cssClass: 'sb-exec-bypass', tooltip: 'DANGEROUS - All safety restrictions disabled!' }
    ],

    currentModeIndex: 1,  // Default to 'prompt' (Normal)
    bypassCyclingAllowed: false,  // Whether bypass mode can be cycled to via status bar/keyboard

    /**
     * Initialize the execution mode manager
     */
    init: function() {
        try {
            // Bind click handler to status bar element for cycling
            var modeEl = document.getElementById('sb-exec-mode');
            if (modeEl) {
                modeEl.addEventListener('click', function() {
                    ExecutionModeManager.cycleMode();
                });
            }
        } catch (err) {
            console.error('ExecutionModeManager.init error:', err);
        }
    },

    /**
     * Get mode config by ID
     */
    getModeById: function(modeId) {
        for (var i = 0; i < this.EXEC_MODES.length; i++) {
            if (this.EXEC_MODES[i].id === modeId) {
                return { index: i, config: this.EXEC_MODES[i] };
            }
        }
        return null;
    },

    /**
     * Set whether bypass mode cycling is allowed
     * @param {boolean} allowed - True if bypass cycling is allowed
     */
    setBypassCyclingAllowed: function(allowed) {
        this.bypassCyclingAllowed = allowed === true;
    },

    /**
     * Cycle to the next execution mode on click
     */
    cycleMode: function() {
        var nextIndex = (this.currentModeIndex + 1) % this.EXEC_MODES.length;
        var nextMode = this.EXEC_MODES[nextIndex];

        // If bypass cycling is not allowed, skip bypass mode
        if (nextMode.id === 'bypass' && !this.bypassCyclingAllowed) {
            // Skip to next mode (wraps around to plan)
            nextIndex = (nextIndex + 1) % this.EXEC_MODES.length;
            nextMode = this.EXEC_MODES[nextIndex];
        }

        // If cycling into bypass mode (and allowed), show confirmation dialog
        if (nextMode.id === 'bypass') {
            var confirmed = confirm(
                '⚠️ WARNING: Bypass Mode\n\n' +
                'This mode removes ALL safety restrictions:\n' +
                '• No approval prompts before code execution\n' +
                '• Blocked functions (eval, delete, system) are ALLOWED\n' +
                '• Destructive operations are permitted\n\n' +
                'This is DANGEROUS and should only be used when you fully trust the code.\n\n' +
                'Are you sure you want to enable Bypass mode?'
            );
            if (!confirmed) {
                return;  // User cancelled - stay on current mode
            }
        }

        this.setMode(nextMode.id);
    },

    /**
     * Set the execution mode by ID
     * @param {string} modeId - The mode ID ('plan', 'prompt', 'auto', 'bypass')
     */
    setMode: function(modeId) {
        var modeInfo = this.getModeById(modeId);
        if (!modeInfo) {
            console.warn('ExecutionModeManager: Unknown mode:', modeId);
            return;
        }

        this.currentModeIndex = modeInfo.index;
        var mode = modeInfo.config;

        // Update status bar display
        this._updateStatusBar(mode);

        // Show/hide bypass warning banner
        this._updateBypassBanner(modeId === 'bypass');

        // Send to MATLAB
        if (window.matlabBridge) {
            window.matlabBridge.sendEventToMATLAB('setExecutionMode', {
                mode: modeId,
                timestamp: Date.now()
            });
        }
    },

    /**
     * Update status bar display for a mode
     */
    _updateStatusBar: function(mode) {
        var modeEl = document.getElementById('sb-exec-mode');
        if (!modeEl) return;

        // Remove all mode classes
        for (var i = 0; i < this.EXEC_MODES.length; i++) {
            modeEl.classList.remove(this.EXEC_MODES[i].cssClass);
        }

        // Add new mode class and update text
        modeEl.classList.add(mode.cssClass);
        modeEl.textContent = mode.label;
        modeEl.title = mode.tooltip;
    },

    /**
     * Show or hide the bypass warning banner
     */
    _updateBypassBanner: function(show) {
        var banner = document.getElementById('bypass-warning');
        if (banner) {
            banner.style.display = show ? 'block' : 'none';
        }
    },

    /**
     * Load execution mode from settings (without notifying MATLAB)
     * @param {string} modeId - The mode ID to load
     */
    loadMode: function(modeId) {
        var modeInfo = this.getModeById(modeId);
        if (!modeInfo) {
            // Default to prompt if invalid
            modeId = 'prompt';
            modeInfo = this.getModeById(modeId);
        }

        this.currentModeIndex = modeInfo.index;
        var mode = modeInfo.config;

        // Update display without sending to MATLAB (it's loading from MATLAB)
        this._updateStatusBar(mode);
        this._updateBypassBanner(modeId === 'bypass');
    },

    /**
     * Get current mode ID
     */
    getCurrentMode: function() {
        return this.EXEC_MODES[this.currentModeIndex].id;
    }
};

// ============================================================================
// Interrupt Manager (Double-ESC to Stop)
// ============================================================================

/**
 * InterruptManager handles double-ESC keyboard shortcut to interrupt Claude requests.
 * Similar to Claude Code's behavior - press ESC twice within 1 second to interrupt.
 */
var InterruptManager = {
    /**
     * Initialize the interrupt manager - attach global ESC listener
     */
    init: function() {
        try {
            document.addEventListener('keydown', function(event) {
                if (event.key === 'Escape') {
                    InterruptManager._handleEscPress();
                }
            });
        } catch (err) {
            console.error('InterruptManager.init error:', err);
        }
    },

    /**
     * Handle ESC key press - detect double-tap pattern
     */
    _handleEscPress: function() {
        // Only handle ESC if we're streaming
        if (!window.chatState.isStreaming) {
            return;
        }

        // Close settings modal if open (don't count as interrupt)
        if (SettingsManager.isOpen) {
            return;
        }

        var now = Date.now();
        var state = window.interruptState;
        var timeSinceLastEsc = now - state.lastEscTime;

        if (timeSinceLastEsc <= state.THRESHOLD_MS && state.lastEscTime > 0) {
            // Double-ESC detected - trigger interrupt
            this._clearHint();
            this._triggerInterrupt();
            state.lastEscTime = 0;  // Reset for next time
        } else {
            // First ESC - show hint and wait for second
            state.lastEscTime = now;
            this._showInterruptHint();
        }
    },

    /**
     * Show "Press ESC again to interrupt..." hint
     */
    _showInterruptHint: function() {
        var state = window.interruptState;

        // Clear any existing hint timeout
        this._clearHint();

        // Create hint element if needed
        var hint = document.getElementById('interrupt-hint');
        if (!hint) {
            hint = document.createElement('div');
            hint.id = 'interrupt-hint';
            hint.className = 'interrupt-hint';
            hint.textContent = 'Press ESC again to interrupt...';
            document.body.appendChild(hint);
        }

        // Show the hint
        hint.style.display = 'block';
        hint.style.opacity = '1';

        // Auto-hide after threshold time
        state.hintTimeout = setTimeout(function() {
            InterruptManager._clearHint();
            window.interruptState.lastEscTime = 0;  // Reset if user didn't press ESC again
        }, state.THRESHOLD_MS);
    },

    /**
     * Clear the interrupt hint
     */
    _clearHint: function() {
        var state = window.interruptState;

        if (state.hintTimeout) {
            clearTimeout(state.hintTimeout);
            state.hintTimeout = null;
        }

        var hint = document.getElementById('interrupt-hint');
        if (hint) {
            hint.style.display = 'none';
        }
    },

    /**
     * Trigger the interrupt - send event to MATLAB
     */
    _triggerInterrupt: function() {
        if (!window.matlabBridge) {
            console.warn('InterruptManager: MATLAB bridge not available');
            return;
        }

        // Update status to show interrupting
        updateStatus('loading', 'Interrupting...');

        // Send interrupt request to MATLAB
        window.matlabBridge.sendEventToMATLAB('interruptRequest', {
            timestamp: Date.now()
        });
    },

    /**
     * Reset interrupt state - called when streaming ends
     */
    reset: function() {
        this._clearHint();
        window.interruptState.lastEscTime = 0;
    }
};

/**
 * Handle interruptComplete event from MATLAB
 */
function handleInterruptComplete(event) {
    try {
        // Finalize streaming message if there was one
        finalizeStreamingMessage();

        // Add visible interrupted message to chat
        addInterruptedMessage();

        // Reset streaming state
        setStreamingState(false);

        // Reset interrupt manager
        InterruptManager.reset();

        // Update status
        updateStatus('ready', 'Ready');

        // Clear initiating tab ID
        window.chatState.initiatingTabId = null;
    } catch (err) {
        console.error('handleInterruptComplete error:', err);
    }
}

/**
 * Add a visible "Thought interrupted by user" message to the chat
 */
function addInterruptedMessage() {
    var history = document.getElementById('message-history');
    if (!history) return;

    var msgDiv = document.createElement('div');
    msgDiv.className = 'system-message interrupted';
    msgDiv.textContent = 'Thought interrupted by user';
    history.appendChild(msgDiv);

    scrollToBottom();
}

// ============================================================================
// Tab Manager (Multi-Session Support)
// ============================================================================

/**
 * TabManager handles multiple chat sessions via tabs.
 * Each tab maintains its own message history, streaming state, and session ID.
 */
var TabManager = {
    /** @type {Map<string, TabState>} */
    tabs: new Map(),

    /** @type {string|null} */
    activeTabId: null,

    /** @type {number} */
    nextTabNumber: 1,

    /**
     * TabState structure:
     * @typedef {Object} TabState
     * @property {string} id - Unique tab identifier
     * @property {string} label - Display label for the tab
     * @property {Array} messages - Message history for this tab
     * @property {boolean} isStreaming - Whether currently streaming
     * @property {string} currentStreamMessage - Accumulated stream text
     * @property {string} sessionId - Python session ID for this tab
     * @property {string} status - Current status ('ready', 'working', 'attention', 'unread')
     * @property {number} unreadCount - Number of unread messages
     * @property {string} domSnapshot - Saved innerHTML of message-history
     * @property {number} scrollPosition - Saved scroll position
     */

    /**
     * Initialize the tab manager - creates first tab and binds events
     */
    init: function() {
        try {
            // Bind new tab button
            var newTabBtn = document.getElementById('new-tab-btn');
            if (newTabBtn) {
                newTabBtn.addEventListener('click', function() {
                    TabManager.createTab();
                });
            }

            // Create the initial tab
            this.createTab(true);  // true = initial tab, don't notify MATLAB

            // Save tab state when window loses visibility (helps preserve state during MATLAB window switches)
            var self = this;
            document.addEventListener('visibilitychange', function() {
                if (document.hidden && self.activeTabId) {
                    var currentTab = self.tabs.get(self.activeTabId);
                    var history = document.getElementById('message-history');
                    if (currentTab && history) {
                        currentTab.domSnapshot = history.innerHTML;
                        currentTab.scrollPosition = history.scrollTop;
                        currentTab.messages = window.chatState.messages.slice();
                    }
                }
            });

            console.log('TabManager initialized');
        } catch (err) {
            console.error('TabManager.init error:', err);
        }
    },

    /**
     * Create a new tab
     * @param {boolean} isInitial - True if this is the first tab (skip MATLAB notification)
     * @returns {string} The new tab's ID
     */
    createTab: function(isInitial) {
        var tabId = 'tab_' + Date.now() + '_' + Math.random().toString(36).substr(2, 5);
        var tabNumber = this.nextTabNumber++;
        var label = 'Chat ' + tabNumber;

        // Create tab state
        var tabState = {
            id: tabId,
            label: label,
            messages: [],
            isStreaming: false,
            currentStreamMessage: '',
            sessionId: null,
            status: 'ready',
            unreadCount: 0,
            domSnapshot: '',
            scrollPosition: 0
        };

        this.tabs.set(tabId, tabState);

        // Create tab DOM element
        this._createTabElement(tabState);

        // Switch to the new tab
        this.switchTab(tabId, isInitial);

        // Notify MATLAB (unless initial tab)
        if (!isInitial && window.matlabBridge) {
            window.matlabBridge.sendEventToMATLAB('createSession', {
                tabId: tabId,
                label: label,
                timestamp: Date.now()
            });
        }

        return tabId;
    },

    /**
     * Create the DOM element for a tab
     * @param {TabState} tabState
     */
    _createTabElement: function(tabState) {
        var container = document.getElementById('tab-container');
        if (!container) return;

        var tab = document.createElement('div');
        tab.className = 'session-tab';
        tab.id = 'session-tab-' + tabState.id;
        tab.setAttribute('data-tab-id', tabState.id);

        // Status icon
        var icon = document.createElement('span');
        icon.className = 'tab-icon tab-icon-ready';
        tab.appendChild(icon);

        // Label
        var label = document.createElement('span');
        label.className = 'tab-label';
        label.textContent = tabState.label;
        tab.appendChild(label);

        // Close button
        var closeBtn = document.createElement('button');
        closeBtn.className = 'tab-close';
        closeBtn.innerHTML = '&times;';
        closeBtn.title = 'Close tab';
        tab.appendChild(closeBtn);

        // Unread badge (hidden by default)
        var badge = document.createElement('span');
        badge.className = 'tab-badge';
        tab.appendChild(badge);

        // Click handlers
        var self = this;
        tab.addEventListener('click', function(e) {
            // Ignore if clicking close button
            if (e.target.classList.contains('tab-close')) return;
            self.switchTab(tabState.id);
        });

        closeBtn.addEventListener('click', function(e) {
            e.stopPropagation();
            self.closeTab(tabState.id);
        });

        container.appendChild(tab);
    },

    /**
     * Close a tab
     * @param {string} tabId
     */
    closeTab: function(tabId) {
        var tabState = this.tabs.get(tabId);
        if (!tabState) return;

        // If this is the only tab, clear it instead of closing
        if (this.tabs.size <= 1) {
            this._clearTabContent(tabId);
            return;
        }

        // If closing the active tab, switch to another first
        if (tabId === this.activeTabId) {
            // Find the next tab to switch to
            var tabIds = Array.from(this.tabs.keys());
            var currentIndex = tabIds.indexOf(tabId);
            var nextTabId = null;

            if (currentIndex > 0) {
                nextTabId = tabIds[currentIndex - 1];
            } else if (tabIds.length > 1) {
                nextTabId = tabIds[1];
            }

            if (nextTabId) {
                this.switchTab(nextTabId);
            }
        }

        // Remove tab DOM element
        var tabEl = document.getElementById('session-tab-' + tabId);
        if (tabEl) {
            tabEl.remove();
        }

        // Remove from tabs map
        this.tabs.delete(tabId);

        // Notify MATLAB
        if (window.matlabBridge) {
            window.matlabBridge.sendEventToMATLAB('closeSession', {
                tabId: tabId,
                timestamp: Date.now()
            });
        }
    },

    /**
     * Clear the content of a tab (used when clearing the last tab)
     * @param {string} tabId
     */
    _clearTabContent: function(tabId) {
        var tabState = this.tabs.get(tabId);
        if (!tabState) return;

        // Reset tab state
        tabState.messages = [];
        tabState.isStreaming = false;
        tabState.currentStreamMessage = '';
        tabState.unreadCount = 0;
        tabState.status = 'ready';

        // Clear auto-executed blocks tracking for this tab
        if (window.autoExecutedBlocks) {
            window.autoExecutedBlocks.clear();
        }

        // Clear message history if this is active tab
        if (tabId === this.activeTabId) {
            var history = document.getElementById('message-history');
            if (history) {
                history.innerHTML = '';
            }
            showWelcomeMessage();
        }

        // Update status
        this.updateTabStatus(tabId, 'ready');

        // Sync with chatState
        window.chatState.messages = [];
        window.chatState.currentStreamMessage = null;
        window.chatState.isStreaming = false;

        // Notify MATLAB to clear Python state
        if (window.matlabBridge) {
            window.matlabBridge.sendEventToMATLAB('clearChat', {
                tabId: tabId,
                timestamp: Date.now()
            });
        }
    },

    /**
     * Switch to a different tab
     * @param {string} tabId
     * @param {boolean} isInitial - True if this is during initialization
     */
    switchTab: function(tabId, isInitial) {
        var newTabState = this.tabs.get(tabId);
        if (!newTabState) return;

        var history = document.getElementById('message-history');
        if (!history) return;

        // Save current tab's state before switching
        if (this.activeTabId && this.activeTabId !== tabId) {
            var oldTabState = this.tabs.get(this.activeTabId);
            if (oldTabState) {
                // Save DOM snapshot and scroll position
                oldTabState.domSnapshot = history.innerHTML;
                oldTabState.scrollPosition = history.scrollTop;

                // Sync messages from chatState
                oldTabState.messages = window.chatState.messages.slice();
                oldTabState.isStreaming = window.chatState.isStreaming;
                oldTabState.currentStreamMessage = window.chatState.currentStreamMessage || '';

                // Update old tab's visual state
                var oldTabEl = document.getElementById('session-tab-' + this.activeTabId);
                if (oldTabEl) {
                    oldTabEl.classList.remove('active');
                }
            }
        }

        // Update active tab
        this.activeTabId = tabId;

        // Update tab visual state
        var newTabEl = document.getElementById('session-tab-' + tabId);
        if (newTabEl) {
            newTabEl.classList.add('active');
        }

        // Clear unread count when switching to tab
        newTabState.unreadCount = 0;
        this._updateBadge(tabId);

        // Restore new tab's content
        if (newTabState.domSnapshot) {
            history.innerHTML = newTabState.domSnapshot;
            history.scrollTop = newTabState.scrollPosition;
        } else if (newTabState.messages && newTabState.messages.length > 0) {
            // Fallback: rebuild DOM from messages array when domSnapshot is unavailable
            this.rebuildFromMessages(newTabState.messages);
        } else if (!isInitial) {
            // Fresh tab with no content yet
            history.innerHTML = '';
            showWelcomeMessage();
        }

        // Sync chatState with new tab
        window.chatState.messages = newTabState.messages.slice();
        window.chatState.isStreaming = newTabState.isStreaming;
        window.chatState.currentStreamMessage = newTabState.currentStreamMessage || null;
        window.chatState.sessionId = newTabState.sessionId;

        // Update streaming state UI
        setStreamingState(newTabState.isStreaming);

        // Notify MATLAB (unless initial)
        if (!isInitial && window.matlabBridge) {
            window.matlabBridge.sendEventToMATLAB('switchSession', {
                tabId: tabId,
                timestamp: Date.now()
            });
        }
    },

    /**
     * Rebuild the message history DOM from the messages array.
     * Used as fallback when domSnapshot is unavailable (e.g., after window focus changes).
     * @param {Array} messages - Array of message objects with role, content, and optional images
     */
    rebuildFromMessages: function(messages) {
        var history = document.getElementById('message-history');
        if (!history) return;

        history.innerHTML = '';

        if (!messages || messages.length === 0) {
            showWelcomeMessage();
            return;
        }

        messages.forEach(function(msg) {
            var messageDiv = document.createElement('div');
            messageDiv.className = 'message ' + msg.role;

            var contentDiv = document.createElement('div');
            contentDiv.className = 'message-content';

            if (msg.role === 'user') {
                // User messages are plain text
                contentDiv.textContent = msg.content;
            } else {
                // Assistant messages use markdown rendering
                contentDiv.innerHTML = parseMarkdown(msg.content);

                // Re-add images if present
                if (msg.images && msg.images.length > 0) {
                    msg.images.forEach(function(imgData) {
                        var imgContainer = document.createElement('div');
                        imgContainer.className = 'message-image-container';
                        imgContainer.innerHTML = createImageHTML(imgData);
                        contentDiv.insertBefore(imgContainer, contentDiv.firstChild);
                    });
                }
            }

            messageDiv.appendChild(contentDiv);
            history.appendChild(messageDiv);

            // Process code blocks for MATLAB syntax highlighting
            if (msg.role === 'assistant') {
                processCodeBlocks(messageDiv);
            }
        });

        scrollToBottom();
    },

    /**
     * Update a tab's status indicator
     * @param {string} tabId
     * @param {string} status - 'ready', 'working', 'attention', 'unread'
     */
    updateTabStatus: function(tabId, status) {
        var tabState = this.tabs.get(tabId);
        if (!tabState) return;

        tabState.status = status;

        var tabEl = document.getElementById('session-tab-' + tabId);
        if (!tabEl) return;

        var icon = tabEl.querySelector('.tab-icon');
        if (!icon) return;

        // Remove all status classes
        icon.classList.remove('tab-icon-ready', 'tab-icon-working', 'tab-icon-attention', 'tab-icon-unread');

        // Add new status class
        icon.classList.add('tab-icon-' + status);
    },

    /**
     * Increment unread count for a tab (when message received in background)
     * @param {string} tabId
     */
    incrementUnread: function(tabId) {
        var tabState = this.tabs.get(tabId);
        if (!tabState) return;

        tabState.unreadCount++;
        this._updateBadge(tabId);

        // Also set status to unread if not already attention
        if (tabState.status !== 'attention') {
            this.updateTabStatus(tabId, 'unread');
        }
    },

    /**
     * Update the unread badge display
     * @param {string} tabId
     */
    _updateBadge: function(tabId) {
        var tabState = this.tabs.get(tabId);
        if (!tabState) return;

        var tabEl = document.getElementById('session-tab-' + tabId);
        if (!tabEl) return;

        var badge = tabEl.querySelector('.tab-badge');
        if (!badge) return;

        if (tabState.unreadCount > 0) {
            badge.textContent = tabState.unreadCount > 9 ? '9+' : tabState.unreadCount.toString();
        } else {
            badge.textContent = '';
        }
    },

    /**
     * Get the active tab state
     * @returns {TabState|null}
     */
    getActiveTab: function() {
        if (!this.activeTabId) return null;
        return this.tabs.get(this.activeTabId) || null;
    },

    /**
     * Get the active tab ID
     * @returns {string|null}
     */
    getActiveTabId: function() {
        return this.activeTabId;
    },

    /**
     * Update session ID for a tab
     * @param {string} tabId
     * @param {string} sessionId
     */
    setSessionId: function(tabId, sessionId) {
        var tabState = this.tabs.get(tabId);
        if (tabState) {
            tabState.sessionId = sessionId;
        }
    },

    /**
     * Save current streaming state to active tab
     */
    saveStreamingState: function() {
        var tabState = this.getActiveTab();
        if (tabState) {
            tabState.isStreaming = window.chatState.isStreaming;
            tabState.currentStreamMessage = window.chatState.currentStreamMessage || '';
            tabState.messages = window.chatState.messages.slice();
        }
    },

    /**
     * Handle status update from MATLAB
     * @param {string} tabId
     * @param {string} status
     */
    handleStatusUpdate: function(tabId, status) {
        this.updateTabStatus(tabId, status);
    },

    /**
     * Start streaming in a background tab (when user switches away during streaming)
     * @param {string} tabId
     */
    startBackgroundStreaming: function(tabId) {
        var tabState = this.tabs.get(tabId);
        if (!tabState) return;

        tabState.isStreaming = true;
        tabState.currentStreamMessage = '';
    },

    /**
     * Append streaming content to a background tab
     * @param {string} tabId
     * @param {string} text
     */
    appendToBackgroundTab: function(tabId, text) {
        var tabState = this.tabs.get(tabId);
        if (!tabState) return;

        tabState.currentStreamMessage = (tabState.currentStreamMessage || '') + text;
        tabState.isStreaming = true;
    },

    /**
     * Finalize streaming in a background tab (message completed while user on different tab)
     * @param {string} tabId
     */
    finalizeBackgroundTab: function(tabId) {
        var tabState = this.tabs.get(tabId);
        if (!tabState) return;

        // Add the completed message to the tab's message history
        if (tabState.currentStreamMessage) {
            tabState.messages.push({
                role: 'assistant',
                content: tabState.currentStreamMessage
            });

            // Update DOM snapshot to include the new message
            // We need to render the message into the saved HTML
            var messageHtml = this._renderAssistantMessage(tabState.currentStreamMessage);
            tabState.domSnapshot = tabState.domSnapshot + messageHtml;
        }

        // Reset streaming state
        tabState.currentStreamMessage = '';
        tabState.isStreaming = false;

        // Increment unread count to alert user
        this.incrementUnread(tabId);
    },

    /**
     * Render an assistant message as HTML (for background tab DOM snapshot)
     * @param {string} content
     * @returns {string} HTML string
     */
    _renderAssistantMessage: function(content) {
        // Create a temporary container to generate the message HTML
        // This mirrors the structure created by addAssistantMessage()
        var escapedContent = content
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#039;');

        // Simple rendering - the full markdown rendering will happen when tab is viewed
        // For now, store as pre-formatted text that will be properly rendered on tab switch
        return '<div class="message assistant-message">' +
               '<div class="message-content">' +
               '<div class="markdown-content">' + escapedContent + '</div>' +
               '</div></div>';
    }
};
