'use strict';

export {
    svcBookings,
    svcEntry,
    svcLDAP,
    svcLocal
}

svcBookings.$inject = ["$resource"];

function svcBookings($resource) {
    return $resource('/v1/bookings/:id_booking');
}

svcEntry.$inject = ["$resource"];

function svcEntry($resource) {
    return $resource('/v1/booking_entry/:id/:mode');
}

svcLDAP.$inject = ["$resource"];

function svcLDAP($resource) {
    return $resource('/:action/:qry',{ qry: '@qry' }, {
        list_groups: {
            method: 'GET',
            isArray: true,
            params: { action: 'group/ldap/list'}
        }
    });
}

svcLocal.$inject = ["$resource"];

function svcLocal($resource) {
    return $resource('/:action/:qry',{ qry: '@qry' }, {
        list_groups: {
            method: 'GET',
            isArray: true,
            params: { action: 'group/local/list'}
        }
    });
}
