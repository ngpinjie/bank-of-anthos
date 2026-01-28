// CloudWatch Synthetics Canary - Heartbeat Frontend
// Simple HTTP check to verify frontend is reachable

const synthetics = require('Synthetics');
const log = require('SyntheticsLogger');

const apiCanaryBlueprint = async function () {
    const hostname = process.env.FRONTEND_URL || 'http://localhost';

    // Configure request
    let requestOptions = {
        hostname: hostname.replace(/^https?:\/\//, '').replace(/\/$/, ''),
        method: 'GET',
        path: '/',
        port: 80,
        protocol: 'http:',
        headers: {
            'User-Agent': 'CloudWatch-Synthetics-Canary'
        }
    };

    // Remove port from hostname if present
    if (requestOptions.hostname.includes(':')) {
        const parts = requestOptions.hostname.split(':');
        requestOptions.hostname = parts[0];
        requestOptions.port = parseInt(parts[1]);
    }

    log.info(`Checking frontend at: ${requestOptions.hostname}:${requestOptions.port}`);

    // Step 1: Check homepage loads
    let stepConfig = {
        includeRequestHeaders: true,
        includeResponseHeaders: true,
        includeRequestBody: false,
        includeResponseBody: true,
        restrictedHeaders: [],
        continueOnHttpStepFailure: false
    };

    await synthetics.executeHttpStep('Homepage Check', requestOptions, null, stepConfig);

    log.info('Frontend heartbeat check passed!');
};

exports.handler = async () => {
    return await apiCanaryBlueprint();
};
