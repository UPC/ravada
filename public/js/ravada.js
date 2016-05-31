angular.module("ravada.app",[])
 
.controller("new_base",[ '$scope', '$http', function($scope, $http) {
    $http.get('/list_images.json').then(function(response) {
            $scope.images = response.data;
    });
    
}])

.directive("solShowNewbase",function() {
  return {
    restrict: "E",
    templateUrl: '/templates/new_base.html',
  };
})
