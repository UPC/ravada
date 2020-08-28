'use strict';

export {
    svcBookings,
    svcLDAP
}

svcBookings.$inject = ["$resource"];

function svcBookings($resource) {
    return $resource('/v1/bookings');
}

svcLDAP.$inject = ["$resource"];

function svcLDAP($resource) {
    return $resource('/:qry',{ qry: '@qry' }, {
        list_groups: {
            method: 'GET',
            isArray: true,
            params: { qry: 'list_ldap_groups'}
        }
    });
}
