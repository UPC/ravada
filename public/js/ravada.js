

    var ravadaApp = angular.module("ravada.app",['ngResource','ngSanitize'])
            .config( [
                '$compileProvider',
                function( $compileProvider )
                {
                    $compileProvider.aHrefSanitizationWhitelist(/^\s*(https?|spice|mailto|chrome-extension):/);
        // Angular before v1.2 uses $compileProvider.urlSanitizationWhitelist(...)
                }
            ])
            .directive("solShowSupportform", swSupForm)
            //TODO check if the next directive may be removed
            .directive("solShowNewmachine", swNewMach)
            .directive("solShowListmachines", swListMach)
	        .directive("solShowListusers", swListUsers)
            .directive("solShowCardsmachines", swCardsMach)
            .directive("solShowMachinesNotifications", swMachNotif)
            .directive("nameAvailable", nameAvail)
            .service("request", gtRequest)
            .service("listMach", gtListMach)
            .service("listMess", gtListMess)
            .controller("SupportForm", suppFormCtrl)
	        .controller("AddUserForm",addUserFormCrtl)
//            .controller("machines", machinesCrtl)
//            .controller("messages", messagesCrtl)
            .controller("users", usersCrtl)
            .controller("bases", mainpageCrtl)
            .controller("singleMachinePage", singleMachinePageC)
            .controller("maintenance",maintenanceCtrl)
            .controller("notifCrtl", notifCrtl)
            .controller("run_domain",run_domain_ctrl)
            .controller("run_domain_req",run_domain_req_ctrl)



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

    function suppFormCtrl($scope){
	this.user = {};
        $scope.showErr = false;
        $scope.isOkey = function() {
            if($scope.contactForm.$valid){
                $scope.showErr = false;
            } else{
                $scope.showErr = true;
            }
        }

    };

    function swSupForm() {
	
        return {
            restrict: "E",
            templateUrl: '/ng-templates/support_form.html',
        };

    };


    function addUserFormCrtl($scope, $http, request){
               
       
    };

    function swNewMach() {

        return {
            restrict: "E",
            templateUrl: '/templates/new_machine.html',
        };

    };
    // list machines
        function mainpageCrtl($scope, $http, $timeout, request, listMach) {
            $scope.set_restore=function(machineId) {
                $scope.host_restore = machineId;
            };
            $scope.restore= function(machineId){
              $http.post('/request/restore_domain/'
                      , JSON.stringify({ 'id_domain': machineId
                      })
              );
            };
            $scope.action = function(machine, action) {
                machine.action = false;
                if ( action == 'restore' ) {
                    $scope.host_restore = machine.id_clone;
                    $scope.host_shutdown = 0;
                } else if (action == 'shutdown' || action == 'hibernate') {
                    $scope.host_restore = 0;
                    $http.get( '/machine/'+action+'/'+machine.id_clone+'.json');
                } else {
                    alert("unknown action "+action);
                }

            };
            ws_connected = false;
            $timeout(function() {
                if (typeof $scope.public_bases === 'undefined') $scope.public_bases = 0;
                if (!ws_connected) {
                    $scope.ws_fail = true;
                }
            }, 60 * 1000 );

            $scope.subscribe_list_machines_user = function(url) {
                $scope.machines = [];
                var channel = 'list_machines_user';
                if ($scope.anonymous) {
                    channel = 'list_bases_anonymous';
                }
                var ws = new WebSocket(url);
                ws.onopen = function(event) {
                    $scope.ws_fail = false;
                    ws_connected = true;
                    ws.send(channel);
                };
                ws.onclose = function() {
                    ws = new WebSocket(url);
                };
                ws.onmessage = function(event) {
                    var data = JSON.parse(event.data);
                    $scope.$apply(function () {
                        $scope.public_bases = 0;
                        $scope.private_bases = 0;
                        if ($scope.machines && $scope.machines.length != data.length) {
                            $scope.machines = [];
                        }
                        for (var i = 0; i < data.length; i++) {
                            if ( !$scope.machines[i] || $scope.machines[i].id != data[i].id ) {
                                $scope.machines[i] = data[i];
                                $scope.machines[i].description = data[i].description;
                            } else {
                                $scope.machines[i].can_hibernate = data[i].can_hibernate;
                                $scope.machines[i].id= data[i].id;
                                $scope.machines[i].id_clone = data[i].id_clone;
                                $scope.machines[i].is_active = data[i].is_active;
                                $scope.machines[i].is_locked = data[i].is_locked;
                                $scope.machines[i].is_public = data[i].is_public;
                                $scope.machines[i].name = data[i].name;
                                $scope.machines[i].name_clone = data[i].name_clone;
                                $scope.machines[i].screenshot = data[i].screenshot;
                                $scope.machines[i].description = data[i].description;
                            }
                            if ( data[i].is_public == 1) {
                                $scope.public_bases++;
                            } else {
                                $scope.private_bases++;
                            }
                        }
                    });
                }
            };

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
            $scope.subscribe_ws = function(url) {
                subscribe_list_machines_user(url);
                subscribe_ping_backend(url);
            };

            $scope.only_public = false;
            $scope.toggle_only_public=function() {
                    $scope.only_public = !$scope.only_public;
            };
            $scope.startIntro = startIntro;
        };

        function singleMachinePageC($scope, $http, $interval, request, $location) {
            subscribe_machine_info= function(url) {
                var ws = new WebSocket(url);
                ws.onopen = function(event) { ws.send('machine_info/'+$scope.showmachineId) };
                ws.onmessage = function(event) {
                    var data = JSON.parse(event.data);
                    $scope.$apply(function () {
                        $scope.showmachine = data;
                        $scope.list_bases();
                        subscribe_nodes(url,data.type);
                    });
                }
            };

            subscribe_requests = function(url) {
                var ws = new WebSocket(url);
                ws.onopen = function(event) { ws.send('list_requests') };
                ws.onclose = function() {
                    ws = new WebSocket(url);
                };
                ws.onmessage = function(event) {
                    var data = JSON.parse(event.data);
                    $scope.$apply(function () {
                        $scope.alerts_ws = data;
                    });
                }
            };

            subscribe_isos = function(url) {
                var ws = new WebSocket(url);
                ws.onopen = function(event) { ws.send('list_isos') };
                ws.onmessage = function(event) {
                    var data = JSON.parse(event.data);
                    $scope.$apply(function () {
                        $scope.list_isos = data;
                    });
                }
            };
            $scope.new_node_start = true;
            subscribe_nodes = function(url, type) {
                var ws = new WebSocket(url);
                ws.onopen = function(event) { ws.send('list_nodes/'+type) };
                ws.onmessage = function(event) {
                    var data = JSON.parse(event.data);
                    $scope.$apply(function () {
                        $scope.nodes = data;
                        for (var i = 0; i < $scope.nodes.length; i++) {
                            if ($scope.new_node) {
                                if ($scope.new_node.id == $scope.nodes[i].id) {
                                    $scope.new_node = $scope.nodes[i];
                                    return
                                }
                            } else {
                                if ($scope.nodes[i].id == $scope.showmachine.id_vm) {
                                    $scope.new_node = $scope.nodes[i];
                                    return;
                                }
                            }
                        }
                    });
                }
            };
            subscribe_ws = function(url, is_admin) {
                subscribe_machine_info(url);
                subscribe_requests(url);
                subscribe_isos(url);
            };

          var url_ws;
          $scope.init = function(id, url,is_admin) {
                url_ws = url;
                $scope.showmachineId=id;
                $scope.tab_access=['client']
                $scope.client_attributes = [ 'User-Agent'
                   , 'Accept', 'Connection', 'Accept-Language', 'DNT', 'Host'
                   , 'Accept-Encoding', 'Cache-Control', 'X-Forwarded-For'
                ];
                subscribe_ws(url_ws, is_admin);
                $http.get('/machine/info/'+$scope.showmachineId+'.json')
                    .then(function(response) {
                            $scope.showmachine=response.data;
                            if (typeof $scope.new_name == 'undefined' ) {
                                $scope.new_name=$scope.showmachine.name+"-2";
                                $scope.validate_new_name($scope.showmachine.name);
                                $scope.new_n_virt_cpu= $scope.showmachine.n_virt_cpu;
                                $scope.new_memory = ($scope.showmachine.memory / 1024);
                                $scope.new_max_mem = ($scope.showmachine.max_mem / 1024);

                                $scope.new_run_timeout = ($scope.showmachine.run_timeout / 60);
                                if (!$scope.new_run_timeout) $scope.new_run_timeout = undefined;

                                $scope.new_volatile_clones = $scope.showmachine.volatile_clones;
                                $scope.new_autostart = $scope.showmachine.autostart;
                                $scope.new_shutdown_disconnected
                                    = $scope.showmachine.shutdown_disconnected;
                            }
                            $scope.init_domain_access();
                            $scope.init_ldap_access();
                            $scope.list_ldap_attributes();
                            list_interfaces();
                            $scope.hardware_types = Object.keys(response.data.hardware);
                            $scope.copy_ram = $scope.showmachine.max_mem / 1024 / 1024;
                            if (is_admin) list_users();
                });
          };

          list_interfaces = function() {
            if (! $scope.network_nats) {
                $http.get('/network/interfaces/'+$scope.showmachine.type+'/nat')
                    .then(function(response) {
                        $scope.network_nats = response.data;
                });
            }
            if (! $scope.network_bridges ) {
                $http.get('/network/interfaces/'+$scope.showmachine.type+'/bridge')
                    .then(function(response) {
                        $scope.network_bridges= response.data;
                });
            }
          };
          $scope.domain_remove = 0;
          $scope.new_name_invalid = false;
          $scope.machine_info = function(id) {
               $http.get('/machine/info/'+$scope.showmachineId+'.json')
                    .then(function(response) {
                            $scope.showmachine=response.data;
                    });
          };
          $scope.remove = function(machineId) {
            $http.get('/machine/remove/'+machineId+'.json');
          };
          $scope.remove_clones = function(machineId) {
                $http.get('/machine/remove_clones/'+machineId+'.json');
          };

          $scope.reload_page_msg = false;
          $scope.fail_page_msg = false;
          $scope.screenshot = function(machineId) {
                  $scope.reload_page_msg = true;
                  setTimeout(function () {
                    $scope.reload_page_msg = false;
                  }, 2000);
                  $http.get('/machine/screenshot/'+machineId+'.json');
          };
          
          $scope.reload_page_copy_msg = false;
          $scope.fail_page_copy_msg = false;
          $scope.copy_done = false;
          $scope.copy_screenshot = function(machineId){
                $scope.reload_page_msg = false;
                $scope.reload_page_copy_msg = true;
                setTimeout(function () {
                    $scope.reload_page_copy_msg = false;
                }, 2000);
                $http.get('/machine/copy_screenshot/'+machineId+'.json');
          };

          subscribe_request = function(id_request, action) {
                var ws = new WebSocket(url_ws);
                ws.onopen = function(event) { ws.send('request/'+id_request) };
                ws.onmessage = function(event) {
                    var data = JSON.parse(event.data);
                    action(data);
                }
            };


          $scope.rename = function(machineId, old_name) {
            if ($scope.new_name_duplicated || $scope.new_name_invalid) return;

            $scope.rename_request= { 'status': 'requested' };

            $http.get('/machine/rename/'+machineId+'/'
            +$scope.new_name).then(function(response) {
                subscribe_request(response.data.req, function(data) {
                    $scope.$apply(function () {
                        $scope.rename_request=data;
                    });
                });
            });
          };
          $scope.cancel_rename=function(old_name) {
                $scope.new_name = old_name;
          };

          $scope.validate_new_name = function(old_name) {
            $scope.new_name_duplicated = false;
            if(old_name == $scope.new_name) {
              $scope.new_name_invalid=false;
              return;
            }
            var valid_domain_name = /^[a-zA-Z][\w_-]+$/;
            if ( !valid_domain_name.test($scope.new_name)) {
                $scope.new_name_invalid = true;
                return;
            }
            $scope.new_name_invalid = false;
            $http.get('/machine/exists/'+$scope.new_name)
            .then(duplicated_callback, unique_callback);
            function duplicated_callback(response) {
              $scope.new_name_duplicated=response.data;
            };
            function unique_callback() {
              $scope.new_name_duplicated=false;
            }
          };

          $scope.set_bool = function(field, value) {
            if (value ) value=1;
                else value=0;
            $scope.showmachine[field]=value;
            value_show = true;
            if (! value) {
                value_show = false;
            }
            if ($scope.pending_request && $scope.pending_request.status == 'done' ) {
                $scope.pending_request = undefined;
            }
            $http.get("/machine/set/"+$scope.showmachine.id+"/"+field+"/"+value);
          };

          $scope.set = function(field) {
            if ($scope.pending_request && $scope.pending_request.status == 'done' ) {
                $scope.pending_request = undefined;
            }
            $http.get("/machine/set/"+$scope.showmachine.id+"/"+field+"/"+$scope.showmachine[field]);
          };
          $scope.set_value = function(field,value) {
            if ($scope.pending_request && $scope.pending_request.status == 'done' ) {
                $scope.pending_request = undefined;
            }
            $http.get("/machine/set/"+$scope.showmachine.id+"/"+field+"/"+value);
          };
          $scope.set_public = function(machineId, value) {
            if (value) value=1;
            else value=0;
            $http.get("/machine/public/"+machineId+"/"+value);
          };
          $scope.set_base= function(vmId,machineId, value) {
            if (value == 0 || !value) {
                url = 'remove_base_vm';
            } else {
                url = 'set_base_vm';
            }
            $http.get("/machine/"+url+"/" +vmId+ "/" +machineId+".json")
              .then(function(response) {
              });
          };
          $scope.copy_machine = function() {
              $scope.copy_request= { 'status': 'requested' };
              $http.post('/machine/copy/'
                      , JSON.stringify({ 'id_base': $scope.showmachine.id
                            ,'copy_number': $scope.copy_number
                          ,'copy_ram': $scope.copy_ram
                          ,'new_name': $scope.new_name
                      })
              ).then(function(response) {
                  // if there are many , we pick the last one
                  id_request = response.data.request;
                  subscribe_request(id_request, function(data) {
                    $scope.$apply(function () {
                        $scope.copy_request=data;
                    });
                  });
              });
          };

          //On load code
//          $scope.showmachineId = window.location.pathname.split("/")[3].split(".")[0] || -1 ;
          $scope.add_hardware = function(hardware, number, extra) {
              if (hardware == 'disk' && ! extra) {
                  $scope.show_new_disk = true;
                  return;
              }
              if ( hardware == 'disk' && extra.device == 'cdrom') {
                  extra.driver = 'ide';
              }
              $http.post('/machine/hardware/add/'
                      , JSON.stringify({ 'id_domain': $scope.showmachine.id
                            ,'hardware': hardware
                            ,'number': number
                            ,'data': extra
                      })
              ).then(function(response) {
                      });
          };
          $scope.remove_hardware = function(hardware, index, item, confirmation) {
            if (hardware == 'disk') {
                if (!confirmation) {
                    item.remove = !item.remove;
                    return;
                }
            }
            item.remove = false;
              $http.get('/machine/hardware/remove/'
                      +$scope.showmachine.id+'/'+hardware+'/'+index).then(function(response) {
                      });

          };
          $scope.list_ldap_attributes= function() {
              $scope.ldap_entries = 0;
              $scope.ldap_verified = 0;
              $http.get('/list_ldap_attributes/'+$scope.cn).then(function(response) {
                  $scope.ldap_attributes = response.data.attributes;
              });
          };
          $scope.count_ldap_entries = function() {
              $scope.ldap_verifying = true;
              $http.get('/count_ldap_entries/'+$scope.ldap_attribute+'/'+$scope.ldap_attribute_value)
                    .then(function(response) {
                  $scope.ldap_entries = response.data.entries;
                  $scope.ldap_verified = true;
                  $scope.ldap_verifying = false;
              });
          };
          $scope.expose = function(port, name, restricted, id_port) {
              if (restricted == "1" || restricted == true) {
                  restricted = 1;
              } else {
                  restricted = 0;
              }
              $http.post('/request/expose/'
                  ,JSON.stringify({
                        'id_domain': $scope.showmachine.id
                        ,'port': port
                        ,'name': name
                        ,'restricted': restricted
                        ,'id_port': id_port
                  })
                ).then(function(response) {
              });
              $scope.init_new_port();
          };
          $scope.remove_expose = function(port) {
              $http.post('/request/remove_expose/'
                  ,JSON.stringify({
                        'id_domain': $scope.showmachine.id
                        ,'port': port
                  })
                ).then(function(response) {
              });
          };


          $scope.add_access = function(type) {
              $http.post('/machine/add_access/'+$scope.showmachine.id
                    ,JSON.stringify({
                        'type': type
                        ,'attribute': $scope.access_attribute[type]
                        ,'value': $scope.access_value[type]
                        ,'allowed': $scope.access_allowed[type]
                        ,'last': $scope.access_last[type]
                    })
                    ).then(function(response) {
                        if (type == 'ldap') { $scope.init_ldap_access() }
                        else { $scope.init_domain_access() }
                    });
          };

          $scope.add_ldap_access = function() {
              $http.get('/add_ldap_access/'+$scope.showmachine.id+'/'+$scope.ldap_attribute+'/'
                            +$scope.ldap_attribute_value+"/"+$scope.ldap_attribute_allowed
                            +'/'+$scope.ldap_attribute_last)
                    .then(function(response) {
                        $scope.init_ldap_access();
                    });
          };
          $scope.delete_ldap_access= function(id_access) {
              $http.get('/delete_ldap_access/'+$scope.showmachine.id+'/'+id_access)
                    .then(function(response) {
                        $scope.init_ldap_access();
                    });
          };
          $scope.move_ldap_access= function(id_access, count) {
              $http.get('/move_ldap_access/'+$scope.showmachine.id+'/'+id_access+'/'+count)
                    .then(function(response) {
                        $scope.init_ldap_access();
                    });
          };
          $scope.set_ldap_access = function(id_access, allowed, last) {
              $http.get('/set_ldap_access/'+$scope.showmachine.id+'/'+id_access+'/'+allowed
                        +'/'+last)
                    .then(function(response) {
                        $scope.init_ldap_access();
                    });
          };
          $scope.move_access= function(type, id_access, count) {
              $http.get('/machine/move_access/'+$scope.showmachine.id+'/'
                        +id_access+'/'+count)
                    .then(function(response) {
                        $scope.init_domain_access();
                    });
          };
 
          $scope.set_access = function(id_access, allowed, last) {
              $http.get('/machine/set_access/'+$scope.showmachine.id+'/'+id_access+'/'+allowed
                        +'/'+last)
                    .then(function(response) {
                        $scope.init_domain_access();
                    });
          };

          $scope.init_ldap_access = function() {
              $scope.ldap_entries = 0;
              $scope.ldap_verified = 0;
              $scope.ldap_attribute = '';
              $scope.ldap_attribute_value = '';
              $scope.ldap_attribute_allowed=true;
              $scope.ldap_attribute_last=true;
              $http.get('/list_ldap_access/'+$scope.showmachine.id).then(function(response) {
                  $scope.ldap_attributes_domain  = response.data.list;
                  $scope.ldap_attributes_default = response.data.default;
              });
          };
          $scope.init_domain_access = function() {
              $http.get('/machine/list_access/'+$scope.showmachine.id).then(function(response) {
                  $scope.domain_access  = response.data.list;
                  $scope.domain_access_default = response.data.default;
              });

              $http.get('/machine/check_access/'+$scope.showmachine.id)
                      .then(function(response) {
                          $scope.check_client_access = response.data.ok;
                  });
          };
          $scope.delete_access= function(id_access) {
              $http.get('/machine/delete_access/'+$scope.showmachine.id+'/'+id_access)
                    .then(function(response) {
                        $scope.init_domain_access();
                    });
          };

          $scope.init_new_port = function() {
              $scope.new_port = null;
              $scope.new_port_name = null;
              $scope.new_port_restricted = false;
          };
            $scope.change_disk = function(id_machine, index ) {
                var new_settings={
                  driver: $scope.showmachine.hardware.disk[index].driver,
                  boot: $scope.showmachine.hardware.disk[index].boot,
                  file: $scope.showmachine.hardware.disk[index].file,
                };
                if ($scope.showmachine.hardware.disk[index].device === 'disk') {
                  new_settings.capacity = $scope.showmachine.hardware.disk[index].capacity;
                }
                $http.post('/machine/hardware/change'
                    ,JSON.stringify({
                        'id_domain': id_machine
                        ,'hardware': 'disk'
                           ,'index': index
                            ,'data': new_settings
                    })
                ).then(function(response) {
                });

            };
            $scope.change_network = function(id_machine, index ) {
                var new_settings ={
                    driver: $scope.showmachine.hardware.network[index].driver,
                    type: $scope.showmachine.hardware.network[index].type,
                };
                if ($scope.showmachine.hardware.network[index].type == 'NAT' ) {
                    new_settings.network=$scope.showmachine.hardware.network[index].network;
                }
                if ($scope.showmachine.hardware.network[index].type == 'bridge' ) {
                    new_settings.bridge=$scope.showmachine.hardware.network[index].bridge;
                }
                $http.post('/machine/hardware/change'
                    ,JSON.stringify({
                        'id_domain': id_machine
                        ,'hardware': 'network'
                           ,'index': index
                            ,'data': new_settings
                    })
                ).then(function(response) {
                });
            };
            $scope.list_bases = function() {
                $http.get('/list_bases.json')
                    .then(function(response) {
                            $scope.bases=response.data;
                                for (var i = 0; i < $scope.bases.length; i++) {
                                    if ($scope.bases[i].id == $scope.showmachine.id_base) {
                                        $scope.new_base = $scope.bases[i];
                                    } else if ($scope.showmachine.is_base
                                        && $scope.bases[i].id == $scope.showmachine.id) {
                                        $scope.new_base = $scope.bases[i];
                                    }
                                }
                    });
            };
            list_users= function() {
                $http.get('/list_users.json')
                    .then(function(response) {
                        $scope.list_users=response.data;
                        for (var i = 0; i < response.data.length; i++) {
                            if (response.data[i].id == $scope.showmachine.id_owner) {
                                $scope.new_owner = response.data[i];
                            }
                        }
                    });
            }
            $scope.rebase= function() {
                $scope.req_new_base = $scope.new_base;
                $http.post('/request/rebase/'
                    , JSON.stringify({ 'id_base': $scope.new_base.id
                        ,'id_domain': $scope.showmachine.id
                        ,'retry': 5
                    })
                ).then(function(response) {
                    // if there are many , we pick the last one
                    id_request = response.data.request;
                    subscribe_request(id_request, function(data) {
                        $scope.$apply(function () {
                            $scope.rebase_request=data;
                            if ($scope.rebase_request.status == 'done') {
                                $scope.list_bases();
                            }
                        });
                    });
                });
            };

            $scope.add_disk = {
                device: 'disk',
                type: 'sys',
                driver: 'virtio',
                capacity: '1G',
                allocation: '0.1G'
            };

            $scope.request = function(request, args) {
                $scope.pending_request = undefined;
                $http.post('/request/'+request+'/'
                    ,JSON.stringify(args)
                ).then(function(response) {
                    if (! response.data.request ) {
                        $scope.pending_request = {
                            'status': 'done'
                            ,'error': response.data.error
                        };
                        return;
                    }
                    id_request = response.data.request;
                    subscribe_request(id_request, function(data) {
                        $scope.$apply(function () {
                            $scope.pending_request=data;
                            if ($scope.pending_request.status == 'done') {
                                $scope.list_bases();
                            }
                        });
                    });
                });
            };

            $scope.message = [];
            $scope.disk_remove = [];
            $scope.pending_before = 10;
//          $scope.getSingleMachine();
//          $scope.updatePromise = $interval($scope.getSingleMachine,3000);
            $scope.access_attribute = [ ];
            $scope.access_value = [ ];
            $scope.access_allowed = [ ];
            $scope.access_last = [ ];
          $scope.list_ldap_attributes();
        };

    function swListMach() {

        return {
            restrict: "E",
            templateUrl: '/ng-templates/list_machines.html',
        };

    };

    function swCardsMach() {

        $url =  '/ng-templates/user_machines.html';
        if ( typeof $_anonymous !== 'undefined' && $_anonymous ) {
            $url =  '/ng-templates/user_machines_anonymous.html';
        }

        return {
            restrict: "E",
            templateUrl: $url,
        };

    };

    function swMachNotif() {
        return {
            restrict: "E",
            templateUrl: '/ng-templates/machines_notif.html',
        };
    };

    function gtRequest($resource){

        return $resource('/requests.json',{},{
            get:{isArray:true}
        });

    };

    function gtListMach($resource){

        return $resource('/list_machines.json',{},{
            get:{isArray:true}
        });

    };

    function run_domain_req_ctrl($scope, $http, $timeout, request ) {
        var redirected_display = false;
        $scope.get_domain_info = function() {
            if ($scope.id_domain) {
                var seconds = 1000;
                $http.get('/machine/info/'+$scope.id_domain+'.json').then(function(response) {
                    $scope.domain = response.data;
                    if ($scope.domain.spice_password) {
                        var copyTextarea = document.querySelector('.js-copytextarea');
                        copyTextarea.value = $scope.domain.spice_password;
                        copyTextarea.length = 5;
                    }
                    if ($scope.domain.is_active) {
                        seconds = 5000;
                        $scope.redirect();
                        if ($scope.auto_view && !redirected_display && !$scope.domain.spice_password) {
                            location.href='/machine/display/'+$scope.domain.id+".vv";
                            redirected_display=true;
                        }
                    }
                    $timeout(function() {
                        $scope.get_domain_info();
                    },seconds);
                });
            }

        };
        $scope.wait_request = function() {
            if ($scope.id_request) {
                $http.get('/request/'+$scope.id_request+'.json').then(function(response) {
                    $scope.request=response.data;
                    if (response.data.status == 'done' ) {
                        $scope.id_domain=response.data.id_domain;
                        $scope.get_domain_info();
                    }
                });
            }

            if ( !$scope.id_domain ) {
                $timeout(function() {
                    $scope.wait_request();
                },1000);
            }
        }
        $scope.copy_password= function() {
            $scope.view_password=1;
            var copyTextarea = document.querySelector('.js-copytextarea');
            if (copyTextarea) {
                    copyTextarea.select();
                    try {
                        var successful = document.execCommand('copy');
                        var msg = successful ? 'successful' : 'unsuccessful';
                        console.log('Copying text command was ' + msg);
                        $scope.password_clipboard=successful;
                    } catch (err) {
                        console.log('Oops, unable to copy');
                    }

            }
        };
        $scope.redirect = function() {
            if (!$scope.redirect_done) {
                $timeout(function() {
                    if(typeof $_anonymous != "undefined" && $_anonymous){
                        window.location.href="/anonymous";                        
                    }
                    else {
                        window.location.href="/logout";
                    }
                }, $scope.timeout);
                $scope.redirect_done = true;
            }
        }

        $scope.redirect_done = false;
        $scope.wait_request();
        $scope.view_clicked=false;
    };
    function run_domain_ctrl($scope, $http, request ) {
        $http.get('/auto_view').then(function(response) {
            $scope.auto_view = response.auto_view;
        });
        $scope.toggle_auto_view = function() {
            $http.get('/auto_view/toggle').then(function(response) {
                $scope.auto_view = response.auto_view;
            });
        };
        $scope.copy_password= function() {
                    $scope.view_password=1;
                    var copyTextarea = document.querySelector('.js-copytextarea');
              if (copyTextarea) {

                    copyTextarea.select();
                    try {
                        var successful = document.execCommand('copy');
                        var msg = successful ? 'successful' : 'unsuccessful';
                        console.log('Copying text command was ' + msg);
                        $scope.password_clipboard=successful;
                    } catch (err) {
                        console.log('Oops, unable to copy');
                    }

              }
        };

    };
