'use strict';

export default {
    bindings: {
        entry: '<',
        onSave: '&',
        onCancel: '&'
    },
    templateUrl: '/booking/formEvent.component.html',
    controller: formEventCtrl
}

formEventCtrl.$inject = ["moment", "$scope", "apiBookings", "toast", "apiEntry", "$uibModal"]

function formEventCtrl(moment, $scope, apiBookings, toast, apiEntry, $uibModal) {
    // init
    const self = this;
    const conflictFields = ["date_start", "date_end", "time_start", "time_end", "day_of_week", "id"];
    const showError = err => toast.create({
        message: err,
        className: 'alert-danger',
    });
    const showResponse = res => {
        if (res.error) showError(res.error)
        else {
            self.onSave();
            toast.create({
                message: 'Event saved successfully',
                className: 'alert-success',
            });
        }
    };

    self.cal = {};
    self.dateFormat = "EEEE dd MMMM yyyy";
    self.dow = moment.weekdaysShort(true);

    self.$onInit = () => {
        self.isNew = !Object.hasOwnProperty.call(self.entry, "id") || !self.entry.id;
        self.entry_parsed = {
            date_booking: moment(self.entry.date_booking).toDate(),
            date_end: moment(self.entry.date_end).toDate()
        }
        self.updateDates();
        self.entry_clone = angular.copy(self.entry);
    }
    // Called on each turn of the digest cycle. Detect entry changes
    self.$doCheck = () => {
        if (!angular.equals(self.entry_clone, self.entry)) {
            const fieldsConflictModif = Object.keys(self.entry)
                .filter(k => self.entry[k] !== self.entry_clone[k])
                .filter(field => conflictFields.includes(field))
            if (fieldsConflictModif.length) check_conflicts();
            self.entry_clone = angular.copy(self.entry);
        }
    }

    // methods

    const check_conflicts = () => {
        let filtred = {};
        conflictFields.forEach(k => filtred[k] = self.entry[k]);
        apiBookings.get(filtred, res => self.conflicts = res.data)
    }

    self.hasConflicts = () => !!(self.conflicts && self.conflicts.length);
    self.openCal = id => self.cal[id] = true;
    self.openConfirm = type => {
        return $uibModal.open({
            component: 'rvdConfirmActions',
            size: 'md',
            backdrop: 'static',
            keyboard: false,
            resolve: {
                type: () => type
            }
        });
    }
    self.remove = () => self.openConfirm('delete').result.then(
        mode => self.remove_entry(mode)
    )
    self.remove_entry = mode => apiEntry.delete({id: self.entry.id, mode},
        res => showResponse(res),
        () => showError("Server error on delete")
    );
    self.save = () => {
        if (!self.isNew) {
            self.openConfirm('modify').result.then(
                mode => self.save_entry(mode)
            )
            return;
        }
        if (!Object.prototype.hasOwnProperty.call(self.entry, 'repeat') || self.entry["repeat"] === "") {
            self.entry.dow = '';
            self.entry.date_end = undefined;
        }
        apiBookings.save({}, self.entry,
            res => showResponse(res),
            () => showError("Server error on save")
        );
    };

    self.save_entry = mode =>
        apiEntry.save({id: self.entry.id},
            Object.assign(self.entry, {mode}),
            res => showResponse(res),
            err => showError("Server error on save entry")
        );

    self.update_booking_dow = () => self.entry.day_of_week = self.entry.dow.join("");

    self.updateDates = () => {
        // check and update date_end limit
        if (!self.entry.repeat
            || (self.entry.repeat && moment(self.entry_parsed.date_booking).isAfter(self.entry_parsed.date_end)))
            self.entry_parsed.date_end = self.entry_parsed.date_booking

        // update main model entry
        Object.assign(self.entry, {
            date_booking: moment(self.entry_parsed.date_booking).format("YYYY-MM-DD"),
            date_end: moment(self.entry_parsed.date_end).format("YYYY-MM-DD")
        });
        self.entry.date_start = self.entry.date_booking;

        // update dow
        if (!self.entry.repeat) resetDow();

        // set calendar limits
        setDateLimits();
    }
    const setDateLimits = () => {
        self.optionsDateEnd = {
            minDate: new Date(self.entry.date_booking)
        }
    }

    const resetDow = () => {
        self.entry.dow = [0, 0, 0, 0, 0, 0, 0];
        const actual_dow = moment(self.entry_parsed.date_booking).weekday();
        self.entry.dow[actual_dow] = actual_dow + 1;
        self.update_booking_dow();
    }

}
