'use strict';

import calendarComponent from './calendar.component.js'
import { svcBookings } from "./booking.services.js"

angular.module("ravada.booking", [])
    .component("rvdCalendar", calendarComponent)
    .service("apiBookings",svcBookings)
