'use strict';

import calendarComponent from './calendar.component.js'
import confirmActions from './confirmActions.component.js'
import entryModalComponent from "./entryModal.component.js"
import formEventComponent from "./formEvent.component.js"
import ldapGroupsComponent from "./ldapGroups.component.js"
import localGroupsComponent from "./localGroups.component.js"
import timeComponent from "./time.component.js"
import { svcBookings, svcEntry, svcLDAP, svcLocal } from "./booking.services.js"

angular.module("ravada.booking", ['ui.bootstrap','angularMoment','angularjsToast','ngMessages'])
    .component("rvdCalendar", calendarComponent)
    .component("rvdConfirmActions",confirmActions)
    .component("rvdEntryModal",entryModalComponent)
    .component("rvdFormEvent",formEventComponent)
    .component("rvdTimePicker",timeComponent)
    .component("ldapGroups", ldapGroupsComponent)
    .component("localGroups", localGroupsComponent)
    .service("apiBookings",svcBookings)
    .service("apiEntry",svcEntry)
    .service("apiLDAP",svcLDAP)
    .service("apiLocal",svcLocal)
    .run( amMoment => amMoment.changeLocale('en') );

