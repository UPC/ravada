(function() {

ravadaApp.directive("solShowMachine", swMach)
        .directive("solShowNewmachine", swNewMach)
        .controller("new_machine", newMachineCtrl)
        .controller("machinesPage", machinesPageC)
        .controller("usersPage", usersPageC)
        .controller("messagesPage", messagesPageC)
        .controller("manage_nodes",manage_nodes)
        .controller("manage_routes",manage_routes)
        .controller("manage_networks",manage_networks)
        .controller("manage_host_devices",manage_host_devices)
        .controller("settings_network",settings_network)
        .controller("settings_node",settings_node)
        .controller("settings_storage",settings_storage)
        .controller("settings_route",settings_route)
        .controller("new_node", newNodeCtrl)
        .controller("new_storage", new_storage)
        .controller("settings_global", settings_global_ctrl)
        .controller("admin_groups", admin_groups_ctrl)
        .controller('admin_charts', admin_charts_ctrl)
        .controller('upload_users', upload_users)
    ;

    ravadaApp.directive('ipaddress', function() {
        return {
            require: 'ngModel',
            link: function(scope, elm, attrs, ctrl) {
                ctrl.$parsers.unshift(function(inputText) {
                    var ipformat = /^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\/([0-9]|[0-1][0-9]|2[0-4])$/;
                    if(ipformat.test(inputText))
                    {
                        ctrl.$setValidity('ipformat', true);
                        return inputText;
                    }
                    else
                    {
                        //alert("You have entered an invalid IP address!");
                        //document.form1.text1.focus();
                        ctrl.$setValidity('ipformat', false);
                        return undefined;
                    }
                });

            }
        };
    });

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

      var ws_list_isos;
      var isos_cache = {};

      $scope.init = function(url) {
          $scope.disconnected = false;
          $scope.url = url;
          $scope.images = [];
          subscribe_list_machines(url);
          $http.get('/list_nodes.json').then(function(response) {
              $scope.nodes = {};
              for (var i=0; i<response.data.length; i++) {
                  var node = response.data[i];
                  if (typeof($scope.nodes[node.type]) == 'undefined') {
                      $scope.nodes[node.type] = [];
                  }
                  $scope.nodes[node.type].push(node);
                  if(typeof($scope.backend) == 'undefined') {
                      $scope.backend = node.type;
                  }
              }
              $scope.backends=Object.keys($scope.nodes);
              $scope.change_backend();
              $scope.subscribe_list_isos($scope.node.id);
          });
      }

      $scope.connect = function() {
          $scope.disconnected=false;
          subscribe_list_machines($scope.url);
          $scope.subscribe_list_isos($scope.node.id);
      };

      $scope.list_machine_types = function(backend) {
          $http.get('/list_machine_types.json?vm_type='+backend).then(function(response) {
              $scope.machine_types[backend] = response.data;
          });

      };
      $scope.list_storage_pools = function(backend) {
          $scope.storage_pools_loaded=false;
          $http.get('/list_storage_pools/'+backend+"?active=1").then(function(response) {
            $scope.storage_pools_loaded=true;
              $scope.storage_pools[backend] = response.data;

              $scope.storage_pool=response.data[0];
              for(var i=0; i<response.data.length;i++) {
                  if (response.data[i].is_active) {
                      $scope.storage_pool=response.data[i];
                  }
              }
              for(var i=0; i<response.data.length;i++) {
                  if (response.data[i].is_active && response.data[i].name == 'default') {
                      $scope.storage_pool=response.data[i];
                  }
              }

          });

      };

      $scope.loadTemplates = function() {
          $scope.iso_file = '';
          $http.get('/list_images.json').then(function(response) {
              $scope.images = response.data;
          });
          $scope.list_machine_types($scope.backend);
          $scope.list_storage_pools($scope.backend);
      }

      default_node = function() {
          $scope.node = undefined;
          var node;
          for (var i=0; i<$scope.nodes[$scope.backend].length; i++) {
              var current_node = $scope.nodes[$scope.backend][i];
              if (typeof(node) == 'undefined') {
                  node = current_node;
              }
              if (typeof($scope.node) == 'undefined' && current_node.is_local ) {
                  $scope.node = current_node;
              }
          }
          if (typeof($scope.node) == 'undefined') {
              $scope.node=node;
          }
      }

      var refresh_list_isos = function(id_node) {
          $scope.subscribe_list_isos(id_node);
      };

      $scope.change_backend = function() {
            $scope.loadTemplates();
            default_node();
            refresh_list_isos($scope.node.id);
      }

      /*
      $http.get('/iso_file.json').then(function(response) {
              $scope.isos = response.data;
      });
      */

      $scope.change_list_isos = function() {
        var id_vm = $scope.node.id;
        $scope.iso_file = '';
        if (typeof(isos_cache[id_vm]) != 'undefined') {
            $scope.isos = isos_cache[id_vm];
            $scope.iso_file = $scope.change_iso($scope.id_iso);
        } else {
            $scope.isos = undefined;
        }
        refresh_list_isos(id_vm);
      };

      $scope.subscribe_list_isos = function(id_vm) {
          $scope.iso_file = '';
          $scope.isos=[];
          if (typeof(ws_list_isos) != 'undefined') {
              ws_list_isos.close();
          }
          ws_list_isos = new WebSocket($scope.url);
          ws_list_isos.onopen = function(event) { ws_list_isos.send('list_isos/'+id_vm) };
          ws_list_isos.onclose = function(event) {
              $scope.disconnected=true;
          };
          ws_list_isos.onmessage = function(event) {
              var data = JSON.parse(event.data);
              $scope.$apply(function () {
                  $scope.isos = data;
                  isos_cache[$scope.node.id] = data;
                  if (!$scope.iso_file && $scope.id_iso) {
                      $scope.iso_file = $scope.change_iso($scope.id_iso);
                  }
              });
          }
      };

      subscribe_list_machines = function() {
          var ws = new WebSocket($scope.url);
          ws.onopen = function(event) { ws.send('list_machines') };
          ws.onmessage = function(event) {
              var data = JSON.parse(event.data);
              $scope.$apply(function () {
                  $scope.base = data;
              });
          }
      };
      /*
      $http.get('/list_lxc_templates.json').then(function(response) {
              $scope.templates_lxc = response.data;
      });
      */
      $scope.iso_download=function(iso) {
            iso.downloading=1;
            $http.get('/iso/download/'+$scope.node.id+"/"+iso.id+'.json').then(function() {
            });
      };
      $scope.name_duplicated = false;

      $scope.ddsize=20;
      $scope.swapsize={value:1};
      $scope.ramSize=1;
      $scope.seeswap=0;

      $scope.showMinSize = false;
      $scope.min_size = 15;

      $scope.iso = { arch: 'unknown' };
      $scope.machine_types = { };
      $scope.storage_pools = { };

      $scope.change_iso = function(iso) {
          $scope.id_iso_id = iso.id;
          if (iso.min_disk_size != null) {
            $scope.min_size = iso.min_disk_size;
            $scope.showMinSize = true;
          }
          else {
            $scope.showMinSize = false;
            $scope.min_size = 1;
          }
          if ( $scope.swap.value < iso.min_swap_size ) {
              $scope.swap.value = iso.min_swap_size + 0.1;
          }
          if (iso.file_re ) {
              file_re = new RegExp(iso.file_re);
          } else {
              return '';
          }
          if (typeof($scope.isos) != 'undefined' ) {
              var name_re = /.*\/(.+\.iso$)/;
              for (var i=0 ; i<$scope.isos.length ; i++) {
                  var found = name_re.exec($scope.isos[i]);
                  if (found.length && file_re.test(found[1])) {
                      if ($scope.isos[i].downloading) {
                          $scope.isos[i].downloading=false;
                      }
                      return $scope.isos[i];
                  }
              }
          }
          return "";
      };

      $scope.onIdIsoSelected = function() {
        $scope.iso_file = $scope.change_iso(this.id_iso)
        $scope.id_file = ($scope.iso_file === "<NONE>") ? "" : $scope.iso_file;
        if ($scope.backend && $scope.machine_types[$scope.backend] 
            && $scope.id_iso && $scope.id_iso.options
            && $scope.id_iso.options['machine']) {
            var types = $scope.machine_types[$scope.backend][$scope.id_iso.arch];
            var option = $scope.id_iso.options['machine'];
            if (types && typeof(types) != undefined ) {
                for (var i=0; i<types.length
                    ;i++) {
                    var current = types[i];
                    if (current.substring(0,option.length) == option) {
                        $scope.machine=current;
                    }
                }
            }
        }
        if ($scope.id_iso && $scope.id_iso.options) {
            if( $scope.id_iso.options['bios']) {
                $scope.bios = $scope.id_iso.options['bios'];
            }
            if( $scope.id_iso.options['hardware']) {
                $scope.hardware = $scope.id_iso.options['hardware'];
            }

        }

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

      $scope.getVisualizableObjects = function(value, objects, name) {
          var visualizable_objects = [];
          if (objects) {
              var lowercased_value = value ? value.toLowerCase() : '';
              for (var i = 0, j = objects.length; i < j; i ++) {
                  var search_value = name ? objects[i][name] : objects[i];
                  if ((! lowercased_value) || (search_value.toLowerCase().indexOf(lowercased_value) >= 0)) {
                      visualizable_objects.push(objects[i]);  
                  }
              }
          }
          return visualizable_objects;
      };

      $scope.type = function(v) {
        return typeof(v);
      };

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

      $scope.refresh_storage = function() {
          $scope.refresh_working = true;
          $scope.iso_file = undefined;
          $scope.isos = undefined;
          isos_cache[$scope.node.id] = undefined;
          $http.post('/request/refresh_storage/',
              JSON.stringify({})
          ).then(function(response) {
              $scope.refresh_working = false;
              $scope.change_list_isos($scope.node.id);
              if(response.status == 300 ) {
                  console.error('Response error', response.status);
              }
          }
        );
      };

      $scope.swap = {
          enabled: true
          ,value: 1
      };

      $scope.data = {
          enabled: true
          ,value: 1
      };
  };

  function machinesPageC($scope, $http, $timeout) {
        $scope.list_machines_time = 0;
        $scope.n_active=0;
        $scope.show_active=false;
        var ws_list_machines;
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

      var refresh_show_clones = function() {
          $scope.n_clones=0;
          var show=Object.keys($scope.show_clones);
          for (var i=0; i<show.length; i++) {
                  ws_list_machines.send("list_machines_tree/show_clones/"+show[i]+"=false");
                  ws_list_machines.send("list_machines_tree/show_clones/"+show[i]+"="
                      +$scope.show_clones[show[i]]);
          }
          return show.length;
      };

      subscribe_list_machines= function(url) {
          ws_connected = false;
          $scope.list_machines = {};
          $scope.n_clones = 0;
          $timeout(function() {
              if (!ws_connected) {
                $scope.ws_fail = true;
              }
          }, 5 * 1000 );

          var ws = new WebSocket(url);
          ws_list_machines=ws;

          ws.onerror = function(event) {
              console.log("error ",event);
              console.log(event);
              if ($scope.ws_connection_lost) {
                window.location.reload();
              }
          };
          ws.onopen    = function (event) {
              $scope.ws_connection_lost = false;
              ws_connected = true ;
              $scope.ws_fail = false;
              if ($scope.show_active) {
                  ws.send("list_machines_tree/show_active/true");
              }
              if ($scope.filter) {
                  ws_list_machines.send("list_machines_tree/show_name/"+$scope.filter);
              }
              if (! refresh_show_clones() || !$scope.show_active || !$scope.filter ) {
                  ws.send('list_machines_tree');
              }
          };
          ws.onclose = function() {
              $scope.$apply(function() {
                  $timeout(function() {
                    $scope.ws_connection_lost = true;
                  }, 5*1000);
              });
          };
          ws.onmessage = function (event) {

              if ( $scope.modalOpened == true ) {
                  return;
              }
              $scope.list_machines_time++;
              var data0 = JSON.parse(event.data);

              $scope.$apply(function () {
                  var mach;
                  var n_active_current = 0;
                  var action = data0.action;
                  var data = data0.data;
                  if (typeof(data) == 'undefined') {
                      return;
                  }
                  $scope.n_active=data0.n_active;
                  if(action == 'new' || Object.keys($scope.list_machines).length==0) {
                      $scope.list_machines.length = data.length;
                      for (var i=0, iLength = data.length; i<iLength; i++){
                          mach = data[i];
                          if (mach.id_base>0) { $scope.n_clones++ }
                          if (typeof $scope.list_machines[i] == 'undefined'
                              || $scope.list_machines[i].id != mach.id
                              || $scope.list_machines[i].date_changed != mach.date_changed
                              || ($scope.show_active && mach.is_active )
                          ){
                              var show=false;
                              if (mach._level == 0 && !$scope.filter && !$scope.show_active) {
                                  mach.show=true;
                              }
                              if ($scope.show_machine[mach.id]) {
                                  mach.show = $scope.show_machine[mach.id];
                              } else if(mach.id_base && $scope.show_clones[mach.id_base]) {
                                  mach.show = true;
                              }
                              if ($scope.show_active && mach.status=='active') {
                                  mach.show=true;
                              }
                              $scope.list_machines[i] = mach;
                          }
                      }
                  } else {
                    var change = {};
                    for (var i=0, iLength = data.length; i<iLength; i++){
                        mach = data[i];
                        change[mach.id] = mach;
                    }
                    var keys = Object.keys($scope.list_machines);
                    for ( var n_key=0 ; n_key<keys.length ; n_key++) {
                        mach = $scope.list_machines[n_key];
                        var mach2;
                        if ( typeof(mach) != 'undefined' ) {
                            mach2 = change[mach.id];
                        }
                        if (typeof(mach2) != 'undefined' && typeof(mach) != 'undefined') {
                            mach2._level = mach._level;
                              var show=false;
                              if (mach2.name != mach.name || mach2.id_base != mach.id_base) {
                                  ws.send("list_machines_tree");
                              }
                              if (mach2._level == 0 && !$scope.filter && !$scope.show_active) {
                                  mach2.show=true;
                              }
                              if ($scope.show_machine[mach.id]) {
                                  mach2.show = $scope.show_machine[mach.id];
                              } else if(mach.id_base && $scope.show_clones[mach.id_base]) {
                                  mach2.show = true;
                              }
                              if ($scope.show_active && mach2.is_active) {
                                  mach2.show=true;
                              }

                              $scope.list_machines[n_key] = mach2;
                                if (mach2.id_base>0) { $scope.n_clones++ }
                        }
                    }

                  }
                  if ( $scope.show_active ) { $scope.do_show_active() };
                  if ( $scope.filter) { $scope.show_filter() };
              });
          }
          if (typeof(ws_list_isos) != 'undefined') {
              $scope.change_list_isos($scope.node.id);
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
                        var time1 = new Date() / 1000;
                        if(time1 - time0 > 120 ) {
                            $scope.pingbe_fail = !data;
                        } else {
                            $scope.pingbe_fail = false;
                        }
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
    $scope.toggle_show_all_clones = function() {
        $scope.showClones($scope.hide_clones);
    };
    $scope.showClones = function(value){
        $scope.auto_hide_clones = false;
        $scope.show_active = false;
        $scope.hide_clones = !value;
        $scope.filter = '';
        for (var i in $scope.list_machines){
            mach = $scope.list_machines[i];
            if (mach._level == 0 ) {
                mach.show = true;
            }
            if (mach.is_base) {
                $scope.toggle_show_clones(mach.id,value);
            }
        }
     }

     $scope.request = function(request, args) {
        $http.post('/request/'+request+'/'
            ,JSON.stringify(args)
        ).then(function(response) {
            if(response.status == 300 ) {
                console.error('Response error', response.status);
                window.location.reload();
            }
        });
    };

    $scope.action = function(target,action,machineId){
        if (action === 'view-new-tab') {
            window.open('/machine/view/' + machineId + '.html');
        }
        else if (action === 'view') {
            window.location.assign('/machine/view/' + machineId + '.html');
        }
        else {
            $http.get('/'+target+'/'+action+'/'+machineId+'.json')
               .then(function(response) {
                   if(response.status == 300 || response.status == 403) {
                   console.error('Reponse error', response.status);
                   window.location.reload();
                    }
                }).catch(function(data) {
                    if (data.status == 403) {
                        window.location.reload();
                    }
                })
            ;
        }
    };
    $scope.set_autostart= function(machineId, value) {
      $http.get("/machine/autostart/"+machineId+"/"+value);
    };
    $scope.set_public = function(machineId, value, show_clones) {
      if (value) value=1;
      else value = 0;
      $http.get("/machine/public/"+machineId+"/"+value)
        .then(function(response) {
            if(response.status == 300 ) {
              console.error('Reponse error', response.status);
            }
        });

       if ( value == 0 ) {
        $http.get("/machine/set/"+machineId+"/show_clones/"+show_clones);
       }
    };

    $scope.can_remove_base = function(machine) {
        return machine.is_base > 0 && machine.has_clones == 0 && machine.is_locked ==0;
    };
    $scope.can_prepare_base = function(machine) {
        return machine.is_base == 0 && machine.is_locked ==0;
    };

    $scope.can_manage_base = function(machine) {
        if (typeof(machine) == 'undefined') {
            return;
        }
        if (machine.is_base) {
            return $scope.can_remove_base(machine);
        } else {
            return $scope.can_prepare_base(machine);
        }
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
          if(response.status != 200 ) {
               window.location.reload();
          }
          machine.info=response.data;
      }
      ,function errorCallback(response) {
          window.location.reload();
      });
    }
    $scope.cancel_modal=function(machine,field){
        $scope.modalOpened=false;
        if (typeof(machine)!='undefined' && typeof(field)!='undefined') {
            if (machine[field]) {
                machine[field]=0;
            } else {
                machine[field]=1;
            }
        }
    }
    $scope.toggle_show_clones =function(id, value) {
        if (typeof(value) == 'undefined') {
            $scope.show_clones[id] = !$scope.show_clones[id];
        } else {
            $scope.show_clones[id] = value;
        }
        if (!$scope.show_clones[id]) {
            $scope.show_active = false;
            $scope.hide_clones = true;
        }
        ws_list_machines.send("list_machines_tree/show_clones/"+id+"="+$scope.show_clones[id]);
       for (var [key, mach ] of Object.entries($scope.list_machines)) {
            if (mach.id_base == id) {
                mach.show = $scope.show_clones[id];
                $scope.show_machine[mach.id] = mach.show;
                if ( !mach.show) {
                    $scope.set_show_clones(mach.id, false);
                }
            }
        }
        $scope.lock_show_active=false;
    }
    $scope.set_show_clones = function(id, show) {
       $scope.show_clones[id] = show;
       for (var [key, mach ] of Object.entries($scope.list_machines)) {
            if (mach.id_base == id) {
                mach.show = show;
                $scope.show_machine[mach.id] = mach.show;
                if ( !mach.show) {
                    $scope.set_show_clones(mach.id, false);
                }
            }
       }
    }

    machine_base = function(id) {
       for (var [key, mach ] of Object.entries($scope.list_machines)) {
            if (mach.id == id ) {
                return mach;
            }
       }
    };
    show_parents = function(mach) {
        var id_base = mach.id_base;
        if (id_base) {
            $scope.set_show_clones(mach.id_base, true);
            show_parents(machine_base(id_base));
        }
    };
    $scope.toggle_show_active = function() {
        var show = !$scope.show_active;
        ws_list_machines.send("list_machines_tree/show_active/"+show);
        if (!$scope.show_active) {
            $scope.do_show_active();
        } else {
            $scope.reload_list();
            $scope.showClones(false);
        }
    };
    $scope.do_show_active = function() {
        $scope.filter = '';
        $scope.show_active=true;
        $scope.hide_clones = true;
        var n_show = 0;
        for (var [key, mach ] of Object.entries($scope.list_machines)) {
            if (mach.status =='active') {
                $scope.show_machine[mach.id_base] = true;
                mach.show = true;
                n_show++;
            } else {
                mach.show = false;
            }
        }
        $scope.show_active=true;
        $scope.n_show = n_show;
    };
    $scope.reload_list = function() {
        if ($scope.filter) {
            $scope.filter = '';
        } else {
            $scope.show_active=false;
            $scope.hide_clones = true;
        }
        for (var [key, mach ] of Object.entries($scope.list_machines)) {
            if (mach._level == 0 ) {
                mach.show = true;
            } else {
                mach.show = false;
            }
        }
    };

    $scope.list_machines_name = function() {
        ws_list_machines.send("list_machines_tree/show_name/"+$scope.filter);
        $scope.show_filter();
        if (!$scope.filter) {
            refresh_show_clones();
        }
    };

    $scope.show_filter = function() {
        $scope.hide_clones = true;
        $scope.show_active = false;
        var n_show=0;
        var filter = $scope.filter.toLowerCase();
        for (var [key, mach ] of Object.entries($scope.list_machines)) {
            if (mach.name && $scope.filter.length > 0) {
                var name = mach.name.toLowerCase();
                if ( name.indexOf(filter)>= 0) {
                    mach.show = true;
                    n_show++;
                } else {
                    mach.show = false;
                }
            } else if (mach.name) {
                if (mach._level > 0 ) {
                    mach.show = false;
                } else {
                    mach.show = true;
                    n_show++;
                }
            }
        }
        $scope.n_show = n_show;
    };

    //On load code
    $scope.modalOpened=false;
    $scope.rename= {new_name: 'new_name'};
    $scope.show_rename = false;
    $scope.new_name_duplicated=false;
    $scope.show_clones = { '0': false };
    $scope.show_machine = { '0': false };
    $scope.pingbe_fail = false;
    $scope.show_active=false;
    var time0 = new Date() / 1000;
  };

    function usersPageC($scope, $http, $interval, request) {
        $scope.list_groups= function() {
            $scope.loading_groups = true;
            $scope.error = '';
            $http.get('/group/ldap/list')
                .then(function(response) {
                    $scope.loading_groups = false;
                    $scope.groups = response.data;
                });
        };
        $scope.list_user_groups = function(id_user) {
            $http.get('/user/list_groups/'+id_user)
                .then(function(response) {
                    $scope.user_groups = response.data;
                });
        };
        $scope.add_group_member = function(id_user, cn, group) {
            $http.post("/ldap/group/add_member/"
              ,JSON.stringify(
                  { 'group': group
                    ,'cn': cn
                  })
              ).then(function(response) {
                  $scope.error = response.data.error;
                  $scope.list_user_groups(id_user);
                });
        };
        $scope.remove_group_member = function(id_user, dn, group) {
            $http.post("/ldap/group/remove_member/"
              ,JSON.stringify(
                  { 'group': group
                    ,'dn': dn
                  })
              ).then(function(response) {
                  $scope.error = response.data.error;
                  $scope.list_user_groups(id_user);
            });
        };

        $scope.load_grants = function(id) {
            id_user=id;
            $http.get("/user/grants/"+id_user).then(function(response) {
                $scope.perm = response.data;
            });
            $http.get("/user/info/"+id_user).then(function(response) {
                $scope.user= response.data;
            });
        };
        $scope.toggle_grant = function(grant) {
            $scope.perm[grant] = !$scope.perm[grant];
            $http.get("/user/grant/"+id_user+"/"+grant+"/"+$scope.perm[grant]).then(function(response) {
                $scope.error = response.data.error;
                $scope.info = response.data.info;
            });
        };
        $scope.update_grant = function(grant) {
            $http.get("/user/grant/"+id_user+"/"+grant+"/"+$scope.perm[grant]).then(function(response) {
                $scope.error = response.data.error;
                $scope.info = response.data.info;
            });
        };
        $scope.change_user = function(data) {
            $http.post('/user/set/'+id_user
                ,JSON.stringify(data)
            ).then(function(response) {
                $scope.load_grants(id_user);
            });
        };
        $scope.init = function(id) {
            $scope.load_grants(id);
            $scope.list_user_groups(id);
        };

        $scope.list_groups();
        var id_user;

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
            $http.get('/v1/node/remove/'+id);
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
    function manage_networks($scope, $http, $interval, $timeout) {
        $scope.init = function(id_vm) {
            $scope.list_networks(id_vm);
            $scope.loaded_networks=false;
        }
        $scope.list_networks = function(id_vm) {
            $http.get('/v2/vm/list_networks/'+id_vm).then(function(response) {
                $scope.networks=response.data;
                $scope.loaded_networks=true;
                });
        }
    }

    function manage_routes($scope, $http, $interval, $timeout) {
        list_routes = function() {
            $http.get('/list_routes.json').then(function(response) {
                    for (var i=0; i<response.data.length; i++) {
                        var item = response.data[i];
                        $scope.routes[item.id] = item;
                    }
                });
        }
        $scope.update_network= function(id, field) {
            var value = $scope.routes[id][field];
            var args = { 'id': id };
            args[field] = value;
            $http.post('/v2/route/set'
                , JSON.stringify( args ))
            .then(function(response) {
            });
        };


        $scope.routes={};
        list_routes();
    }

    function settings_network($scope, $http, $interval, $timeout) {
        $scope.init = function(id,url, id_vm) {
            if ( id ) {
                $scope.load_network(id);
            } else {
                $scope.new_network(id_vm);
            }
        };
        $scope.new_network = function(id_vm) {
            $scope.network = { };
            $http.get('/v2/network/new/'+id_vm)
                .then(function(response) {
                    $scope.network=response.data;
                    $scope.form_network.$setDirty();
                    $scope.search_users();
            });
        };

        $scope.load_network = function(id) {
            $http.get('/v2/network/info/'+id)
                .then(function(response) {
                $scope.network = response.data;
                $scope.network._old_name = $scope.network.name;
                $scope.form_network.$setPristine();
                $scope.search_users();
            });

        };
        $scope.search_users = function() {
            if ($scope.name_search == undefined) {
                $scope.name_search = $scope.network._owner.name;
            }
            $scope.searching_user = true;
            $scope.user_found = '';
            $http.get("/search_user/"+$scope.name_search)
                .then(function(response) {
                    $scope.user_found = response.data.found;
                    $scope.user_count = response.data.count;
                    $scope.list_users = response.data.list;
                    $scope.searching_user=false;
                    if ($scope.user_count == 1) {
                        $scope.name_search = response.data.found;
                    }
                    for ( var n=0 ; n<$scope.list_users.length ; n++) {
                        if ($scope.list_users[n].name == $scope.name_search) {
                            $scope.network._owner = $scope.list_users[n];
                            break;
                        }
                    }
                });

        };

        $scope.update_network = function() {
            $scope.form_network.$setPristine();
            var update = $scope.network['id'];
            $scope.network.id_owner = $scope.network._owner.id;
            $scope.name_search = $scope.network._owner.name;
            $http.post('/v2/network/set/'
                , JSON.stringify($scope.network))
                .then(function(response) {
                    $scope.error=response.data.error;
                    if (!update) {
                        if (response.data['id_network']) {
                            window.location.assign('/network/settings/'
                                +response.data['id_network']+'.html');
                        }
                    }
                });
        };
        $scope.remove_network = function() {
            $http.post('/request/remove_network'
                ,JSON.stringify({'id': $scope.network.id }))
                .then(function(response) {
                    $scope.network._removed = true;
                });
        };


    }


    function settings_storage($scope, $http, $interval, $timeout) {
        var start=0;
        var limit=10;
        $scope.n_selected = 0;
        $scope.init=function(id_vm) {
            $scope.id_vm = id_vm;
            list_storage_pools(id_vm);
            $scope.storage = {
                'id': id_vm
            };
            $scope.load_node(id_vm);
            $scope.list_unused_volumes();
        };

        $scope.load_node= function() {
            $http.get('/node/info/'+$scope.id_vm+'.json')
                .then(function(response) {
                $scope.node = response.data;
            });
        };

        $scope.update_node = function(node) {
            $scope.error = '';
            $http.post('/v1/node/set/'
                , JSON.stringify(node))
                .then(function(response) {
                    if (response.data.ok == 1){
                        $scope.saved = true;
                    }
                    $scope.error = response.data.error;
                });
        };

        $scope.toggle_active = function(pool) {
            if (pool.is_active) {
                pool.is_active=0;
            } else {
                pool.is_active=1;
            }
            $http.post('/request/active_storage_pool'
                ,JSON.stringify({'id_vm': $scope.id_vm
                    , 'value': pool.is_active
                    , 'name': pool.name})
            ).then(function(response) {
                $scope.error = response.data.error;
            });

        };

        list_storage_pools= function(id_vm) {
            $scope.pools=[];
            $http.get('/storage/list_pools/'+id_vm).then(function(response) {
                $scope.storage_pools = response.data;
                for (var i=0;i<response.data.length;i++) {
                    $scope.pools[i]=response.data[i].name;
                }
            });
        }

        $scope.list_unused_volumes=function() {
            $scope.loading_unused=true;
            $http.get('/storage/list_unused_volumes?id_vm='+$scope.id_vm
                +'&start='+start+'&limit='+limit)
                    .then(function(response) {
                $scope.loading_unused=false;
                $scope.list_more = response.data.more;
                if (!$scope.unused_volumes) {
                    $scope.unused_volumes = response.data.list;
                    return;
                }
                for (var i=0; i<response.data.list.length ; i++) {
                    $scope.unused_volumes.push(response.data.list[i]);
                }
                $scope.req_more = false;
                window.scrollTo(0, document.body.scrollHeight);
            });
        }
        $scope.remove_selected = function() {
            var remove = [];
            var files = $scope.unused_volumes;
            var keep = [];
            var count = 0;
            for (var i=0; i<files.length; i++ ) {
                if (files[i].remove) {
                    remove.push(files[i].file);
                    count++;
                } else {
                    keep.push(files[i]);
                }
            }
            if (!count) {
                return;
            };
            $scope.unused_volumes = keep;
            $http.post('/request/remove_files'
                ,JSON.stringify({'id_vm': $scope.id_vm , 'files': remove })
            ).then(function(response) {
                start=0;
                $scope.unused_volumes=undefined;
                $scope.list_unused_volumes();
            });
        }
        $scope.more = function() {
            start += limit;
            $scope.req_more = true;
            $scope.list_unused_volumes();
        };
    }

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
        $scope.check_duplicated_hostname = function() {
            if (typeof($scope.hostname) == 'undefined'
                || typeof($scope.vm_type) == 'undefined'
                || $scope.hostname.length == 0
                || $scope.vm_type.length == 0
            ) {
                $scope.hostname_duplicated = false;
                return;
            }
            $scope.hostname_duplicated = false;
            var args = { hostname: $scope.hostname , vm_type: $scope.vm_type };

            $http.post("/v1/exists/vms",JSON.stringify(args))
                .then(function(response) {
                    $scope.hostname_duplicated = response.data.id;
            });
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

    function new_storage($scope, $http, $timeout) {
        var url_ws;
        var ws;
        $scope.name_valid=true;
        $scope.directory_valid=true;

        $scope.init=function(id_vm, url) {
            $scope.id_vm = id_vm;
            url_ws = url;
        };
        $scope.check_name = function(name) {
            const re = /^[a-zA-Z]+[a-zA-Z0-9_\.\-]*$/;
            $scope.name_valid = re.test(name);
        };
        $scope.check_directory = function(name) {
            const re = /^\/[a-zA-Z]+[a-zA-Z0-9_\.\-\/]*$/;
            $scope.directory_valid = re.test(name);
        };

        $scope.name_duplicated=false;
        $scope.add_storage = function() {
            $scope.request=undefined;
            if (!$scope.name_valid || ! $scope.directory_valid) {
                return;
            }
            $http.post('/request/create_storage_pool/'
                ,JSON.stringify({
                    'id_vm': $scope.id_vm
                    ,'name': $scope.name
                    ,'directory': $scope.directory})
            ).then(function(response) {
                if (response.data.ok == 1 ) {
                    $scope.request = {
                        'id': response.data.request
                    };
                    subscribe_request(response.data.request);
                }
            });
        }
        subscribe_request = function(id_request) {
            if(typeof(ws) === 'undefined') {
                ws = new WebSocket(url_ws);
            } else {
                ws.close();
                ws = new WebSocket(url_ws);
            }
            ws.onopen = function(event) { ws.send('request/'+id_request) };
            ws.onmessage = function(event) {
                var data = JSON.parse(event.data);
                $scope.$apply(function () {
                    $scope.request = data;
                });
            }
        };

    };

   function manage_host_devices($scope, $http, $timeout) {
        $scope.init=function(id, vm_type, url) {
            $scope.id_vm= id;
            $scope.vm_type = vm_type;
            $scope.vm_type_orig = vm_type;
            subscribe_list_host_devices(id, url);
            list_templates(id);
            list_backends();
            list_nodes();
        };

       list_nodes=function() {
            $http.get('/list_nodes_by_id.json')
            .then(function(response) {
                   $scope.nodes = response.data;
               });
       };

       list_backends=function() {
            $http.get('/list_vm_types.json')
            .then(function(response) {
                   $scope.vm_types = response.data;
               });
       };

        list_templates = function(id) {
            $http.get('/host_devices/templates/list/'+ id)
            .then(function(response) {
                   $scope.templates = response.data;
               });
        };

        $scope.add_host_device = function() {
            $http.post('/node/host_device/add'
                ,JSON.stringify({ 'template': $scope.new_template.name , 'id_vm': $scope.id_vm}))
            .then(function(response) {
            });
        };

        $scope.update_host_device = function(hdev) {
            hdev._loading=true;
            hdev.devices_node=[];
            hdev._nodes = [];
            $http.post('/node/host_device/update'
                ,JSON.stringify(hdev))
            .then(function(response) {
                $scope.error = response.data.error;
            });
            hdev.devices = undefined;
        };
        $scope.remove_host_device = function(id) {
            $http.get('/node/host_device/remove/'+id).then(function(response) {
                // TODO: add some reponse
            });
        };


        subscribe_list_host_devices= function(id, url) {
            $scope.show_requests = false;
            $scope.host_devices = [];
            var ws = new WebSocket(url);
            ws.onopen    = function (event) { ws.send('list_host_devices/'+id) };
            ws.onclose = function() {
                ws = new WebSocket(url);
            };

            ws.onmessage = function (event) {
                var data = JSON.parse(event.data);
                $scope.$apply(function () {
                    if (Object.keys($scope.host_devices).length != data.length) {
                        $scope.host_devices.length = data.length;
                    }
                    for (var i=0, iLength = data.length; i<iLength; i++){
                        var hd = data[i];
                        if (typeof($scope.host_devices[i]) == 'undefined') {
                            $scope.host_devices[i] = hd;
                        } else if ( $scope.host_devices[i].id != hd.id
                            || $scope.host_devices[i].date_changed != hd.date_changed
                            || $scope.host_devices[i]['loading']
                        ) {
                            var keys = Object.keys(hd);
                            for ( var n_key=0 ; n_key<keys.length ; n_key++) {
                               var field=keys[n_key];
                                if (field != 'filter' && $scope.host_devices[i][field] != hd[field]) {
                                    $scope.host_devices[i][field] = hd[field];
                                }
                            }
                        }
                    }
                });
            }
        };
        $scope.toggle_show_hdev = function(id) {
            $scope.show_hdev[id] = ! $scope.show_hdev[id];
        };
        $scope.show_hdev = { 1: true};

    };

   function settings_route($scope, $http, $timeout) {
        var url_ws;
        $scope.init = function(id_network) {
            if (typeof id_network == 'undefined') {
                $scope.route= {
                    'name': ''
                    ,'all_domains': 1
                };
            } else {
                $scope.load_network(id_network);
                $scope.list_domains_network(id_network);
            }
        }
        $scope.check_no_domains = function() {
            if ( $scope.route.no_domains == 1 ){
                $scope.route.all_domains = 0;
            }
        };
        $scope.check_all_domains = function() {
            if ( $scope.route.all_domains == 1 ){
                $scope.route.no_domains = 0;
            }
        };
        $scope.update_network= function(field) {
            var data = $scope.route;
            if (typeof field != 'undefined') {
                var data = {};
                data[field] = $scope.route[field];
            }
            $scope.saved = false;
            $scope.error = '';
            $http.post('/v2/route/set/'
                , JSON.stringify(data))
            //                    , JSON.stringify({ value: $scope.network[field]}))
                .then(function(response) {
                    if (response.data.ok == 1){
                        $scope.saved = true;
                        if (!$scope.route.id) {
                            $scope.new_saved = true;
                        }
                    }
                    $scope.error = response.data.error;
                });
            $scope.formNetwork.$setPristine();
        };

        $scope.load_network = function(id_network) {
                $scope.error = '';
                $scope.saved = false;
                $http.get('/route/info/'+id_network).then(function(response) {
                    $scope.route = response.data;
                    $scope.formNetwork.$setPristine();
                    $scope.route._old_name = $scope.route.name;
                });
        };
        $scope.list_domains_network = function(id_network) {
                $http.get('/route/list_domains/'+id_network).then(function(response) {
                    $scope.machines = response.data;
                });
        };
        $scope.set_network_domain= function(id_domain, field, allowed) {
            $http.get("/v2/route/set/"+$scope.route.id+ "/" + field+ "/" +id_domain+"/"
                    +allowed)
                .then(function(response) {
                });
        };
        $scope.set_domain_public = function( id_domain, is_public) {
            $http.get('/machine/set/'+id_domain+'/is_public/'+is_public)
                .then(function(response) {
            });
        };

        $scope.remove_route = function(id_network) {
            if ($scope.route.name == 'default') {
                $scope.error = $scope.route.name + " network can't be removed";
                return;
            }
            $http.get('/v2/route/remove/'+id_network).then(function(response) {
                window.location.assign('/admin/routes');
            });
        };
        $scope.check_duplicate = function(field) {
            var args = {};
            if (typeof ($scope.route['id']) != 'undefined') {
                args['id'] = $scope.route['id'];
            }
            args[field] = $scope.route[field];

            $http.post("/v1/exists/networks",JSON.stringify(args))
                .then(function(response) {
                    $scope.route["_duplicated_"+field]=response.data.id;
            });
        };
        $scope.new_saved = false;
    };

    function settings_node($scope, $http, $timeout) {
        var url_ws;
        var id_node;
        var listed_sp = false;
        $scope.init = function(id, url) {
            id_node = id;
            url_ws = url;
            list_bases(id_node);
            list_templates(id_node);
            subscribe_node_info(id_node, url);
            subscribe_list_host_devices(id_node, url);
        };
        subscribe_node_info = function(id_node, url) {
            var ws = new WebSocket(url);
            ws.onopen = function(event) { ws.send('node_info/'+id_node) };
            ws.onmessage = function(event) {
                if (!$scope.formNode.$pristine) {
                    return;
                }
                var data = JSON.parse(event.data);
                $scope.$apply(function () {
                    $scope.node = data;
                    $scope.node._old_name = data.name;
                    $scope.old_node =$.extend({}, data);

                    if (data.is_active && !listed_sp) {
                        listed_sp = true;
                        list_storage_pools(id_node);
                    }
                });
            }
        };

        subscribe_list_host_devices= function(id, url) {
            $scope.show_requests = false;
            $scope.host_devices = [];
            var ws = new WebSocket(url);
            ws.onopen    = function (event) { ws.send('list_host_devices/'+id) };
            ws.onclose = function() {
                ws = new WebSocket(url);
            };

            ws.onmessage = function (event) {
                var data = JSON.parse(event.data);
                $scope.$apply(function () {
                    if (Object.keys($scope.host_devices).length != data.length) {
                        $scope.host_devices.length = data.length;
                    }
                    for (var i=0, iLength = data.length; i<iLength; i++){
                        var hd = data[i];
                        if (typeof($scope.host_devices[i]) == 'undefined') {
                            $scope.host_devices[i] = hd;
                        } else if ( $scope.host_devices[i].id != hd.id
                            || $scope.host_devices[i].date_changed != hd.date_changed
                            || $scope.host_devices[i]['loading']
                        ) {
                            var keys = Object.keys(hd);
                            for ( var n_key=0 ; n_key<keys.length ; n_key++) {
                               var field=keys[n_key];
                                if (field != 'filter' && $scope.host_devices[i][field] != hd[field]) {
                                    $scope.host_devices[i][field] = hd[field];
                                }
                            }
                        }
                    }
                });
            }
        };

        $scope.load_node = function() {
            $scope.node = $.extend({},$scope.old_node);
            $scope.error = '';
        };

        $scope.update_node = function() {
            var data = $scope.node;
            $scope.saved = false;
            $scope.error = '';
            $http.post('/v1/node/set/'
                , JSON.stringify(data))
            //                    , JSON.stringify({ value: $scope.network[field]}))
                .then(function(response) {
                    if (response.data.ok == 1){
                        $scope.saved = true;
                    }
                    $scope.error = response.data.error;
                    console.log($scope.error);
                });
            $scope.formNode.$setPristine();
        };

        subscribe_request = function(id_request, action) {
            var ws = new WebSocket(url_ws);
            ws.onopen = function(event) { ws.send('request/'+id_request) };
            ws.onmessage = function(event) {
                var data = JSON.parse(event.data);
                action(data);
            }
        };


        list_storage_pools = function(id_vm) {
            $http.post('/request/list_storage_pools/'
                ,JSON.stringify({ 'id_vm': id_vm })
            ).then(function(response) {
                if (response.data.ok == 1 ) {
                    subscribe_request(response.data.request, function(data) {
                        $scope.$apply(function () {
                            if (data['output'] && data.output.length) {
                                $scope.storage_pools=JSON.parse(data.output);
                            }
                        });
                    });
                } else {
                    $scope.storage_pools = response.data.error;
                }
            });
        };

        list_bases = function(id_vm) {
            $http.get('/node/list_bases/'+id_vm).then(function(response) {
                $scope.bases = response.data;
            });
        };

        list_templates = function(id) {
            $http.get('/host_devices/templates/list/'+ id)
            .then(function(response) {
                   $scope.templates = response.data;
               });
        };

        $scope.set_base_vm = function(id_base, value) {
            var url = 'set_base_vm';
            if (value == 0 || !value) {
                url = 'remove_base_vm';
            }
            $http.get("/machine/"+url+"/" +$scope.node.id+ "/" +id_base+".json")
                .then(function(response) {
                });
        };

        $scope.remove_node = function(id_node) {
            $http.get('/v1/node/remove/'+id_node).then(function(response) {
                $scope.message = "Node "+$scope.node.name+" removed";
                $scope.node={};
            });
        };

        $scope.add_host_device = function() {
            $http.post('/node/host_device/add'
                ,JSON.stringify({ 'template': $scope.new_template.name , 'id_vm': id_node }))
            .then(function(response) {
            });
        };

        $scope.update_host_device = function(hdev) {
            hdev._loading=true;
            hdev.devices_node=[];
            hdev._nodes = [];
            $http.post('/node/host_device/update'
                ,JSON.stringify(hdev))
            .then(function(response) {
                $scope.error = response.data.error;
            });
            hdev.devices = undefined;
        };
        $scope.remove_host_device = function(id) {
            $http.get('/node/host_device/remove/'+id).then(function(response) {
                // TODO: add some reponse
            });
        };

        $scope.toggle_show_hdev = function(id) {
            $scope.show_hdev[id] = ! $scope.show_hdev[id];
        };
        $scope.show_hdev = { 1: true};

    };

    function admin_groups_ctrl($scope, $http) {
        $scope.group_filter = '';
        $scope.username_filter = '';
        var type;
        var group_name;
        var group_id;
        $scope.init = function(type0, group_name0, group_id0) {
            type = type0;
            group_name = group_name0;
            group_id = group_id0;
            $scope.list_group_members();
        };
        $scope.list_ldap_groups = function() {
            $http.get('/group/ldap/list/'+$scope.group_filter)
                .then(function(response) {
                    $scope.ldap_groups=response.data;
                });
        };
        list_local_groups=function() {
            $http.get('/group/local/list_data')
                .then(function(response) {
                    $scope.local_groups=response.data;
                    $scope.local_groups_all=response.data;
                });
        }
        $scope.filter_local_groups=function() {
            $scope.local_groups = [];
            var re = new RegExp($scope.group_filter);
            for (var i=0; i<$scope.local_groups_all.length; i++) {
                if (re.test($scope.local_groups_all[i].name)) {
                    $scope.local_groups.push($scope.local_groups_all[i]);
                }
            }
        };
        $scope.list_groups=function() {
            $scope.list_ldap_groups();
            list_local_groups();
        };

        $scope.list_group_members = function() {
            group = group_name;
            $http.get('/group/'+type+'/list_members/'+group_name)
                .then(function(response) {
                    $scope.group_members=response.data;
                });
        };
        $scope.list_users = function() {
            $scope.loading_users = true;
            $scope.error = '';
            $http.get('/user/'+type+'/list/'+$scope.username_filter)
                .then(function(response) {
                    $scope.loading_users = false;
                    $scope.error = response.data.error;
                    $scope.users = response.data.entries;
                });
        };
        $scope.add_member = function(user_id, user_name) {
            $http.post("/group/"+type+"/add_member/"
              ,JSON.stringify(
                  { 'group': group_name
                    ,'id_user': user_id
                    ,'id_group': group_id
                    ,'name': user_name
                  })
              ).then(function(response) {
                  $scope.list_group_members();
                  $scope.error = response.data.error;
            });
        };
        $scope.remove_member = function(user) {
            $http.post("/group/"+type+"/remove_member/"
              ,JSON.stringify(
                  { 'group': group
                    ,'id_user': user.id
                      ,'name': user.name
                  })
              ).then(function(response) {
                  $scope.list_group_members(group);
                  $scope.error = response.data.error;
            });
        };
        $scope.remove_group = function() {
            $scope.confirm_remove=false;
            $http.get("/group/"+type+"/remove/"+group).then(function(response) {
                $scope.error=response.data.error;
                $scope.removed = true;
            });
        };

    }

    function settings_global_ctrl($scope, $http) {
        $scope.timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
        $scope.csp_locked = false;
        $scope.set_csp_locked=function() {
            var keys = Object.keys($scope.settings.frontend.content_security_policy);
            var found = 0;
            for ( var n_key=0 ; n_key<keys.length ; n_key++) {
                var field=keys[n_key];
                if ( field != 'all' && field != 'id' && field != 'value'
                    && $scope.settings.frontend.content_security_policy[field].value) {
                    found++;
                }
            }
            $scope.csp_locked = found>0;
            if ($scope.csp_locked && !$scope.csp_advanced) {
                $scope.csp_advanced = true;
            }
        };
        $scope.init = function(url, csp_advanced) {
            $scope.csp_advanced=false;
            if (csp_advanced) {
                $scope.csp_advanced=true;
            }
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
                $scope.set_csp_locked();
            });
        };
        $scope.load_settings = function() {
            $scope.init();
            $scope.set_csp_locked();
            $scope.formSettings.$setPristine();
        };
        $scope.update_settings = function() {
            $scope.formSettings.$setPristine();
            $http.post('/settings_global'
                ,JSON.stringify($scope.settings)
            ).then(function(response) {
                $scope.set_csp_locked();
                if (response.data.reload) {
                    window.location.reload();
                }
            });
        };
    };


    function admin_charts_ctrl($scope, $http) {
        $scope.data = [];
        $scope.labels = [];
        $scope.bases = undefined;
        var my_chart;
        var ws;

        $scope.hour = 1;
        $scope.day = 0;
        $scope.week = 0;
        $scope.month = 0;
        $scope.year = 0;

        var max_y = 10;
        $scope.options_h = [
            {id:0, title: 'hours'}
            ,{id:1 , title: '1 hour'}
            ,{id:2 , title: '2 hours'}
            ,{id:3 , title: '3 hours'}
            ,{id:6 , title: '6 hours'}
            ,{id:8 , title: '8 hours'}
        ];
        $scope.options_d = [
            {id:0 , title: 'days'}
            ,{id:1 , title: '1 day'}
            ,{id:2 , title: '2 days'}
            ,{id:3 , title: '3 days'}
            ,{id:6 , title: '6 days'}
        ];
        $scope.options_w = [
            {id:0 , title: 'weeks'}
            ,{id:1 , title: '1 week'}
            ,{id:2 , title: '2 weeks'}
            ,{id:3 , title: '3 weeks'}
            ,{id:4 , title: '4 weeks'}
        ];
        $scope.options_m = [
            {id:0 , title: 'months'}
            ,{id:1 , title: '1 month'}
            ,{id:2 , title: '2 months'}
            ,{id:3 , title: '3 months'}
            ,{id:6 , title: '6 months'}
            ,{id:9 , title: '9 months'}
        ];
        $scope.options_y = [
            {id:0 , title: 'years'}
            ,{id:1 , title: '1 year'}
            ,{id:2 , title: '2 years'}
            ,{id:3 , title: '3 years'}
            ,{id:6 , title: '6 years'}
            ,{id:9 , title: '9 years'}
        ];

        var url;

        $scope.init = function(url0) {
            $scope.last_type='hour';
            ws = new WebSocket(url0);
            subscribe_log_active_domains(url0,'hours',1);
            url = url0;
        }

        $scope.load_chart = function(type) {
            $scope.last_type = type;
            var time = $scope[type];
            if (type == 'hour') {
                $scope.day=0;$scope.week=0;$scope.month=0;$scope.year=0;
            } else if( type =='day') {
                $scope.hour=0;$scope.week=0;$scope.month=0;$scope.year=0;
            } else if ( type == 'week') {
                $scope.hour=0; $scope.day=0;$scope.month=0;$scope.year=0;
            } else if ( type == 'month') {
                $scope.hour=0; $scope.day=0;$scope.week=0;$scope.year=0;
            } else if ( type == 'year') {
                $scope.hour=0; $scope.day=0;$scope.week=0;$scope.month=0;
            }
            send_params(type+"s",time);
        };

        send_params = function(unit,time) {
            var id_base= '';
            if (typeof($scope.base) != 'undefined' && $scope.base ) {
                id_base = $scope.base.id;
            }
            ws.send('log_active_domains/'+unit+'/'+time+'/'+id_base);

        };

        subscribe_log_active_domains = function(url,unit,time) {
            var chart_data = {
                labels: [],
                datasets: [{
                    label: 'Active',
                    backgroundColor: 'rgb(0, 199, 132)',
                    borderColor: 'rgb(0, 99, 132)',
                    data: [],
                    tension: 0.2
                }]
            };
            var chart_config ={
                type: 'line',
                data: chart_data,
                options: {
                    scales : {
                        y : {
                            min: 0,
                            max: max_y
                        }
                    }
                    ,borderColor: 'black'
                }
            };
            my_chart = new Chart(
                            document.getElementById('myChart'),
                            chart_config
                        );

            ws.onopen = function(event) {
                send_params(unit,time);
            };
            ws.onmessage = function(event) {
                var data = JSON.parse(event.data);
                $scope.$apply(function () {
                    $scope.data = data.data;
                    $scope.labels = data.labels;
                    if (typeof($scope.bases) == 'undefined' || $scope.bases.length != data.bases) {
                        $scope.bases = data.bases;
                            for (var i=0; i<$scope.bases.length; i++) {
                                if (!$scope.base && $scope.bases[i].id == 0 ) {
                                    $scope.base = $scope.bases[i];
                                }
                                if($scope.base && $scope.bases[i].id==$scope.base.id) {
                                    $scope.base = $scope.bases[i];
                                }
                            }
                    }

                    chart_config.data.datasets[0].data = data.data;
                    chart_config.data.labels = data.labels;
                    var new_max = Math.max(...data.data);
                    var div = 5;
                    if (new_max>30) { div = 10 };
                    new_max = Math.round(new_max/div+1)*div;
                    if (new_max > chart_config.options.scales.y.max) {
                        chart_config.options.scales.y.max = new_max;
                    }
                    my_chart.update();

                });
            }
        };


    };

    function upload_users($scope, $http) {
        $scope.type = 'sql';
    };
}());
