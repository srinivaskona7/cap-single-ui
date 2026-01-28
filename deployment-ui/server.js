const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const { spawn } = require('child_process');
const path = require('path');
const fs = require('fs');
const https = require('https');

const app = express();
const server = http.createServer(app);
const io = new Server(server);

app.use(express.static(path.join(__dirname, 'public')));
app.use(express.json());

// API to get available Docker tags from Hub
app.get('/api/tags', (req, res) => {
    const options = {
        hostname: 'hub.docker.com',
        path: '/v2/repositories/sriniv7654/single/tags/?page_size=10',
        method: 'GET'
    };

    const reqApi = https.request(options, (resApi) => {
        let data = '';
        resApi.on('data', (chunk) => data += chunk);
        resApi.on('end', () => {
            try {
                const json = JSON.parse(data);
                const tags = json.results ? json.results.map(r => r.name) : [];
                res.json(tags);
            } catch (e) {
                res.json([]);
            }
        });
    });
    reqApi.on('error', () => res.json([]));
    reqApi.end();
});

io.on('connection', (socket) => {
    console.log('Client connected');

    socket.on('execute_script', (data) => {
        const { action, tag, chartVersion, namespace } = data;
        let scriptInput = '';

        // Map UI actions to Script Inputs
        // 4) Build Images -> Input: "4\n<tag>\n"
        // 7) Build New Chart -> Input: "7\n<suffix>\n" 
        // 8) Deploy OCI -> Input: "8\n<version>\n<release>\n<ns>\n<kubeconfig>\n"

        if (action === 'build_images') {
            scriptInput = `4\n${tag}\n`;
        } else if (action === 'build_chart') {
            // Tag comes as "v1", script asks for suffix. 
            // If tag is "1.0.0-ui", suffix is "ui". logic needed?
            // User inputs suffix directly in UI for this action.
            scriptInput = `7\n${tag}\n`;
        } else if (action === 'deploy_oci') {
            // Deploy: 8 -> Version(0 for manual) -> ManualVer -> Release -> Namespace -> Kubeconfig
            // We'll simplify: Assume we pass the version selected
            // We need to match the script's prompt sequence exactly.
            // Script: Select Version [1-N] or 0.
            // Safe bet: "0\n<version>\n<release>\n<namespace>\n\n" (default kubeconfig)
            scriptInput = `8\n0\n${chartVersion}\nsingle-ui\n${namespace}\n\n`;
        }

        const scriptPath = path.join(__dirname, '../deploy_new.sh');
        const child = spawn(scriptPath, [], {
            cwd: path.join(__dirname, '../'),
            shell: true
        });

        // Pipe the calculated input to the script (Initial Answer)
        if (scriptInput) {
            child.stdin.write(scriptInput);
        }
        
        // Do NOT close stdin immediately for interactive scripts
        // child.stdin.end(); 

        // Handle interactive input from client
        socket.on('input', (inputData) => {
            child.stdin.write(inputData);
        }); 

        child.stdout.on('data', (data) => {
            socket.emit('log', data.toString());
        });

        child.stderr.on('data', (data) => {
            socket.emit('log', `\x1b[31m${data.toString()}\x1b[0m`); // Red for error
        });

        child.on('close', (code) => {
            socket.emit('log', `\n\nProcess exited with code ${code}`);
            socket.emit('done', code);
        });
    });
});

const PORT = 3000;
server.listen(PORT, () => {
    console.log(`UI Server running at http://localhost:${PORT}`);
});
