/**
 * Claude Code MATLAB Integration - Chat Message Handling
 *
 * Handles message rendering, markdown parsing, and chat history management.
 */

/**
 * Add a user message to the chat
 * @param {string} content - Message content
 */
function addUserMessage(content) {
    const history = document.getElementById('message-history');

    // Remove welcome message if present
    const welcome = history.querySelector('.welcome-message');
    if (welcome) {
        welcome.remove();
    }

    const messageDiv = document.createElement('div');
    messageDiv.className = 'message user';

    const contentDiv = document.createElement('div');
    contentDiv.className = 'message-content';
    contentDiv.textContent = content;

    messageDiv.appendChild(contentDiv);
    history.appendChild(messageDiv);

    // Store in state
    window.chatState.messages.push({
        role: 'user',
        content: content,
        timestamp: Date.now()
    });

    scrollToBottom();
}

/**
 * Add a complete assistant message to the chat
 * @param {string} content - Message content (may contain markdown)
 * @param {boolean} isComplete - Whether this is the final message
 */
function addAssistantMessage(content, isComplete = true) {
    const history = document.getElementById('message-history');

    const messageDiv = document.createElement('div');
    messageDiv.className = 'message assistant';

    const contentDiv = document.createElement('div');
    contentDiv.className = 'message-content';
    contentDiv.innerHTML = parseMarkdown(content);

    messageDiv.appendChild(contentDiv);
    history.appendChild(messageDiv);

    // Process code blocks for MATLAB
    processCodeBlocks(messageDiv);

    // Store in state
    window.chatState.messages.push({
        role: 'assistant',
        content: content,
        timestamp: Date.now()
    });

    scrollToBottom();
}

/**
 * Start a new streaming message
 */
function startStreamingMessage() {
    const history = document.getElementById('message-history');

    const messageDiv = document.createElement('div');
    messageDiv.className = 'message assistant';
    messageDiv.id = 'streaming-message';

    const contentDiv = document.createElement('div');
    contentDiv.className = 'message-content';
    contentDiv.id = 'streaming-content';

    // Add streaming cursor
    const cursor = document.createElement('span');
    cursor.className = 'streaming-cursor';
    cursor.id = 'streaming-cursor';
    contentDiv.appendChild(cursor);

    messageDiv.appendChild(contentDiv);
    history.appendChild(messageDiv);

    window.chatState.currentStreamMessage = {
        content: '',
        element: messageDiv
    };

    scrollToBottom();
}

/**
 * Append text to the current streaming message
 * @param {string} chunk - Text chunk to append
 */
function appendToStreamingMessage(chunk) {
    if (!window.chatState.currentStreamMessage) {
        startStreamingMessage();
    }

    window.chatState.currentStreamMessage.content += chunk;

    const contentDiv = document.getElementById('streaming-content');
    if (contentDiv) {
        // Parse and render current content
        const parsed = parseMarkdown(window.chatState.currentStreamMessage.content);

        // Keep cursor
        contentDiv.innerHTML = parsed + '<span class="streaming-cursor"></span>';

        scrollToBottom();
    }
}

/**
 * Finalize the streaming message
 */
function finalizeStreamingMessage() {
    const streamMsg = window.chatState.currentStreamMessage;
    if (!streamMsg) return;

    const messageDiv = document.getElementById('streaming-message');
    const contentDiv = document.getElementById('streaming-content');

    if (messageDiv && contentDiv) {
        // Remove streaming indicators
        messageDiv.removeAttribute('id');
        contentDiv.removeAttribute('id');

        // Final render without cursor
        contentDiv.innerHTML = parseMarkdown(streamMsg.content);

        // Process code blocks
        processCodeBlocks(messageDiv);
    }

    // Store in state
    window.chatState.messages.push({
        role: 'assistant',
        content: streamMsg.content,
        timestamp: Date.now()
    });

    window.chatState.currentStreamMessage = null;

    scrollToBottom();
}

/**
 * Simple markdown parser (handles basic formatting and code blocks)
 * @param {string} text - Markdown text
 * @returns {string} HTML
 */
