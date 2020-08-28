'use strict';

export default {
    bindings: {
        modalInstance: "<",
        resolve: "<"
    },
    templateUrl: "/js/booking/entryModal.component.html",
    controller: modalCtrl
}

function modalCtrl() {
    var self = this;
    self.$onInit = () => {
        self.eventInfo = self.resolve.info
    }
    self.ok = () => {
        console.info("in handle close");
        self.modalInstance.close();
    };
    self.cancel = function() {
        console.info("in handle dismiss");
        self.modalInstance.dismiss("cancel");
    };
}
