
ravadaApp.directive("solShowAdminNavigation", swAdminNavigation)
        .directive("solShowAdminContent", swAdminContent)

    function swAdminNavigation() {

        return {
            restrict: "E",
            templateUrl: '/templates/admin_nav.html',
        };

    };

    function swAdminContent() {

        return {
            restrict: "E",
            templateUrl: '/templates/admin_cont.html',
        };

    };
