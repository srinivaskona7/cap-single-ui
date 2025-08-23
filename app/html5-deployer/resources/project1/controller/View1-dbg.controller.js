sap.ui.define([
    "sap/ui/core/mvc/Controller",
    "sap/ui/model/json/JSONModel"
], (Controller, JSONModel) => {
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
        }
    });
});