/**
 * Claude Code MATLAB Integration - Code Execution Handling
 *
 * Handles code block actions: copy, run, and insert.
 */

/**
 * Copy code to clipboard
 * @param {string} blockId - The code block ID
 */
function copyCode(blockId) {
    const codeElement = document.getElementById(blockId);
    if (!codeElement) return;

    const code = codeElement.textContent;

    // Use clipboard API if available
    if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(code).then(() => {
            showCopyFeedback(blockId, true);
        }).catch(() => {
            fallbackCopy(code, blockId);
        });
    } else {
        fallbackCopy(code, blockId);
    }
}

/**
 * Fallback copy method using textarea
 * @param {string} code - Code to copy
 * @param {string} blockId - Block ID for feedback
 */
function fallbackCopy(code, blockId) {
    const textarea = document.createElement('textarea');
    textarea.value = code;
    textarea.style.position = 'fixed';
    textarea.style.left = '-9999px';
    document.body.appendChild(textarea);
    textarea.select();

    try {
        document.execCommand('copy');
        showCopyFeedback(blockId, true);
    } catch (err) {
        showCopyFeedback(blockId, false);
    }

    document.body.removeChild(textarea);
}

/**
 * Show copy feedback on button
 * @param {string} blockId - Block ID
 * @param {boolean} success - Whether copy succeeded
 */
function showCopyFeedback(blockId, success) {
    const container = document.querySelector(`[data-block-id="${blockId}"]`);
    if (!container) return;

    const copyBtn = container.querySelector('.copy-btn');
    if (!copyBtn) return;

    const originalText = copyBtn.textContent;
    copyBtn.textContent = success ? 'Copied!' : 'Failed';
    copyBtn.disabled = true;

    setTimeout(() => {
        copyBtn.textContent = originalText;
        copyBtn.disabled = false;
    }, 1500);
}

/**
 * Run MATLAB code via MATLAB bridge
 * @param {string} blockId - The code block ID
 */
function runCode(blockId) {
    const codeElement = document.getElementById(blockId);
    if (!codeElement) return;

    const code = codeElement.textContent;

    // Show loading state
    showCodeLoading(blockId);

    // Disable run button while executing
    const container = document.querySelector(`[data-block-id="${blockId}"]`);
    if (container) {
        const runBtn = container.querySelector('.run-btn');
        if (runBtn) {
            runBtn.disabled = true;
            runBtn.textContent = 'Running...';
        }
    }

    // Send to MATLAB for execution
    if (window.matlabBridge) {
        window.matlabBridge.sendEventToMATLAB('runCode', {
            blockId: blockId,
            code: code,
            timestamp: Date.now()
        });
    } else {
        showCodeResult(blockId, 'Error: MATLAB connection not available', true);
    }
}

/**
 * Insert code into MATLAB editor
 * @param {string} blockId - The code block ID
 */
function insertCode(blockId) {
    const codeElement = document.getElementById(blockId);
    if (!codeElement) return;

    const code = codeElement.textContent;

    // Send to MATLAB for insertion into editor
    if (window.matlabBridge) {
        window.matlabBridge.sendEventToMATLAB('insertCode', {
            blockId: blockId,
            code: code,
            timestamp: Date.now()
        });

        // Show feedback
        const container = document.querySelector(`[data-block-id="${blockId}"]`);
        if (container) {
            const insertBtn = container.querySelector('.insert-btn');
            if (insertBtn) {
                const originalText = insertBtn.textContent;
                insertBtn.textContent = 'Inserted!';
                insertBtn.disabled = true;

                setTimeout(() => {
                    insertBtn.textContent = originalText;
                    insertBtn.disabled = false;
                }, 1500);
            }
        }
    }
}

/**
 * Show loading indicator while code is executing
 * @param {string} blockId - The code block ID
 */
function showCodeLoading(blockId) {
    const container = document.querySelector(`[data-block-id="${blockId}"]`);
    if (!container) return;

    // Remove any existing result
    const existingResult = container.querySelector('.code-result');
    if (existingResult) {
        existingResult.remove();
    }

    // Add loading indicator
    const loadingDiv = document.createElement('div');
    loadingDiv.className = 'code-loading';
    loadingDiv.id = `loading-${blockId}`;
    loadingDiv.innerHTML = `
        <div class="code-loading-spinner"></div>
        <span>Executing code...</span>
    `;

    container.appendChild(loadingDiv);
}

/**
 * Show code execution result
 * @param {string} blockId - The code block ID
 * @param {string} result - The execution result or error message
 * @param {boolean} isError - Whether this is an error
 */
function showCodeResult(blockId, result, isError) {
    const container = document.querySelector(`[data-block-id="${blockId}"]`);
    if (!container) return;

    // Remove loading indicator
    const loading = document.getElementById(`loading-${blockId}`);
    if (loading) {
        loading.remove();
    }

    // Remove any existing result
    const existingResult = container.querySelector('.code-result');
    if (existingResult) {
        existingResult.remove();
    }

    // Reset run button
    const runBtn = container.querySelector('.run-btn');
    if (runBtn) {
        runBtn.disabled = false;
        runBtn.textContent = 'Run';
    }

    // Create result display
    const resultDiv = document.createElement('div');
    resultDiv.className = 'code-result';

    const headerClass = isError ? 'error' : 'success';
    const headerText = isError ? 'Error' : 'Output';
    const contentClass = isError ? 'error' : '';

    // Escape HTML in result
    const escapedResult = result
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;');

    resultDiv.innerHTML = `
        <div class="code-result-header ${headerClass}">
            ${isError ? '&#x2717;' : '&#x2713;'} ${headerText}
        </div>
        <div class="code-result-content ${contentClass}">${escapedResult || '(no output)'}</div>
    `;

    container.appendChild(resultDiv);

    scrollToBottom();
}

/**
 * Clear all code results
 */
function clearAllResults() {
    const results = document.querySelectorAll('.code-result');
    results.forEach(result => result.remove());

    const loadings = document.querySelectorAll('.code-loading');
    loadings.forEach(loading => loading.remove());

    // Also clear the auto-executed blocks tracking
    if (window.autoExecutedBlocks) {
        window.autoExecutedBlocks.clear();
    }
}
