'use strict';

export {
    svcBookings
}

svcBookings.$inject = ["$resource"];

function svcBookings($resource) {
    return $resource('/v1/bookings');
}
