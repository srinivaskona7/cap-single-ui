sap.ui.define([
    "sap/ui/core/mvc/Controller",
    "sap/ui/model/json/JSONModel",
    "sap/m/ColumnListItem",
    "sap/m/Text"
], (Controller, JSONModel, ColumnListItem, Text) => {
    "use strict";

    return Controller.extend("project1.controller.View1", {
        onInit() {
            const userModel = new JSONModel();
            this.getView().setModel(userModel, "user");

            const odataModel = this.getOwnerComponent().getModel();
            const oContext = odataModel.bindContext("/userInfo()");

            oContext.requestObject().then((data) => {
                userModel.setProperty("/email", data.name);
            });

            const oRouter = this.getOwnerComponent().getRouter();
            oRouter.getRoute("RouteView1").attachPatternMatched(this.onRoutePatternMatched, this);
        },

        onRoutePatternMatched: function() {
            const oTable = this.byId("booksTable");
            const oMessageStrip = this.byId("authMessage");
            const odataModel = this.getOwnerComponent().getModel();

            const oAuthContext = odataModel.bindContext("/isAuthorized()");
            oAuthContext.requestObject().then(() => {
                // User is authorized
                oTable.bindItems({
                    path: "/Books",
                    template: new ColumnListItem({
                        cells: [
                            new Text({ text: "{ID}" }),
                            new Text({ text: "{title}" }),
                            new Text({ text: "{stock}" })
                        ]
                    })
                });
            }).catch((oError) => {
                if (oError && /403|forbidden/i.test(oError.message)) {
                    // User is not authorized
                    oTable.setVisible(false);
                    oMessageStrip.setVisible(true);
                }
            });
        }
    });
});