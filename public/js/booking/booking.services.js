'use strict';

export {
    svcBookings
}

svcBookings.$inject = ["$resource"];

function svcBookings($resource) {
    const url = '/v1/booking/:range/:date';

    return $resource(url, {range: '@range', date: '@date'}, {
        week: {
            method: 'GET',
            params: {range: 'week'}
        },
    });
}
