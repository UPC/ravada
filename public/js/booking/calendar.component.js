'use strict';

export default {
    template: '<div id="rvdCalendar"></div>',
    controller: calendarCtrl
}
calendarCtrl.$inject = ['$element', '$window', 'apiBookings','$uibModal','moment'];

function calendarCtrl($element, $window, apiBookings,$uibModal,moment) {
    var self = this;
    var parseDate = (data, time) => data + "T" + time;
    var TimeFormat = {
            hour: '2-digit',
            minute: '2-digit',
            hour12: false,
            omitZeroMinute: false
    };
    self.$postLink = () => {
        var calendarEl = $element.find("#rvdCalendar")[0];
        var calendar = new FullCalendar.Calendar(calendarEl, {
            initialView: 'timeGridWeek',
            firstDay: 1,
            editable: true,
            selectable: true,
            events: getEvents,
            select: newEntry,
            eventClick: editEntry,
            headerToolbar: {
                left: 'dayGridMonth,timeGridWeek,timeGridDay,listWeek create',
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
        var date_start = info.startStr.valueOf().slice(0,10);
        var date_end = info.endStr.valueOf().slice(0,10);
        apiBookings.get({date_start, date_end},
            res => {
                successCallback(
                    Array.prototype.slice.call( // convert to array
                        res.data
                    ).map(ev => ({
                            id: ev.id,
                            start: parseDate(ev.date_booking, ev.time_start),
                            end: parseDate(ev.date_booking, ev.time_end),
                            title: ev.title
                        })
                    )
                )
            },
            err => failureCallback(err)
        );
    }

    function openEntry(entry) {
        $uibModal.open({
            component: 'rvdEntryModal',
            size: 'md',
            resolve: {
                info: () => entry
            }
        })
    }
    function newEntry(selectionInfo) {
        // parameter object details in https://fullcalendar.io/docs/select-callback
        var booking_entry = {
            title: '',
            date_booking: moment(selectionInfo.startStr).format("YYYY-MM-DD"),
            date_end : moment(selectionInfo.endStr).format("YYYY-MM-DD"),
            time_start : moment(selectionInfo.startStr).format("HH:mm"),
            time_end : moment(selectionInfo.endStr).format("HH:mm"),
            dow : [0,0,0,0,0,0,0],
            ldap_groups: []
        };
        var today_dow = moment(selectionInfo.startStr,"e");
        booking_entry.dow[today_dow]=today_dow+1;
        booking_entry.day_of_week = booking_entry.dow.join("");
        openEntry(booking_entry)
    }
    function editEntry(eventClickInfo) {
        // parameter object details in https://fullcalendar.io/docs/eventClick
    }
}
