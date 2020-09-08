'use strict';

export default {
    bindings: {
        entry: '<',
        onSave: '&',
        onCancel: '&'
    },
    templateUrl: '/js/booking/formEvent.component.html',
    controller: formEventCtrl
}

formEventCtrl.$inject = ["moment", "$scope", "apiBookings","toast","apiEntry"]

function formEventCtrl(moment, $scope, apiBookings,toast,apiEntry) {
    const self = this;
    const showResponse = res => {
        if (res.error) {
            toast.create({
                message: res.error,
                className: 'alert-danger',
            });
        } else {
            self.onSave();
            toast.create({
                message: 'Event saved successfully',
                className: 'alert-success',
            });
        }
    };
    self.cal = {};
    self.confirm_update = false;
    self.confirm_delete = false;
    moment.updateLocale('en', {
        week: {
            dow: 1,
        }
    });

    self.dow = moment.weekdaysShort(true);
    self.$onInit = () => {
        self.isNew = !Object.hasOwnProperty.call(self.entry,"id") || !self.entry.id;
        self.entry_parsed = {
            date_booking: moment(self.entry.date_booking).toDate(),
            date_end: moment(self.entry.date_end).toDate()
        }
    }

    self.confirmCancel = () => self.confirm_update=self.confirm_delete=false;
    self.openCal = id => self.cal[id] = true;
    self.remove = () => self.confirm_delete = true;
    self.remove_entry = mode => apiEntry.delete({ id:self.entry.id, mode }, res => showResponse(res));
    self.save = () => {
        if (!self.isNew) {
            self.confirm_update = true;
            return;
        }
        if (!Object.prototype.hasOwnProperty.call(self.entry, 'repeat') || self.entry["repeat"] === "") {
            self.entry.dow = '';
            self.entry.date_end = undefined;
        }
        apiBookings.save({}, self.entry, res => showResponse(res));
    };

    self.save_entry = mode =>
        apiEntry.save({id: self.entry.id},
            Object.assign(self.entry, {mode}),
            res => showResponse(res)
        );

    self.update_booking_dow = () => {
        self.entry.day_of_week = self.entry.dow.join("");
        //self.check_conflicts()
    };
    self.updateDates = () => {
        Object.assign(self.entry,{
            date_booking: moment(self.entry_parsed.date_booking).format("YYYY-MM-DD"),
            date_end: moment(self.entry_parsed.date_end).format("YYYY-MM-DD")
        });
    }


}
