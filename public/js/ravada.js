var app = angular.module("ravada.app",[]);
 
    app.controller("new_machine",[ '$scope', '$http', function($scope, $http) {

        $http.get('/list_images.json').then(function(response) {
                $scope.images = response.data;
        });

    }]);

    app.controller("SupportForm",function($scope){
        this.user = {};
        $scope.showErr = false;
        $scope.isOkey = function() {
            if($scope.contactForm.$valid){
                $scope.showErr = false;
            } else{
                $scope.showErr = true;
            }
        }

    });

    app.directive("solShowSupportform",function() {

        return {
            restrict: "E",
            templateUrl: '/templates/support_form.html',
        };

    });

    app.directive("solShowNewmachine",function() {

        return {
            restrict: "E",
            templateUrl: '/templates/new_machine.html',
        };

    });

// list machines
    app.controller("machines",[ '$scope', '$http', function($scope, $http) {

        $http.get('/list_machines.json').then(function(response) {
                $scope.list_machines= response.data;
        });

    }]);

    app.directive("solShowListmachines",function() {

        return {
            restrict: "E",
            templateUrl: '/templates/list_machines.html',
        };

    });

    app.directive("solShowCardsmachines",function() {

        return {
            restrict: "E",
            templateUrl: '/templates/user_machines.html',
        };

    });
