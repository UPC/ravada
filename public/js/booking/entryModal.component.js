'use strict';

export default {
    bindings: {
        modalInstance: "<",
        resolve: "<"
    },
    templateUrl: "/booking/entryModal.component.html",
    controller: modalCtrl
}

function modalCtrl() {
    const self = this;
    self.$onInit = () => {
        self.eventInfo = self.resolve.info
    }
    self.cancel =  () => self.modalInstance.dismiss("cancel");
    self.formSaved = () => self.modalInstance.close();
}
