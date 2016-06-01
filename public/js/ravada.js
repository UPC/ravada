var app = angular.module("ravada.app",[]);
 
    app.controller("new_base",[ '$scope', '$http', function($scope, $http) {

        $http.get('/list_images.json').then(function(response) {
                $scope.images = response.data;
        });

    }]);

    app.controller("SupportForm",function($scope){
        $scope.showErr = false;
        $scope.isOkey = function() {
            if($scope.contactForm.$valid){
                $scope.showErr = false;
            } else{
                $scope.showErr = true;
            }
        }

    });

    app.directive("solShowNewbase",function() {

        return {
            restrict: "E",
            templateUrl: '/templates/new_base.html',
        };

    });


