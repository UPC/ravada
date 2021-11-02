(function() {

ravadaApp.directive("solShowMachine", swMach)
        .directive("solShowNewmachine", swNewMach)
        .controller("new_machine", newMachineCtrl)
        .controller("machinesPage", machinesPageC)
        .controller("usersPage", usersPageC)
        .controller("messagesPage", messagesPageC)
        .controller("manage_nodes",manage_nodes)
        .controller("manage_networks",manage_networks)
        .controller("settings_node",settings_node)
        .controller("settings_network",settings_network)
        .controller("new_node", newNodeCtrl)
        .controller("settings_global", settings_global_ctrl)
        .controller("admin_groups", admin_groups_ctrl)
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
          $scope.id_iso_id = id.id;
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

  function machinesPageC($scope, $http, $timeout) {
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
              ws.send('list_machines_tree');
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
                      if (typeof $scope.list_machines[i] == 'undefined'
                            || $scope.list_machines[i].id != mach.id
                            || $scope.list_machines[i].date_changed != mach.date_changed
                      ){
                        var show=false;
                        if (mach._level == 0 ) {
                            mach.show=true;
                        }
                        if ($scope.show_machine[mach.id]) {
                            mach.show = $scope.show_machine[mach.id];
                        } else if(mach.id_base && $scope.show_clones[mach.id_base]) {
                            mach.show = true;
                        }
                        if (typeof $scope.show_clones[mach.id] == 'undefined') {
                            $scope.show_clones[mach.id] = false;
                        }
                        $scope.list_machines[i] = mach;
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
                   if(response.status == 300 ) {
                   console.error('Reponse error', response.status);
                   window.location.reload();
               }
            });
        }
    };
    $scope.set_autostart= function(machineId, value) {
      $http.get("/machine/autostart/"+machineId+"/"+value);
    };
    $scope.set_public = function(machineId, value) {
      if (value) value=1;
      else value = 0;
      $http.get("/machine/public/"+machineId+"/"+value)
        .then(function(response) {
            if(response.status == 300 ) {
              console.error('Reponse error', response.status);
            }
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
       for (var [key, mach ] of Object.entries($scope.list_machines)) {
            if (mach.id_base == id) {
                mach.show = $scope.show_clones[id];
                $scope.show_machine[mach.id] = mach.show;
                if ( !mach.show) {
                    $scope.set_show_clones(mach.id, false);
                }
            }
        }
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
    //On load code
    $scope.modalOpened=false;
    $scope.rename= {new_name: 'new_name'};
    $scope.show_rename = false;
    $scope.new_name_duplicated=false;
    $scope.show_clones = { '0': false };
    $scope.show_machine = { '0': false };
  };

    function usersPageC($scope, $http, $interval, request) {
        $scope.list_groups= function() {
            $scope.loading_groups = true;
            $scope.error = '';
            $http.get('/list_ldap_groups')
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
        list_networks= function() {
            $http.get('/list_networks.json').then(function(response) {
                    for (var i=0; i<response.data.length; i++) {
                        var item = response.data[i];
                        $scope.networks[item.id] = item;
                    }
                });
        }
        $scope.update_network= function(id, field) {
            var value = $scope.networks[id][field];
            var args = { 'id': id };
            args[field] = value;
            $http.post('/v1/network/set'
                , JSON.stringify( args ))
            .then(function(response) {
            });
        };


        $scope.networks={};
        list_networks();
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
                    console.log(response.data);
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

   function settings_network($scope, $http, $timeout) {
        var url_ws;
        $scope.init = function(id_network) {
            if (typeof id_network == 'undefined') {
                $scope.network = {
                    'name': ''
                    ,'all_domains': 1
                };
            } else {
                $scope.load_network(id_network);
                $scope.list_domains_network(id_network);
            }
        }
        $scope.check_no_domains = function() {
            if ( $scope.network.no_domains == 1 ){
                $scope.network.all_domains = 0;
            }
        };
        $scope.check_all_domains = function() {
            if ( $scope.network.all_domains == 1 ){
                $scope.network.no_domains = 0;
            }
        };
        $scope.update_network= function(field) {
            var data = $scope.network;
            if (typeof field != 'undefined') {
                var data = {};
                data[field] = $scope.network[field];
            }
            $scope.saved = false;
            $scope.error = '';
            $http.post('/v1/network/set/'
                , JSON.stringify(data))
            //                    , JSON.stringify({ value: $scope.network[field]}))
                .then(function(response) {
                    if (response.data.ok == 1){
                        $scope.saved = true;
                        if (!$scope.network.id) {
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
                $http.get('/network/info/'+id_network+'.json').then(function(response) {
                    $scope.network = response.data;
                    $scope.formNetwork.$setPristine();
                    $scope.network._old_name = $scope.network.name;
                });
        };
        $scope.list_domains_network = function(id_network) {
                $http.get('/network/list_domains/'+id_network).then(function(response) {
                    $scope.machines = response.data;
                });
        };
        $scope.set_network_domain= function(id_domain, field, allowed) {
            $http.get("/network/set/"+$scope.network.id+ "/" + field+ "/" +id_domain+"/"
                    +allowed)
                .then(function(response) {
                });
        };
        $scope.set_domain_public = function( id_domain, is_public) {
            $http.get('/machine/set/'+id_domain+'/is_public/'+is_public)
                .then(function(response) {
            });
        };

        $scope.remove_network = function(id_network) {
            if ($scope.network.name == 'default') {
                $scope.error = $scope.network.name + " network can't be removed";
                return;
            }
            $http.get('/v1/network/remove/'+id_network).then(function(response) {
                $scope.message = "Network "+$scope.network.name+" removed";
                $scope.network ={};
            });
        };
        $scope.check_duplicate = function(field) {
            var args = {};
            if (typeof ($scope.network['id']) != 'undefined') {
                args['id'] = $scope.network['id'];
            }
            args[field] = $scope.network[field];

            $http.post("/v1/exists/networks",JSON.stringify(args))
                .then(function(response) {
                    $scope.network["_duplicated_"+field]=response.data.id;
            });
        };
        $scope.new_saved = false;
    };

    function settings_node($scope, $http, $timeout) {
        var url_ws;
        $scope.init = function(id_node, url) {
            url_ws = url;
            list_storage_pools(id_node);
            list_bases(id_node);
            subscribe_node_info(id_node, url);
        };
        subscribe_node_info = function(id_node, url) {
            var ws = new WebSocket(url);
            ws.onopen = function(event) { ws.send('node_info/'+id_node) };
            ws.onmessage = function(event) {
                var data = JSON.parse(event.data);
                $scope.$apply(function () {
                    $scope.node = data;
                    $scope.node._old_name = data.name;
                    $scope.old_node =$.extend({}, data);
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
    };

    function admin_groups_ctrl($scope, $http) {
        var group;
        $scope.group_filter = '';
        $scope.username_filter = 'a';
        $scope.list_ldap_groups = function() {
            $http.get('/list_ldap_groups/'+$scope.group_filter)
                .then(function(response) {
                    $scope.ldap_groups=response.data;
                });
        };
        $scope.list_group_members = function(group_name) {
            group = group_name;
            $http.get('/list_ldap_group_members/'+group_name)
                .then(function(response) {
                    $scope.group_members=response.data;
                });
        };
        $scope.list_users = function() {
            $scope.loading_users = true;
            $scope.error = '';
            $http.get('/list_ldap_users/'+$scope.username_filter)
                .then(function(response) {
                    $scope.loading_users = false;
                    $scope.error = response.data.error;
                    $scope.users = response.data.entries;
                });
        };
        $scope.add_member = function(cn) {
            $http.post("/ldap/group/add_member/"
              ,JSON.stringify(
                  { 'group': group
                    ,'cn': cn
                  })
              ).then(function(response) {
                  $scope.list_group_members(group);
                  $scope.error = response.data.error;
            });
        };
        $scope.remove_member = function(dn) {
            $http.post("/ldap/group/remove_member/"
              ,JSON.stringify(
                  { 'group': group
                    ,'dn': dn
                  })
              ).then(function(response) {
                  $scope.list_group_members(group);
                  $scope.error = response.data.error;
            });
        };
        $scope.remove_group = function() {
            $scope.confirm_remove=false;
            $http.get("/ldap/group/remove/"+group).then(function(response) {
                $scope.error=response.data.error;
                $scope.removed = true;
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
            $http.post('/settings_global'
                ,JSON.stringify($scope.settings)
            ).then(function(response) {
                if (response.data.reload) {
                    window.location.reload();
                }
            });
        };
    };
}());
