ravadaApp.directive("solShowMachine", swMach)
        .directive("solShowNewmachine", swNewMach)
        .controller("new_machine", newMachineCtrl)
        .controller("machinesPage", machinesPageC)
        .controller("usersPage", usersPageC)
        .controller("messagesPage", messagesPageC)

  function swMach() {
    return {
      restrict: "E",
      templateUrl: '/ng-templates/admin_machine.html',
    };
  };

  function swNewMach() {
      return {
          restrict: "E",
          templateUrl: '/ng-templates/new_machine.html',
      };
  };

  function newMachineCtrl($scope, $http) {
      $http.get('/list_images.json').then(function(response) {
              $scope.images = response.data;
      });
      $http.get('/list_vm_types.json').then(function(response) {
              $scope.backends = response.data;
      });
      $http.get('/list_lxc_templates.json').then(function(response) {
              $scope.templates_lxc = response.data;
      });
  };

  function machinesPageC($scope, $http, $interval, request, listMach) {
    $http.get('/pingbackend.json').then(function(response) {
      $scope.pingbe_fail = !response.data;
    });
    $scope.getMachines = function() {
      $http.get("/list_machines.json").then(function(response) {
        $scope.list_machines = [];
        var mach;
        for (var i=0, iLength = response.data.length; i<iLength; i++){
          mach = response.data[i];
          if (!mach.id_base){
            $scope.list_machines[mach.id] = mach;
            $scope.list_machines[mach.id].childs = [];
          }
        }
        for (var i=0, iLength = response.data.length; i<iLength; i++){
          mach = response.data[i];
          if (mach.id_base){
            $scope.list_machines[mach.id_base].childs.push(mach);
          }
        }
        for (var i = $scope.list_machines.length-1; i >= 0; i--){
          if (!$scope.list_machines[i]){
            $scope.list_machines.splice(i,1);
          }
        }
      });
    };
    $scope.orderParam = ['name'];
    $scope.orderMachineList = function(type1,type2){
      if ($scope.orderParam[0] === '-'+type1)
        $scope.orderParam = ['none'];
      else if ($scope.orderParam[0] === type1 )
        $scope.orderParam = ['-'+type1,type2];
      else $scope.orderParam = [type1,'-'+type2];
    }
    $scope.hide_clones = false;
    $scope.hideClones = function(){
      $scope.hide_clones = !$scope.hide_clones;
    }
    $scope.action = function(target,action,machineId){
      $http.get('/'+target+'/'+action+'/'+machineId+'.json');
    };
    $scope.set_public = function(machineId, value) {
      $http.get("/machine/public/"+machineId+"/"+value);
    };

    //On load code
    $scope.rename= {new_name: 'new_name'};
    $scope.show_rename = false;
    $scope.new_name_duplicated=false;
    $scope.getMachines();
    $interval($scope.getMachines,3000);
  };

  function usersPageC($scope, $http, $interval, request) {
    $http.get('/pingbackend.json').then(function(response) {
      $scope.pingbe_fail = !response.data;
    });
    $scope.getUsers = function() {
      $http.get('/list_users.json').then(function(response) {
        $scope.list_users= response.data;
      });
    }
    $scope.action = function(target,action,machineId){
      $http.get('/'+target+'/'+action+'/'+machineId+'.json');
    };
    //On load code
    $scope.getUsers();
    $scope.updatePromise = $interval($scope.getUsers,3000);
  };

  function messagesPageC($scope, $http, $interval, request) {
    $http.get('/pingbackend.json').then(function(response) {
      $scope.pingbe_fail = !response.data;
    });
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
    $scope.asRead = function(messId){
        var toGet = '/messages/read/'+messId+'.json';
        $http.get(toGet);
    };
    $scope.asUnread = function(messId){
        var toGet = '/messages/unread/'+messId+'.json';
        $http.get(toGet);
    };
    //On load code
    $scope.getMessages();
    $scope.updatePromise = $interval($scope.updateMessages,3000);
  };

