const socket = io();

// DOM Elements
const actionSelect = document.getElementById('action-select');
const tagGroup = document.getElementById('tag-group');
const deployGroup = document.getElementById('deploy-group');
const btnExecute = document.getElementById('btn-execute');
const terminal = document.getElementById('terminal');
const statusIndicator = document.getElementById('status-indicator');
const statusText = document.getElementById('status-text');
const chartVersionSelect = document.getElementById('chart-version');
const terminalInput = document.getElementById('terminal-input');

// Initial State
let isRunning = false;

// Add Hana Option dynamically if not present (or expected in index.html)
// Just ensuring logic handles it. 
// Note: We need to add the option to HTML manually or via JS. 
// Let's assume user manually edits HTML or we do it here.
if (!document.querySelector('option[value="hana_enable"]')) {
    const opt = document.createElement('option');
    opt.value = 'hana_enable';
    opt.textContent = 'Hana Enable (Manager)';
    actionSelect.appendChild(opt);
}

// UI Logic: Show/Hide inputs based on Action
actionSelect.addEventListener('change', (e) => {
    const action = e.target.value;
    
    if (action === 'deploy_oci') {
        tagGroup.classList.add('hidden');
        deployGroup.classList.remove('hidden');
        loadVersions();
    } else if (action === 'hana_enable') {
        tagGroup.classList.add('hidden');
        deployGroup.classList.add('hidden');
    } else {
        tagGroup.classList.remove('hidden');
        deployGroup.classList.add('hidden');
    }
});

async function loadVersions() {
    chartVersionSelect.innerHTML = '<option>Loading...</option>';
    try {
        const res = await fetch('/api/tags');
        const tags = await res.json();
        
        if (tags && tags.length > 0) {
            chartVersionSelect.innerHTML = tags.map(t => `<option value="${t}">${t}</option>`).join('');
        } else {
            chartVersionSelect.innerHTML = '<option value="">No versions found</option>';
        }
    } catch (e) {
        chartVersionSelect.innerHTML = '<option value="">Error loading</option>';
    }
}

// Terminal Input Logic
terminalInput.addEventListener('keypress', (e) => {
    if (e.key === 'Enter') {
        const cmd = terminalInput.value;
        socket.emit('input', cmd + '\n'); // Send newline
        // Echo locally for better UX?
        // const line = document.createElement('div');
        // line.textContent = '> ' + cmd;
        // terminal.appendChild(line);
        terminalInput.value = '';
    }
});

// Execute Logic
btnExecute.addEventListener('click', () => {
    if (isRunning) return;

    const action = actionSelect.value;
    const tag = document.getElementById('inp-tag').value;
    const chartVersion = chartVersionSelect.value;
    const namespace = document.getElementById('inp-ns').value;

    if (action !== 'deploy_oci' && action !== 'hana_enable' && !tag) {
        alert("Please enter a Tag or Suffix");
        return;
    }

    setBusy(true);
    terminal.innerHTML = ''; // Clear terminal

    socket.emit('execute_script', {
        action,
        tag,
        chartVersion,
        namespace
    });
});

// Socket Events
socket.on('log', (msg) => {
    const line = document.createElement('div');
    line.className = 'line';
    line.textContent = msg.replace(/\u001b\[\d+m/g, ''); 
    terminal.appendChild(line);
    terminal.scrollTop = terminal.scrollHeight;
});

socket.on('done', (code) => {
    setBusy(false);
    const line = document.createElement('div');
    line.innerHTML = `<br>--- Process finished with code ${code} ---`;
    line.style.color = code === 0 ? '#10b981' : '#ef4444';
    terminal.appendChild(line);
});

function setBusy(busy) {
    isRunning = busy;
    if (busy) {
        statusIndicator.classList.add('busy');
        statusText.textContent = "Executing...";
        btnExecute.disabled = true;
        btnExecute.textContent = "Running...";
        terminalInput.disabled = false;
        terminalInput.focus();
    } else {
        statusIndicator.classList.remove('busy');
        statusText.textContent = "Ready";
        btnExecute.disabled = false;
        btnExecute.textContent = "Execute";
        terminalInput.disabled = true;
    }
}
