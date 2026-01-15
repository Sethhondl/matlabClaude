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
    // Store reference globally
    window.matlabBridge = htmlComponent;

    // Listen for data changes from MATLAB
    htmlComponent.addEventListener('DataChanged', handleMatlabData);

    // Initialize UI event handlers
    initializeUI();

    // Show welcome message
    showWelcomeMessage();

    // Notify MATLAB that UI is ready
    htmlComponent.sendEventToMATLAB('uiReady', {
        timestamp: Date.now()
    });
}

/**
 * Handle data updates from MATLAB
 * @param {Event} event - The DataChanged event
 */
function handleMatlabData(event) {
    const data = event.Data;

    if (!data || !data.type) {
        console.warn('Received data without type:', data);
        return;
    }

    switch (data.type) {
        case 'assistantMessage':
            // Complete assistant message
            addAssistantMessage(data.content, true);
            setStreamingState(false);
            break;

        case 'streamStart':
            // Start of a new streamed response
            setStreamingState(true);
            startStreamingMessage();
            break;

        case 'streamChunk':
            // Streaming text chunk
            appendToStreamingMessage(data.content);
            break;

        case 'streamEnd':
            // End of streaming
            finalizeStreamingMessage();
            setStreamingState(false);
            break;

        case 'codeResult':
            // Result of code execution
            showCodeResult(data.blockId, data.result, data.isError);
            break;

        case 'error':
            // Error from MATLAB
            showError(data.message);
            setStreamingState(false);
            break;

        case 'status':
            // Status update
            updateStatus(data.status, data.message);
            break;

        case 'sessionId':
            // Session ID update
            window.chatState.sessionId = data.sessionId;
            break;

        default:
            console.warn('Unknown data type:', data.type);
    }
}

/**
 * Initialize UI event handlers
 */
function initializeUI() {
    // Send button
    const sendBtn = document.getElementById('send-btn');
    sendBtn.addEventListener('click', sendMessage);

    // Text input
    const userInput = document.getElementById('user-input');
    userInput.addEventListener('keydown', handleKeyDown);

    // Auto-resize textarea
    userInput.addEventListener('input', autoResizeTextarea);
}

/**
 * Handle keyboard events in the input field
 * @param {KeyboardEvent} event
 */
function handleKeyDown(event) {
    // Ctrl+Enter or Cmd+Enter to send
    if (event.key === 'Enter' && (event.ctrlKey || event.metaKey)) {
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

    // Get context options
    const includeWorkspace = document.getElementById('include-workspace').checked;
    const includeSimulink = document.getElementById('include-simulink').checked;

    // Add user message to UI
    addUserMessage(message);

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
            includeWorkspace: includeWorkspace,
            includeSimulink: includeSimulink,
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
 * @param {string} status - 'ready', 'loading', 'error'
 * @param {string} message - Status message
 */
function updateStatus(status, message) {
    const statusDot = document.getElementById('status-dot');
    const statusText = document.getElementById('status-text');

    statusDot.classList.remove('loading', 'error');

    if (status === 'loading') {
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
