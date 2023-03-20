'use strict';

export default {
    templateUrl: '/booking/confirmActions.component.html',
    controller: actCtrl,
    bindings: {
        modalInstance: "<",
        resolve: "<"
    }
}

function actCtrl() {
    const self = this;
    self.confirm = {
        type: 'current'
    };
    const types = {
        'modify' : {
            title: 'Edit the event'
        },
        'delete' : {
            title: 'Delete the event'
        }
    }
    self.$onInit = () => {
        let type = self.resolve.type || 'modify';
        self.title = types[type].title
    }
    self.onCancel =  () => self.modalInstance.dismiss("cancel");
    self.onConfirm = () => self.modalInstance.close(self.confirm.type);
}
