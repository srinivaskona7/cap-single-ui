using my.bookshop as my from '../db/schema';

service CatalogService {
    entity Books as projection on my.Books;

    annotate Books with @(restrict: [
        {
            grant: 'READ',
            to   : 'kymacapnodejsviewer1'
        },
        {
            grant: [
                'READ',
                'WRITE'
            ],
            to   : 'Admin'
        }
    ]);

    /**
     * Defines the custom function to get user information.
     * It returns a structure containing the user's name.
     */
    @requires: 'authenticated-user'
    function userInfo()     returns {
        name : String;
    };

    @requires: 'kymacapnodejsviewer1'
    function isAuthorized() returns Boolean;
}