function parseMarkdown(text) {
    if (!text) return '';

    // Escape HTML
    let html = text
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');

    // Code blocks (```language\ncode```)
    let blockId = 0;
    html = html.replace(/```(\w*)\n([\s\S]*?)```/g, (match, lang, code) => {
        blockId++;
        const language = lang || 'plaintext';
        return createCodeBlockHTML(code.trim(), language, `code-block-${blockId}`);
    });

    // Inline code (`code`)
    html = html.replace(/`([^`]+)`/g, '<code>$1</code>');

    // Bold (**text**)
    html = html.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');

    // Italic (*text*)
    html = html.replace(/\*([^*]+)\*/g, '<em>$1</em>');

    // Headers (### text)
    html = html.replace(/^### (.+)$/gm, '<h3>$1</h3>');
    html = html.replace(/^## (.+)$/gm, '<h2>$1</h2>');
    html = html.replace(/^# (.+)$/gm, '<h1>$1</h1>');

    // Bullet lists
    html = html.replace(/^- (.+)$/gm, '<li>$1</li>');
    html = html.replace(/(<li>.*<\/li>\n?)+/g, '<ul>$&</ul>');

    // Paragraphs (double newlines)
    html = html.replace(/\n\n/g, '</p><p>');
    html = '<p>' + html + '</p>';

    // Clean up empty paragraphs
    html = html.replace(/<p><\/p>/g, '');
    html = html.replace(/<p>(<h[123]>)/g, '$1');
    html = html.replace(/(<\/h[123]>)<\/p>/g, '$1');
    html = html.replace(/<p>(<ul>)/g, '$1');
    html = html.replace(/(<\/ul>)<\/p>/g, '$1');
    html = html.replace(/<p>(<div)/g, '$1');
    html = html.replace(/(\/div>)<\/p>/g, '$1');

    return html;
}

/**
 * Create HTML for a code block with action buttons
 * @param {string} code - The code content
 * @param {string} language - Programming language
 * @param {string} blockId - Unique block identifier
 * @returns {string} HTML string
 */
function createCodeBlockHTML(code, language, blockId) {
    const isMatlab = language.toLowerCase() === 'matlab' || language.toLowerCase() === 'm';

    const actions = isMatlab ? `
        <button class="copy-btn" onclick="copyCode('${blockId}')">Copy</button>
        <button class="run-btn" onclick="runCode('${blockId}')">Run</button>
        <button class="insert-btn" onclick="insertCode('${blockId}')">Insert</button>
    ` : `
        <button class="copy-btn" onclick="copyCode('${blockId}')">Copy</button>
    `;

    return `
        <div class="code-block-container" data-block-id="${blockId}">
            <div class="code-header">
                <span class="language-label">${language}</span>
                <div class="code-actions">
                    ${actions}
                </div>
            </div>
            <pre><code id="${blockId}" class="language-${language}">${code}</code></pre>
        </div>
    `;
}

/**
 * Process code blocks in a message element (for syntax highlighting, etc.)
 * @param {HTMLElement} messageElement
 */
function processCodeBlocks(messageElement) {
    // Apply basic MATLAB syntax highlighting
    const codeBlocks = messageElement.querySelectorAll('code.language-matlab, code.language-m');

    codeBlocks.forEach(block => {
        block.innerHTML = highlightMatlab(block.textContent);
    });
}

/**
 * Basic MATLAB syntax highlighting
 * @param {string} code - MATLAB code
 * @returns {string} Highlighted HTML
 */
function highlightMatlab(code) {
    // Keywords
    const keywords = ['function', 'end', 'if', 'else', 'elseif', 'for', 'while', 'switch', 'case', 'otherwise', 'try', 'catch', 'return', 'break', 'continue', 'global', 'persistent', 'classdef', 'properties', 'methods', 'events', 'enumeration'];

    // Built-in functions (common ones)
    const builtins = ['plot', 'figure', 'hold', 'xlabel', 'ylabel', 'title', 'legend', 'subplot', 'disp', 'fprintf', 'sprintf', 'length', 'size', 'zeros', 'ones', 'eye', 'linspace', 'logspace', 'mean', 'std', 'max', 'min', 'sum', 'prod', 'sqrt', 'abs', 'sin', 'cos', 'tan', 'exp', 'log', 'log10'];

    let highlighted = code;

    // Escape HTML
    highlighted = highlighted
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');

    // Comments (% to end of line)
    highlighted = highlighted.replace(/(%.*)$/gm, '<span class="hljs-comment">$1</span>');

    // Strings
    highlighted = highlighted.replace(/'([^']*?)'/g, '<span class="hljs-string">\'$1\'</span>');
    highlighted = highlighted.replace(/"([^"]*?)"/g, '<span class="hljs-string">"$1"</span>');

    // Numbers
    highlighted = highlighted.replace(/\b(\d+\.?\d*([eE][+-]?\d+)?)\b/g, '<span class="hljs-number">$1</span>');

    // Keywords
    keywords.forEach(kw => {
        const regex = new RegExp('\\b(' + kw + ')\\b', 'g');
        highlighted = highlighted.replace(regex, '<span class="hljs-keyword">$1</span>');
    });

    // Built-ins
    builtins.forEach(fn => {
        const regex = new RegExp('\\b(' + fn + ')\\b', 'g');
        highlighted = highlighted.replace(regex, '<span class="hljs-built_in">$1</span>');
    });

    return highlighted;
}
