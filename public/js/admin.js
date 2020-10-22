(function() {

ravadaApp.directive("solShowMachine", swMach)
        .directive("solShowNewmachine", swNewMach)
        .controller("new_machine", newMachineCtrl)
        .controller("machinesPage", machinesPageC)
        .controller("usersPage", usersPageC)
        .controller("messagesPage", messagesPageC)
        .controller("manage_nodes",manage_nodes)
        .controller("new_node", newNodeCtrl)
        .controller("settings_global", settings_global_ctrl)
    ;

    ravadaApp.filter('orderObjectBy', function() {
        return function(items, field, reverse) {
            var filtered = [];
            angular.forEach(items, function(item) {
                filtered.push(item);
            });
            filtered.sort(function (a, b) {
                return (a[field] > b[field] ? 1 : -1);
            });
            if(reverse) filtered.reverse();
            return filtered;
        };
    });

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

      $scope.get_machine_info = function(id) {
          $http.get('/machine/info/'+id+'.json')
                .then( function(response) {
                    $scope.machine = response.data;
                    $scope.ramsize = ($scope.machine.max_mem / 1024 / 1024);
                    if ( $scope.ramsize <1 ) {
                        $scope.ramsize = 1;
                    }
                });
      };

      $http.get('/list_machines.json').then(function(response) {
              $scope.base = response.data;
      });

      $scope.swap = {
          enabled: true
          ,value: 1
      };

      $scope.data = {
          enabled: true
          ,value: 1
      };
  };

  function machinesPageC($scope, $http, $interval, $timeout, request, listMach) {
        $scope.list_machines_time = 0;
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
      $scope.subscribe_all=function(url) {
          subscribe_list_machines(url);
          subscribe_list_requests(url);
          subscribe_ping_backend(url);
      };
      subscribe_list_machines= function(url) {
          ws_connected = false;
          $timeout(function() {
              if (!ws_connected) {
                $scope.ws_fail = true;
              }
          }, 5 * 1000 );

          var ws = new WebSocket(url);
          ws.onopen    = function (event) {
              ws_connected = true ;
              $scope.ws_fail = false;
              ws.send('list_machines');
          };
          ws.onclose = function() {
              ws = new WebSocket(url);
          };
          ws.onmessage = function (event) {
              $scope.list_machines_time++;
              var data = JSON.parse(event.data);

              $scope.$apply(function () {
                  var mach;
                  if (Object.keys($scope.list_machines).length != data.length) {
                      $scope.list_machines = {};
                  }
                  for (var i=0, iLength = data.length; i<iLength; i++){
                      mach = data[i];
                      if (mach.is_base || (!mach.id_base && !mach.has_clones)
                          && (typeof $scope.list_machines[mach.id] == 'undefined'
                             || $scope.list_machines[mach.id].date_changed != mach.date_changed)
                      ){
                          $scope.list_machines[mach.id] = mach;
                          $scope.list_machines[mach.id].childs = {};
                          if ($scope.list_machines_time < 3) {
                              $scope.list_machines[mach.id].childs_loading = true;
                          } else {
                              $scope.list_machines[mach.id].childs_loading = false;
                          }
                      }
                  }
                  $scope.n_clones = 0;
                  for (var i=0, iLength = data.length; i<iLength; i++){
                      mach = data[i];
                      var childs = {};
                      if (mach.id_base) {
                          childs = $scope.list_machines[mach.id_base].childs;
                          $scope.list_machines[mach.id_base].childs_loading = false;
                      }
                      if (mach.id_base
                          && ( typeof childs[mach.id] == 'undefined'
                              || childs[mach.id].date_changed != mach.date_changed
                          )
                      ){
                          childs[mach.id] = mach;
                          $scope.n_clones++;
                          $scope.list_machines[mach.id_base].childs_loading = false;
                      }
                  }
                  if ($scope.auto_hide_clones) {
                      $scope.hide_clones = false;
                      if ($scope.n_clones > $scope.n_clones_hide ) {
                          $scope.hide_clones = true;
                      }
                  }
                  for (var i in $scope.list_machines){
                      mach = $scope.list_machines[i];
                      if (!mach.id_base && typeof $scope.show_clones[mach.id] == 'undefined'
                        && typeof mach.childs != 'undefined'
                        && mach.childs.length > 0
                        ) {
                          $scope.show_clones[mach.id] = !$scope.hide_clones;
                      }
                  }
              });
          }
      }
      subscribe_list_requests = function(url) {
          $scope.show_requests = false;
          var ws = new WebSocket(url);
          ws.onopen    = function (event) { ws.send('list_requests') };
          ws.onclose = function() {
              ws = new WebSocket(url);
          };

          ws.onmessage = function (event) {
              var data = JSON.parse(event.data);
              $scope.$apply(function () {
                  $scope.requests= data;
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
          }
      }

      subscribe_ping_backend= function(url) {
          var ws = new WebSocket(url);
          ws.onopen = function(event) { ws.send('ping_backend') };
          ws.onmessage = function(event) {
            var data = JSON.parse(event.data);
            $scope.$apply(function () {
                        $scope.pingbe_fail = !data;
            });
          }
      };

    $scope.list_machines = {};
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
    $scope.showClones = function(value){
        $scope.auto_hide_clones = false;
        $scope.hide_clones = !value;
        for (var i in $scope.list_machines){
            mach = $scope.list_machines[i];
            if (!mach.id_base) {
                $scope.show_clones[mach.id] = value;
            }
        }
     }

      $scope.request = function(request, args) {
          $http.post('/request/'+request+'/'
              ,JSON.stringify(args)
          ).then(function(response) {
              console.log(response);
          });
      };

    $scope.action = function(target,action,machineId){
      $http.get('/'+target+'/'+action+'/'+machineId+'.json')
        .success(function() {
        }).error(function(data,status) {
              console.error('Repos error', status, data);
              window.location.reload();
        });
    };
    $scope.set_autostart= function(machineId, value) {
      $http.get("/machine/autostart/"+machineId+"/"+value);
    };
    $scope.set_public = function(machineId, value) {
      if (value) value=1;
      else value = 0;
      $http.get("/machine/public/"+machineId+"/"+value)
        .error(function(data,status) {
              console.error('Repos error', status, data);
              window.location.reload();
        });

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
      $scope.with_cd = false;
      $http.get("/machine/info/"+machine.id+".json").then(function(response) {
          machine.info=response.data;
      }
      );
    }
    $scope.cancel_modal=function(){
      $scope.modalOpened=false;
    }
    $scope.toggle_show_clones =function(id) {
        $scope.show_clones[id] = !$scope.show_clones[id];
    }
    //On load code
    $scope.modalOpened=false;
    $scope.rename= {new_name: 'new_name'};
    $scope.show_rename = false;
    $scope.new_name_duplicated=false;
    $scope.show_clones = { '0': false };
  };

  function usersPageC($scope, $http, $interval, request) {
    $scope.action = function(target,action,machineId){
      $http.get('/'+target+'/'+action+'/'+machineId+'.json');
    };
    //On load code
  };

  function messagesPageC($scope, $http, $interval, request) {
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

    function settings_global_ctrl($scope, $http) {
        $scope.timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
        $scope.init = function() {
            $http.get('/settings_global.json').then(function(response) {
                $scope.settings = response.data;
                var now = new Date();
                if ($scope.settings.frontend.maintenance.value == 0 ) {
                    $scope.settings.frontend.maintenance_start.value
                        = new Date(now.getFullYear(), now.getMonth(), now.getDate()
                            , now.getHours(), now.getMinutes());

                    $scope.settings.frontend.maintenance_end.value
                        = new Date(now.getFullYear(), now.getMonth(), now.getDate()
                            , now.getHours(), now.getMinutes() + 15);
                } else {
                    $scope.settings.frontend.maintenance_start.value
                    =new Date($scope.settings.frontend.maintenance_start.value);

                    $scope.settings.frontend.maintenance_end.value
                    =new Date($scope.settings.frontend.maintenance_end.value);
                }
            });
        };
        $scope.load_settings = function() {
            $scope.init();
            $scope.formSettings.$setPristine();
        };
        $scope.update_settings = function() {
            $scope.formSettings.$setPristine();
            console.log($scope.settings);
            $http.post('/settings_global'
                ,JSON.stringify($scope.settings)
            ).then(function(response) {
            });
        };
    };
}());
