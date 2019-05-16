(function() {

ravadaApp.directive("solShowMachine", swMach)
        .directive("solShowNewmachine", swNewMach)
        .controller("new_machine", newMachineCtrl)
        .controller("machinesPage", machinesPageC)
        .controller("usersPage", usersPageC)
        .controller("messagesPage", messagesPageC)
        .controller("manage_nodes",manage_nodes)
        .controller("new_node", newNodeCtrl)
    ;

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
        if( $scope.check_netdata && $scope.check_netdata != "0" ) {
            var url = $scope.check_netdata;
            $scope.check_netdata = 0;
            $http.get(url+"?"+Date()).then(function(response) {
                if (response.status == 200 || response.status == 400 ) {
                    $scope.monitoring=1;
                    $http.get("/session/monitoring/1").then(function(response) {
                        window.location.reload();
                    });
                } else {
                    $scope.monitoring=0;
                    $http.get("/session/monitoring/0");
                }
            }, function(response) {
                $scope.monitoring=0;
                $http.get("/session/monitoring/0");
            });
      }
      if(!$scope.modalOpened){
        if ($scope.list_machines_busy) {
            return ;
        }
        $scope.list_machines_busy = true;
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
          $scope.list_machines_busy = false;
          $scope.list_machines = [];
          var mach;
          for (var i=0, iLength = response.data.length; i<iLength; i++){
            mach = response.data[i];
            if (!mach.id_base){
              $scope.list_machines[mach.id] = mach;
              $scope.list_machines[mach.id].childs = [];
            }
          }
          $scope.n_clones = 0;
          for (var i=0, iLength = response.data.length; i<iLength; i++){
            mach = response.data[i];
            if (mach.id_base){
              $scope.list_machines[mach.id_base].childs.push(mach);
              $scope.n_clones++;
            }
          }
          for (var i = $scope.list_machines.length-1; i >= 0; i--){
            if (!$scope.list_machines[i]){
              $scope.list_machines.splice(i,1);
            }
          }
          if ($scope.auto_hide_clones) {
            $scope.hide_clones = 0;
            if ($scope.n_clones > $scope.n_clones_hide ) {
                $scope.hide_clones = 1;
            }
          }
        }
          ,function (error){;
              $scope.list_machines_busy = false;
          }
        );
      }
    };
    $scope.orderParam = ['name'];
    $scope.auto_hide_clones = true;
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
      $scope.auto_hide_clones = false;
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
      if (value) value=1;
      else value = 0;
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
    $scope.open_modal=function(prefix,machine){
      $scope.modalOpened=true;
      $('#'+prefix+machine.id).modal({show:true})
    }
    $scope.cancel_modal=function(){
      $scope.modalOpened=false;
    }
    $scope.refresh_machines=function() {
      $scope.getMachines();
    }

    //On load code
    $scope.modalOpened=false;
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

    function manage_nodes($scope, $http, $interval, $timeout) {
        $scope.list_nodes = function() {
            if (!$scope.modal_open) {
                $http.get('/list_nodes.json').then(function(response) {
                    $scope.nodes = response.data;
                });
            }
        };
        $scope.node_enable=function(id) {
            $scope.modal_open = false;
            $http.get('/node/enable/'+id+'.json').then(function() {
                $scope.list_nodes();
            });

        };
        $scope.node_disable=function(id) {
            $scope.modal_open = false;
            $http.get('/node/disable/'+id+'.json').then(function() {
                $scope.list_nodes();
            });
        };
        $scope.node_remove=function(id) {
            $http.get('/node/remove/'+id+'.json');
            $scope.list_nodes();
        };
        $scope.confirm_disable_node = function(id , n_machines) {
            if (n_machines > 0 ) {
                $scope.modal_open = true;
                $('#confirm_disable_'+id).modal({show:true})
            } else {
                $scope.node_disable(id);
            }
        };
        $scope.node_start=function(id) {
            $scope.modal_open = false;
            $http.get('/node/start/'+id+'.json').then(function() {
                $scope.list_nodes();
            });

        };
        $scope.node_shutdown=function(id) {
            $scope.modal_open = false;
            $http.get('/node/shutdown/'+id+'.json').then(function() {
                $scope.list_nodes();
            });
        };
        $scope.node_connect = function(id) {
            $scope.id_req = undefined;
            $scope.request = undefined;
            $http.get('/node/connect/'+id).then(function(response) {
                $scope.id_req= response.data.id_req;
                $timeout(function() {
                    $scope.fetch_request($scope.id_req);
                }, 2 * 1000 );
            });
        };
        $scope.fetch_request = function(id_req) {
            $http.get('/request/'+id_req+'.json').then(function(response) {
                $scope.request = response.data;
                if ($scope.request.status != "done") {
                    $timeout(function() {
                        $scope.fetch_request(id_req);
                    }, 3 * 1000 );
                } else {
                    $scope.list_nodes()
                }
            });
        };

        $scope.modal_open = false;
        $scope.list_nodes();
        $interval($scope.list_nodes,30 * 1000);
    };

    function newNodeCtrl($scope, $http, $timeout) {
        $http.get('/list_vm_types.json').then(function(response) {
            $scope.backends = response.data;
            $scope.backend = response.data[0];
        });
        $scope.validate_node_name = function() {
            console.log($scope.name);

            $http.get('/node/exists/'+$scope.name)
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
        $scope.connect_node = function(backend, address) {
            $scope.id_req = undefined;
            $scope.request = undefined;
            $http.get('/node/connect/'+backend+'/'+address).then(function(response) {
                $scope.id_req= response.data.id_req;
                $timeout(function() {
                    $scope.fetch_request($scope.id_req);
                }, 2 * 1000 );
            });
        };
        $scope.fetch_request = function(id_req) {
            $http.get('/request/'+id_req+'.json').then(function(response) {
                $scope.request = response.data;
                if ($scope.request.status != "done") {
                    $timeout(function() {
                        $scope.fetch_request(id_req);
                    }, 3 * 1000 );
                }
            });
        };
    };
}());
