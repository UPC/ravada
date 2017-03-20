ravadaApp.directive("solShowAdminNavigation", swAdminNavigation)
        .directive("solShowMessages", swMess)
        .directive("solShowMachine", swMach)
        .controller("adminPage", adminPageC)
        .controller("messages", messagesCrtl)
        .controller("notifCrtl", notifCrtl)

  function swAdminNavigation() {
    return {
      restrict: "E",
      templateUrl: '/ng-templates/admin_nav.html',
    };
  };
  function swMess() {
    return {
      restrict: "E",
      templateUrl: '/ng-templates/list_messages.html',
    };
  };
  function swMach() {
    return {
      restrict: "E",
      templateUrl: '/ng-templates/admin_machine.html',
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
    $scope.getUsers = function() {
      $http.get('/list_users.json').then(function(response) {
        $scope.list_users= response.data;
      });
    }
    $scope.getMessages = function() {
      $http.get('/messages.json').then(function(response) {
        $scope.list_message= response.data;
      });
    }
    $scope.updateMessages = function() {
      $http.get('/messages.json').then(function(response) {
        for (var i=0, iLength = response.data.length; i<iLength; i++){
          if (response.data[0].id != $scope.list_message[i].id){
            $scope.list_message.splice(i,0,response.data.shift());
          }
          else{break;}
        }
      });
    }
    $scope.getMachines = function() {
      $http.get("/list_machines.json").then(function(response) {
        $scope.list_machines= response.data;
      });
    };
    $scope.getSingleMachine = function(){
      $scope.getMachines();
      $scope.showmachine = getMachineById($scope.list_machines,$scope.showmachineId);
    }
    $scope.show = function(type,id){
      $interval.cancel($scope.updatePromise);
      switch(type){
        case 'machines':
        $scope.getMachines();
        $scope.updatePromise = $interval($scope.getMachines,3000);
        break;
        case 'users':
        $scope.getUsers();
        $scope.updatePromise = $interval($scope.getUsers,3000);
        break;
        case 'messages':
        $scope.getMessages();
        $scope.updatePromise = $interval($scope.updateMessages,3000);
        break;
        case 'machine':
        $scope.showmachineId = id;
        $scope.getSingleMachine();
        $scope.updatePromise = $interval($scope.getSingleMachine,3000);
        break;
      }
      $scope.showing = type;
    }
    $scope.orderParam = "";
    $scope.reverse = true;
    $scope.increment = 0;
    $scope.orderMachineList = function(){
      $scope.increment++;
      switch ($scope.increment) {
        case 1:
        case 2:
          $scope.orderParam = 'name';
          $scope.reverse = !$scope.reverse;
          break;
        case 3:
          $scope.orderParam = '';
          $scope.increment = 0;
          break;
      }
    }
    $scope.action = function(target,action,machineId){
      $http.get('/'+target+'/'+action+'/'+machineId+'.json');
    };
    $scope.rename = function(machineId, old_name) {
      if (old_name == $scope.rename.new_name) {
        $scope.show_rename= false;
        return;
      }
      $http.get('/machine/rename/'+machineId+'/'
      +$scope.rename.new_name);
      alert('Rename machine '+old_name
      +' to '+$scope.rename.new_name
      +'. It may take some seconds to complete.');
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

    //On load code
    $scope.rename= {new_name: 'new_name'};
    $scope.show_rename = false;
    $scope.new_name_duplicated=false;
    $scope.show('machines',-1);
  };

  function messagesCrtl($scope, $http, request) {
      $scope.asRead = function(messId){
          var toGet = '/messages/read/'+messId+'.json';
          $http.get(toGet);
      };
      $scope.asUnread = function(messId){
          var toGet = '/messages/unread/'+messId+'.json';
          $http.get(toGet);
      };
  };

  function notifCrtl($scope, $interval, $http, request){
    $scope.getAlerts = function() {
      $http.get('/unshown_messages.json').then(function(response) {
              $scope.alerts= response.data;
      });
    };
    $interval($scope.getAlerts,10000);
    $scope.closeAlert = function(index) {
      var message = $scope.alerts.splice(index, 1);
      var toGet = '/messages/read/'+message[0].id+'.html';
      $http.get(toGet);
    };
  }