// list users
    function usersCrtl($scope, $http, request, listUsers) {

        $scope.make_admin = function(id) {
            $http.get('/users/make_admin/' + id + '.json')
            location.reload();
        };

        $scope.remove_admin = function(id) {
            $http.get('/users/remove_admin/' + id + '.json')
            location.reload();
        };

	$scope.add_user = function() {
            $http.get('/users/register')
            
        };

        $scope.checkbox = [];

        //if it is checked make the user admin, otherwise remove admin
        $scope.stateChanged = function(id,userid) { 
           if($scope.checkbox[id]) { //if it is checked
                $http.get('/users/make_admin/' + userid + '.json')
                location.reload();
           }
           else {
                $http.get('/users/remove_admin/' + userid + '.json')
                location.reload();
           }
        };

    };

    function swListUsers() {
	
        return {
            restrict: "E",
            templateUrl: '/ng-templates/list_users.html',
        };

    };

    function gtListMess($resource){

        return $resource('/messages.json',{},{
            get:{isArray:true}
        });

    };

  function notifCrtl($scope, $interval, $http, request){
    $scope.closeAlert = function(index) {
      var message = $scope.alerts_ws.splice(index, 1);
      var toGet = '/messages/read/'+message[0].id+'.json';
      $http.get(toGet);
    };

      $scope.subscribe_alerts = function(url) {
          var ws = new WebSocket(url);
          ws.onopen = function(event) { ws.send('list_alerts') };
          ws.onclose = function() {
                ws = new WebSocket(url);
          };

          ws.onmessage = function(event) {
              var data = JSON.parse(event.data);
              $scope.$apply(function () {
                  $scope.alerts_ws = data;
              });
          }

      }
      $scope.alerts_ws = [];


  };

    function maintenanceCtrl($scope, $interval, $http, request){
        $scope.init = function(end) {
            $scope.maintenance_end = new Date(end);
        };
    };

/*
  function requestsCrtlSingle($scope, $interval, $http, request){
    $scope.getReqs= function() {
      $http.get('/requests.json').then(function(response) {
          $scope.requests=response.data;
      });
    };
//    $interval($scope.getReqs,5000);
    $scope.getReqs();
  };
*/

	function nameAvail($timeout, $q) {
    return {
        restrict: 'AE',
        require: 'ngModel',
        link: function(scope, elm, attr, model) {
          model.$asyncValidators.nameExists = function() {

        //here you should access the backend, to check if username exists
        //and return a promise
        //here we're using $q and $timeout to mimic a backend call 
        //that will resolve after 1 sec

            var defer = $q.defer();
            $timeout(function(){
              model.$setValidity('nameExists', false);
              defer.resolve;
            }, 1000);
            return defer.promise;
          };
        }
      }
    };
