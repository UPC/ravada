
ravadaApp.directive("solShowAdminNavigation", swAdminNavigation)
        .directive("solShowAdminContent", swAdminContent)
        .controller("adminPage", adminPageC)

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

  function getMachineById(array, value) {
    for (var i=0, iLength=array.length; i<iLength; i++) {
      if (array[i].id == value) return array[i];
    }
    return null;
  }
  function adminPageC($scope, $http, $interval, request, listMach) {
    $http.get('/pingbackend.json').then(function(response) {
      $scope.pingbe_fail = !response.data;
    });
    $scope.showing = 'machines';
    $scope.showMachines = function(){
      $scope.showing = 'machines';
    }
    $scope.showUsers = function(){
      $scope.showing = 'users';
    }
    $scope.showMachine = function(machineId){
      $scope.showmachine = getMachineById($scope.list_machines,machineId);
      $scope.showing = 'machine';
    }
    $scope.getUsers = function() {
      $http.get('/list_users.json').then(function(response) {
        $scope.list_users= response.data;
      });
    }
    $scope.getUsers();
    $interval($scope.getUsers,1000);

    $scope.rename= {new_name: 'new_name'};
    $scope.show_rename = false;
    $scope.new_name_duplicated=false;
    $scope.getMachines = function() {
      $http.get("/list_machines.json").then(function(response) {
        $scope.list_machines= response.data;
      });
    };
    $scope.getMachines();
    $interval($scope.getMachines,1000);

    $scope.action = function(target,action,machineId){
      $http.get('/'+target+'/'+action+'/'+machineId+'.json');
    };

    $scope.rename = function(machineId, old_name) {
      if (old_name == $scope.rename.new_name) {
        // why the next line does nothing ?
        $scope.show_rename= false;
        return;
      }
      $http.get('/machine/rename/'+machineId+'/'
      +$scope.rename.new_name);
      alert('Rename machine '+old_name
      +' to '+$scope.rename.new_name
      +'. It may take some seconds to complete.');
      // why the next line does nothing ?
      $scope.show_rename= false;
    };

    $scope.validate_new_name = function(old_name) {
      if(old_name == $scope.rename.new_name) {
        $scope.new_name_duplicated=false;
        return;
      }
      $http.get('/machine/exists/'+$scope.rename.new_name)
      .then(duplicated_callback, unique_callback);
      function duplicated_callback(response) {
        $scope.new_name_duplicated=response.data;
      };
      function unique_callback() {
        $scope.new_name_duplicated=false;
      }
    };

    $scope.set_public = function(machineId, value) {
      $http.get("/machine/public/"+machineId+"/"+value);
    };
  };
