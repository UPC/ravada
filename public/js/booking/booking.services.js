'use strict';

export {
    svcBookings,
    svcEntry,
    svcLDAP
}

svcBookings.$inject = ["$resource"];

function svcBookings($resource) {
    return $resource('/v1/bookings/:id');
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
            params: { action: 'list_ldap_groups'}
        }
    });
}
