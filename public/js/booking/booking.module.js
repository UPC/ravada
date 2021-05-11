'use strict';

import calendarComponent from './calendar.component.js'
import confirmActions from './confirmActions.component.js'
import entryModalComponent from "./entryModal.component.js"
import formEventComponent from "./formEvent.component.js"
import ldapGroupsComponent from "./ldapGroups.component.js"
import timeComponent from "./time.component.js"
import { svcBookings, svcEntry, svcLDAP } from "./booking.services.js"

angular.module("ravada.booking", ['ui.bootstrap','angularMoment','angularjsToast','ngMessages'])
    .component("rvdCalendar", calendarComponent)
    .component("rvdConfirmActions",confirmActions)
    .component("rvdEntryModal",entryModalComponent)
    .component("rvdFormEvent",formEventComponent)
    .component("rvdTimePicker",timeComponent)
    .component("ldapGroups", ldapGroupsComponent)
    .service("apiBookings",svcBookings)
    .service("apiEntry",svcEntry)
    .service("apiLDAP",svcLDAP)
    .run( amMoment => amMoment.changeLocale('en') );

