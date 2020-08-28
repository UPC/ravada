'use strict';

export default {
    bindings: {
        entry: '<'
    },
    templateUrl: '/js/booking/formEvent.component.html',
    controller: formEventCtrl
}

formEventCtrl.$inject = ["moment"]

function formEventCtrl(moment) {
    var self = this;
    self.cal = {};

    self.dow = moment.weekdaysShort();
    self.openCal = id => self.cal[id] = true;
    self.$onInit = () => {
        self.entry_parsed = {
            date_booking: moment(self.entry.date_booking).toDate(),
            date_end: moment(self.entry.date_end).toDate(),
        }
    }

    self.update_booking_dow = () => {
        self.entry.day_of_week =  self.entry.dow.join("");
        //self.check_conflicts()
    };

}
