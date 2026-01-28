// CloudWatch Synthetics Canary - Login Flow
// Tests the complete login workflow using Puppeteer

const synthetics = require('Synthetics');
const log = require('SyntheticsLogger');
const syntheticsConfiguration = synthetics.getConfiguration();

const flowBuilderBlueprint = async function () {
    const URL = process.env.FRONTEND_URL || 'http://localhost';
    const USERNAME = process.env.TEST_USERNAME || 'testuser';
    const PASSWORD = process.env.TEST_PASSWORD || 'bankofanthos';

    // Configure Synthetics
    syntheticsConfiguration.setConfig({
        screenshotOnStepStart: true,
        screenshotOnStepSuccess: true,
        screenshotOnStepFailure: true
    });

    let page = await synthetics.getPage();

    // Set viewport
    await page.setViewport({ width: 1920, height: 1080 });

    // Step 1: Navigate to login page
    await synthetics.executeStep('Navigate to Login', async function () {
        log.info(`Navigating to: ${URL}/login`);
        await page.goto(`${URL}/login`, { waitUntil: 'networkidle2', timeout: 30000 });

        // Verify login form exists
        await page.waitForSelector('input[name="username"]', { timeout: 10000 });
        await page.waitForSelector('input[name="password"]', { timeout: 10000 });
        log.info('Login page loaded successfully');
    });

    // Step 2: Enter credentials
    await synthetics.executeStep('Enter Credentials', async function () {
        log.info(`Entering username: ${USERNAME}`);

        // Clear and type username
        await page.click('input[name="username"]', { clickCount: 3 });
        await page.type('input[name="username"]', USERNAME);

        // Clear and type password
        await page.click('input[name="password"]', { clickCount: 3 });
        await page.type('input[name="password"]', PASSWORD);

        log.info('Credentials entered');
    });

    // Step 3: Submit login form
    await synthetics.executeStep('Submit Login', async function () {
        log.info('Submitting login form');

        // Find and click login button
        const loginButton = await page.$('button[type="submit"]');
        if (!loginButton) {
            throw new Error('Login button not found');
        }

        await Promise.all([
            page.waitForNavigation({ waitUntil: 'networkidle2', timeout: 30000 }),
            loginButton.click()
        ]);

        log.info('Login form submitted');
    });

    // Step 4: Verify successful login
    await synthetics.executeStep('Verify Login Success', async function () {
        log.info('Verifying login success');

        // Check for elements that indicate successful login
        // Bank of Anthos shows account balance after login
        const currentUrl = page.url();
        log.info(`Current URL: ${currentUrl}`);

        // Should be redirected to home/dashboard
        if (currentUrl.includes('/login')) {
            throw new Error('Still on login page - login may have failed');
        }

        // Look for balance or account information
        try {
            await page.waitForSelector('.account-balance, .balance, [class*="balance"]', { timeout: 10000 });
            log.info('Account balance element found - login successful');
        } catch (e) {
            // Alternative: check for logout button or user menu
            const logoutLink = await page.$('a[href*="logout"], button[onclick*="logout"], .logout');
            if (logoutLink) {
                log.info('Logout link found - login successful');
            } else {
                log.warn('Could not verify login success via UI elements, but not on login page');
            }
        }

        log.info('Login flow completed successfully!');
    });
};

exports.handler = async () => {
    return await flowBuilderBlueprint();
};
