sap.ui.define(
  [
    "sap/ui/core/mvc/Controller",
    "sap/ui/model/json/JSONModel",
    "sap/m/ColumnListItem",
    "sap/m/ObjectIdentifier",
    "sap/m/ObjectNumber",
    "sap/m/Text",
    "sap/m/Dialog",
    "sap/m/Button",
    "sap/m/Label",
    "sap/m/Input",
    "sap/m/MessageToast",
    "sap/m/MessageBox",
    "sap/m/VBox",
    "sap/ui/model/Filter",
    "sap/ui/model/FilterOperator"
  ],
  (
    Controller,
    JSONModel,
    ColumnListItem,
    ObjectIdentifier,
    ObjectNumber,
    Text,
    Dialog,
    Button,
    Label,
    Input,
    MessageToast,
    MessageBox,
    VBox,
    Filter,
    FilterOperator
  ) => {
    "use strict";

    return Controller.extend("project1.controller.View1", {
      onInit() {
        const userModel = new JSONModel();
        this.getView().setModel(userModel, "user");

        const odataModel = this.getOwnerComponent().getModel();
        const oContext = odataModel.bindContext("/userInfo()");

        oContext.requestObject().then((data) => {
             userModel.setProperty("/email", data.name);
           }).catch(() => {
             userModel.setProperty("/email", "Guest");
           });

        const oRouter = this.getOwnerComponent().getRouter();
        oRouter.getRoute("RouteView1").attachPatternMatched(this.onRoutePatternMatched, this);
      },

      onRoutePatternMatched: function () {
        const oTable = this.byId("booksTable");
        const oMessageStrip = this.byId("authMessage");
        const odataModel = this.getOwnerComponent().getModel();

        // Check Authorization
        const oAuthContext = odataModel.bindContext("/isAuthorized()");
        oAuthContext.requestObject().then(() => {
            // User is authorized
            // Note: Template is now defined in XML View for cleaner separation
            oTable.bindItems({
              path: "/Books",
              template: new ColumnListItem({
                type: "Inactive",
                cells: [
                  new ObjectIdentifier({ title: "{ID}" }),
                  new Text({ text: "{title}" }),
                  new ObjectNumber({ 
                      number: "{stock}",
                      state: {
                          path: 'stock',
                          formatter: function(s) { return s > 10 ? 'Success' : 'Error'; }
                      }
                  }),
                  new Button({ icon: "sap-icon://delete", type: "Transparent", press: this.onDeleteBookButton.bind(this) })
                ]
              })
            });
          }).catch((oError) => {
            if (oError && /403|forbidden/i.test(oError.message)) {
              oTable.setVisible(false);
              oMessageStrip.setVisible(true);
            }
          });
      },

      onSearchBook: function(oEvent) {
          const sQuery = oEvent.getParameter("query");
          const oTable = this.byId("booksTable");
          const oBinding = oTable.getBinding("items");
          const aFilters = [];
          
          if (sQuery) {
              aFilters.push(new Filter("title", FilterOperator.Contains, sQuery));
          }
          oBinding.filter(aFilters);
      },

      onDeleteBookButton: function(oEvent) {
          const oItem = oEvent.getSource().getParent(); // The ColumnListItem
          this._deleteItem(oItem);
      },

      onDeleteBook: function(oEvent) {
          const oItem = oEvent.getParameter("listItem"); // For swipe/delete mode
          this._deleteItem(oItem);
      },

      _deleteItem: function(oItem) {
          const oContext = oItem.getBindingContext();
          const sTitle = oContext.getProperty("title");

          MessageBox.confirm(`Are you sure you want to delete "${sTitle}"?`, {
              onClose: (oAction) => {
                  if (oAction === MessageBox.Action.OK) {
                      oContext.delete().then(() => {
                          MessageBox.success(`Book "${sTitle}" deleted successfully!`);
                      }).catch((oError) => {
                           MessageBox.error("Delete Failed: " + oError.message);
                      });
                  }
              }
          });
      },

      onAddBook: function () {
        if (!this.oDialog) {
          this.oNewBookModel = new JSONModel({ ID: null, title: "", stock: null });
          this.oDialog = new Dialog({
            title: "Add New Book",
            type: "Message",
            content: new VBox({
              items: [
                new Label({ text: "ID (Integer)", labelFor: "idInput" }),
                new Input("idInput", { value: "{new>/ID}", type: "Number" }),
                new Label({ text: "Title", labelFor: "titleInput" }),
                new Input("titleInput", { value: "{new>/title}" }),
                new Label({ text: "Stock (Integer)", labelFor: "stockInput" }),
                new Input("stockInput", { value: "{new>/stock}", type: "Number" }),
              ],
            }).addStyleClass("sapUiSmallMargin"),
            beginButton: new Button({ text: "Save", type: "Emphasized", press: this.onSaveBook.bind(this) }),
            endButton: new Button({ text: "Cancel", press: function () { this.oDialog.close(); }.bind(this) }),
          });
          this.oDialog.setModel(this.oNewBookModel, "new");
          this.getView().addDependent(this.oDialog);
        }
        this.oNewBookModel.setData({ ID: null, title: "", stock: null });
        this.oDialog.open();
      },

      onSaveBook: function () {
        const oData = this.oNewBookModel.getData();
        if (!oData.ID || !oData.title) {
          MessageToast.show("ID and Title are required.");
          return;
        }
        const oModel = this.getOwnerComponent().getModel();
        const oBindList = oModel.bindList("/Books");
        try {
          const oContext = oBindList.create({
            ID: parseInt(oData.ID),
            title: oData.title,
            stock: oData.stock ? parseInt(oData.stock) : 0,
          });
          oContext.created().then(() => {
              MessageBox.success("Book created successfully!");
              this.oDialog.close();
              this.byId("booksTable").getBinding("items").refresh();
            }).catch((oError) => {
              MessageBox.error("Creation Failed: " + (oError.message || "Unknown Error"));
            });
        } catch (e) {
          MessageBox.error("Error: " + e.message);
        }
      },
    });
  }
);
