const cds = require('@sap/cds');

/**
 * Service implementation for the CatalogService.
 * This file provides the custom business logic for the service's entities and functions.
 */
module.exports = cds.service.impl(async function() {

    /**
     * Custom handler for the userInfo() function.
     * It retrieves the user's ID from the request object and returns it.
     */
    this.on('userInfo', (req) => {
        // The 'req.user.id' property contains the login name of the authenticated user.
        // A fallback to 'anonymous' is provided if no user is authenticated.
        const name = req.user ? req.user.id : 'anonymous';
        return { name: name };
    });

    this.on('isAuthorized', () => {
        return true;
    });
});