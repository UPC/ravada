(function() {

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

    $http.get('/list_vm_types.json').then(function(response) {
            $scope.backends = response.data;
            $scope.backend = response.data[0];
            $scope.loadTemplates();
    });
      $scope.loadTemplates = function() {
        $http.get('/list_images.json',{
          params: {
            backend: $scope.backend
          }
        }).then(function(response) {
                $scope.images = response.data;
        });
      }
      $http.get('/iso_file.json').then(function(response) {
              $scope.isos = response.data;
      });


      $http.get('/list_lxc_templates.json').then(function(response) {
              $scope.templates_lxc = response.data;
      });
      $scope.iso_download=function(id_iso) {
            $http.get('/iso/download/'+id_iso+'.json').then(function() {
                window.location.href = '/admin/machines';
            });
      };
      $scope.name_duplicated = false;
    
      $scope.ddsize=20;
      $scope.swapsize={value:1};
      $scope.ramSize=1;
      $scope.seeswap=0;

      $scope.showMinSize = false;
      $scope.min_size = 15;
      $scope.change_iso = function(id) {
          if (id.min_disk_size != null) {
            $scope.min_size = id.min_disk_size;
            $scope.showMinSize = true;
          }
          else {
            $scope.showMinSize = false;
            $scope.min_size = 1;
          }
          if (id.device != null) {
             return id.device;
          }
          else return "<NONE>";
      };

      $scope.validate_new_name = function() {
          $http.get('/machine/exists/'+$scope.name)
                .then(duplicated_callback, unique_callback);
            function duplicated_callback(response) {
                if ( response.data ) {
                    $scope.name_duplicated=true;
                } else {
                    $scope.name_duplicated=false;
                }
            };
            function unique_callback() {
                $scope.name_duplicated=false;
            }
      };

      $scope.type = function(v) {
        return typeof(v);
      }
      $scope.show_swap = function() {
        $scope.seeswap = !($scope.seeswap);
      };

    
      $http.get('/list_machines.json').then(function(response) {
              $scope.base = response.data;
      });
  };

  function machinesPageC($scope, $http, $interval, request, listMach) {
    $http.get('/pingbackend.json').then(function(response) {
      $scope.pingbe_fail = !response.data;
    });
    $scope.getMachines = function() {
      $http.get("/requests.json").then(function(response) {
        $scope.requests=response.data;
        $scope.download_done=false;
        $scope.download_working =false;
        for (var i = 0; i < $scope.requests.length; i++){
            if ( $scope.requests[i].command == 'download') {
                if ($scope.requests[i].status == 'done') {
                    $scope.download_done=true;
                } else {
                    $scope.download_working=true;
                }
            }
        }
      });
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
    $scope.hide_clones = true;
    $scope.hideClones = function(){
      $scope.hide_clones = !$scope.hide_clones;
    }
    $scope.action = function(target,action,machineId){
      $http.get('/'+target+'/'+action+'/'+machineId+'.json')
        .then(function() {
            $scope.getMachines();
        });
    };
    $scope.set_autostart= function(machineId, value) {
      $http.get("/machine/autostart/"+machineId+"/"+value);
    };
    $scope.set_public = function(machineId, value) {
      $http.get("/machine/public/"+machineId+"/"+value);
    };

    $scope.can_remove_base = function(machine) {
        return machine.is_base > 0 && machine.has_clones == 0 && machine.is_locked ==0;
    };
    $scope.can_prepare_base = function(machine) {
        return machine.is_base == 0 && machine.is_locked ==0;
    };

    $scope.list_images=function() {
        $http.get('/list_images.json').then(function(response) {
              $scope.images = response.data;
        });
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
    $scope.action = function(target,action,machineId){
      $http.get('/'+target+'/'+action+'/'+machineId+'.json');
    };
    //On load code
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
  
}());
