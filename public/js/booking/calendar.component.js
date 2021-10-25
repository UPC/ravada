'use strict';

export default {
    bindings: {
        userId: '<',
        editable: '<'
    },
    template: '<div id="rvdCalendar"></div>',
    controller: calendarCtrl
}
calendarCtrl.$inject = ['$element', '$window', 'apiBookings','$uibModal','moment','apiEntry'];

function calendarCtrl($element, $window, apiBookings,$uibModal,moment,apiEntry) {
    const self = this;
    const parseDate = (data, time) => data + "T" + time;
    const TimeFormat = {
            hour: '2-digit',
            minute: '2-digit',
            hour12: false,
            omitZeroMinute: false
    };
    let calendar;
    moment.updateLocale('en', {
        week: {
            dow: 1,
        }
    });
    self.$postLink = () => {
        const calendarEl = $element.find("#rvdCalendar")[0];
        calendar = new FullCalendar.Calendar(calendarEl, {
            initialView: 'timeGridWeek',
            firstDay: 1,
            allDaySlot: false,
            selectOverlap: false,
            editable: false,
            selectable: !!self.editable,
            events: getEvents,
            select: newEntry,
            eventClick: editEntry,
            headerToolbar: {
                left: 'dayGridMonth,timeGridWeek,timeGridDay,listWeek',
                center: 'title',
                end: 'today prev,next'
            },
            customButtons: {
                create: {
                    text: 'Crea',
                    click: function () {
                        $window.location.href = "/booking/new.html"
                    }
                },
            },
            slotLabelFormat: TimeFormat,
            eventTimeFormat: TimeFormat,
            views: {
                timeGrid: {
                    slotMinTime: "08:00:00",
                    slotMaxTime: "21:00:00"
                },
            },
            businessHours: {
                // days of week. an array of zero-based day of week integers (0=Sunday)
                daysOfWeek: [1, 2, 3, 4,5],
                startTime: '08:00', // a start time (10am in this example)
                endTime: '21:00',
            }
        });
        calendar.render();
    }

    function getEvents(info, successCallback, failureCallback) {
        const date_start = info.startStr.valueOf().slice(0,10);
        const date_end = info.endStr.valueOf().slice(0,10);
        apiBookings.get({date_start, date_end},
            res => {
                successCallback(
                    Array.prototype.slice.call( // convert to array
                        res.data
                    ).map(ev => ({
                            id: ev.id,
                            groupId: ev.id_booking,
                            start: parseDate(ev.date_booking, ev.time_start),
                            end: parseDate(ev.date_booking, ev.time_end),
                            title: ev.title,
                            backgroundColor: ev.background_color,
                            extendedProps: {}
                        })
                    )
                )
            },
            err => failureCallback(err)
        );
    }

    function openEntry(entry) {
        return $uibModal.open({
            component: 'rvdEntryModal',
            size: 'md',
            backdrop: 'static',
            keyboard: false,
            resolve: {
                info: () => entry
            }
        })
    }
    function newEntry(selectionInfo) {
        // parameter object details in https://fullcalendar.io/docs/select-callback
        const booking_entry = {
            title: '',
            date_booking: moment(selectionInfo.startStr).format("YYYY-MM-DD"),
            date_end : moment(selectionInfo.endStr).format("YYYY-MM-DD"),
            time_start : moment(selectionInfo.startStr).format("HH:mm"),
            time_end : moment(selectionInfo.endStr).format("HH:mm"),
            dow : [0,0,0,0,0,0,0],
            editable: true,
            background_color: "#7ab2fa",
            ldap_groups: []
        };
        const today_dow = moment(selectionInfo.startStr).weekday();
        booking_entry.dow[today_dow]=today_dow+1;
        booking_entry.day_of_week = booking_entry.dow.join("");
        openEntry(booking_entry).result.then(
            () => calendar.refetchEvents() // ok
        )
    }
    async function editEntry(eventClickInfo) {
        // parameter object details in https://fullcalendar.io/docs/eventClick
        const res = await apiEntry.get({ id: eventClickInfo.event.id}).$promise;
        const resBooking = await apiBookings.get({ id_booking: eventClickInfo.event.groupId}).$promise;
        res.editable = self.userId === resBooking.id_owner && self.editable;
        res.background_color = resBooking.background_color;
        res.id_owner = resBooking.id_owner;
        await openEntry(res).result;
        calendar.refetchEvents();
    }
}
