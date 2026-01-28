// CloudWatch Synthetics Canary - API Health Check
// Tests backend API endpoints directly

const synthetics = require('Synthetics');
const log = require('SyntheticsLogger');
const http = require('http');
const https = require('https');

const apiCanaryBlueprint = async function () {
    const FRONTEND_URL = process.env.FRONTEND_URL || 'http://localhost';

    // Parse URL
    const url = new URL(FRONTEND_URL);
    const isHttps = url.protocol === 'https:';
    const hostname = url.hostname;
    const port = url.port || (isHttps ? 443 : 80);

    log.info(`Testing API endpoints at: ${hostname}:${port}`);

    // Helper function for HTTP requests
    const makeRequest = (path, method = 'GET', expectedStatus = 200) => {
        return new Promise((resolve, reject) => {
            const options = {
                hostname: hostname,
                port: port,
                path: path,
                method: method,
                headers: {
                    'User-Agent': 'CloudWatch-Synthetics-Canary',
                    'Accept': 'application/json'
                },
                timeout: 10000
            };

            const client = isHttps ? https : http;
            const req = client.request(options, (res) => {
                let data = '';
                res.on('data', chunk => data += chunk);
                res.on('end', () => {
                    resolve({
                        statusCode: res.statusCode,
                        headers: res.headers,
                        body: data
                    });
                });
            });

            req.on('error', reject);
            req.on('timeout', () => reject(new Error('Request timeout')));
            req.end();
        });
    };

    // Step 1: Check frontend root
    await synthetics.executeStep('Frontend Root', async function () {
        log.info('Checking frontend root endpoint');
        const response = await makeRequest('/');

        if (response.statusCode !== 200 && response.statusCode !== 302) {
            throw new Error(`Frontend root returned ${response.statusCode}, expected 200 or 302`);
        }
        log.info(`Frontend root: ${response.statusCode} OK`);
    });

    // Step 2: Check login page
    await synthetics.executeStep('Login Page', async function () {
        log.info('Checking login page');
        const response = await makeRequest('/login');

        if (response.statusCode !== 200) {
            throw new Error(`Login page returned ${response.statusCode}, expected 200`);
        }
        log.info(`Login page: ${response.statusCode} OK`);
    });

    // Step 3: Check ready endpoint (if exists)
    await synthetics.executeStep('Ready Endpoint', async function () {
        log.info('Checking /ready endpoint');
        try {
            const response = await makeRequest('/ready');
            log.info(`Ready endpoint: ${response.statusCode}`);

            if (response.statusCode === 200) {
                log.info('Ready endpoint: OK');
            } else if (response.statusCode === 404) {
                log.info('Ready endpoint not found (404) - this is OK for frontend');
            } else {
                log.warn(`Ready endpoint returned unexpected status: ${response.statusCode}`);
            }
        } catch (e) {
            log.warn(`Ready endpoint check failed: ${e.message}`);
        }
    });

    // Step 4: Check version/health (common patterns)
    await synthetics.executeStep('Version Check', async function () {
        log.info('Checking version/health endpoints');

        const endpoints = ['/version', '/health', '/healthz', '/_health'];
        let foundOne = false;

        for (const endpoint of endpoints) {
            try {
                const response = await makeRequest(endpoint);
                if (response.statusCode === 200) {
                    log.info(`${endpoint}: ${response.statusCode} OK - ${response.body.substring(0, 100)}`);
                    foundOne = true;
                    break;
                }
            } catch (e) {
                // Continue to next endpoint
            }
        }

        if (!foundOne) {
            log.info('No standard health endpoints found, but frontend is responding');
        }
    });

    // Step 5: Check static assets load
    await synthetics.executeStep('Static Assets', async function () {
        log.info('Checking static assets');

        try {
            const response = await makeRequest('/static/styles/cymbal.css');
            if (response.statusCode === 200) {
                log.info('Static CSS: OK');
            } else {
                log.warn(`Static CSS returned: ${response.statusCode}`);
            }
        } catch (e) {
            log.warn(`Static assets check failed: ${e.message}`);
        }
    });

    log.info('API health check canary completed successfully!');
};

exports.handler = async () => {
    return await apiCanaryBlueprint();
};
