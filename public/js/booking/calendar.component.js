'use strict';

export default {
    template: '<div id="rvdCalendar"></div>',
    controller: calendarCtrl
}
calendarCtrl.$inject = ['$element', '$window', 'apiBookings'];

function calendarCtrl($element, $window, apiBookings) {
    var self = this;
    var calendar;
    var parseDate = (data, time) => data + "T" + time;
    var TimeFormat = {
            hour: '2-digit',
            minute: '2-digit',
            hour12: false,
            omitZeroMinute: false
    };
    self.$postLink = () => {
        var calendarEl = $element.find("#rvdCalendar")[0];
        calendar = new FullCalendar.Calendar(calendarEl, {
            initialView: 'timeGridWeek',
            firstDay: 1,
            events: getEvents,
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

}
