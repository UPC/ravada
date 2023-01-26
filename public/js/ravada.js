    var ravadaApp = angular.module("ravada.app",['ngResource','ngSanitize','ravada.booking'])
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
	        .controller("ChangePasswordForm",changePasswordFormCrtl)
//            .controller("machines", machinesCrtl)
//            .controller("messages", messagesCrtl)
            .controller("users", usersCrtl)
            .controller("bases", mainpageCrtl)
            .controller("singleMachinePage", singleMachinePageC)
            .controller("maintenance",maintenanceCtrl)
            .controller("notifCrtl", notifCrtl)
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

    function changePasswordFormCrtl($scope, $http, request){


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

            $scope.confirming_stop_data = null;

            $scope.confirmingStopCancelled = function() { 
                $scope.confirming_stop_data = null;
            };

            $scope.confirmingStopDone = function() { 
                $scope.action($scope.confirming_stop_data.machine, $scope.confirming_stop_data.action, true);
                $scope.confirming_stop_data = null;
            };

            $scope.checkMaxMachines = function(action,machine) {
              $http.get('/execution_machines_limit')
                .then(function(data) {
                    if ((data.data.can_start_many) || (data.data.running_domains.indexOf(machine.id) >= 0) || (data.data.start_limit > data.data.running_domains.length)) {
                        $scope.action(machine, action, true);
                    }
                    else {
                        $scope.confirming_stop_data = { action: action, machine: machine };
                    }
                }, function(data,status) {
                      console.error('Repos error', status, data);
                      window.location.reload();
                });
            };

            $scope.action = function(machine, action, confirmed) {
                machine.action = false;
                if (action == 'start') {
                    if ((! confirmed) && (! machine.is_active)) {
                        $scope.checkMaxMachines(action, machine); 
                    } else {
                        window.location.assign('/machine/clone/' + machine.id + '.html');
                    }                    
                } else if ( action == 'restore' ) {
                    $scope.host_restore = machine.id_clone;
                    $scope.host_shutdown = 0;
                    $scope.host_force_shutdown = 0;
                } else if (action == 'shutdown' || action == 'hibernate' || action == 'force_shutdown') {
                    $scope.host_restore = 0;
                    $http.get( '/machine/'+action+'/'+machine.id_clone+'.json');
                } else {
                    alert("unknown action "+action);
                }

            };
            var ws_connected = false;
            $timeout(function() {
                if (typeof $scope.public_bases === 'undefined') $scope.public_bases = 0;
                if (!ws_connected) {
                    $scope.ws_fail = true;
                }
            }, 60 * 1000 );

            var subscribe_list_machines_user = function(url) {
                $scope.machines = [];
                var channel = 'list_machines_user_including_privates';
                if ($scope.anonymous) {
                    channel = 'list_bases_anonymous';
                }
                var ws = new WebSocket(url);
                ws.onopen = function(event) {
                    $scope.ws_fail = false;
                    ws_connected = true;
                    ws.send(channel);
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

            var subscribe_ping_backend= function(url) {
                var ws = new WebSocket(url);
                ws.onopen = function(event) { ws.send('ping_backend') };
                ws.onmessage = function(event) {
                    var data = JSON.parse(event.data);
                    $scope.$apply(function () {
                        $scope.pingbe_fail = !data;
                    });
                }
            };

            var subscribe_list_bookings = function(url) {
                var ws = new WebSocket(url);
                ws.onopen = function(event) { ws.send('list_next_bookings_today') };
                ws.onmessage = function(event) {
                    var data = JSON.parse(event.data);
                    $scope.$apply(function () {
                        $scope.bookings_today = data;
                    });
                }

            }

            $scope.subscribe_ws = function(url, enabled_bookings) {
                subscribe_list_machines_user(url);
                if (enabled_bookings) {
                    subscribe_list_bookings(url);
                }
            };
            $scope.only_public = false;
            $scope.toggle_only_public=function() {
                    $scope.only_public = !$scope.only_public;
            };
            $scope.startIntro = startIntro;
        };

        function singleMachinePageC($scope, $http, $interval, request, $location) {
            $scope.timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
            $scope.exec_time_start = new Date();
            $scope.exec_time = new Date();
            $scope.edit = "";
            $scope.lock_info = false;
            $scope.topology = false;

            $scope.getUnixTimeFromDate = function(date) {
                date = (date instanceof Date) ? date : date ? new Date(date) : new Date();
                return date.getTime() / 1000;
            };

            $scope.isPastTime = function(date, now_date) {
                return $scope.getUnixTimeFromDate(date) < $scope.getUnixTimeFromDate(now_date ? now_date : new Date());
            };

            $scope.set_edit=function(name,index) {
                if(!name) {
                    $scope.edit = '';
                } else {
                    $scope.edit = name+index;
                    $scope.lock_info = true;
                }
            };
            $scope.toggle_edit=function(name,index) {
                if(!name || $scope.edit == name+index) {
                    $scope.edit = '';
                } else {
                    $scope.edit = name+index;
                    $scope.lock_info = true;
                }
            };

            $scope.is_edit = function(name,index) {
                return $scope.edit == name+index;
            };

            $scope.topology_changed = function() {
                var cpu = $scope.showmachine.hardware.cpu[0];
                var item = cpu.cpu.topology;
                if(typeof(item) == undefined || !item) {
                    $scope.topology = false;
                    return;
                }
                cpu.vcpu['#text'] = item.dies
                    * item.sockets
                    * item.cores
                    * item.threads;

                $scope.topology = true;
            };

            var load_balance_options = function() {
                $http.get("/balance_options.json")
                    .then(function(response) {
                        $scope.balance_options = response.data;
                    });
            };

            var get_node_info = function(id) {
                $http.get("/node/info/"+id+".json")
                    .then(function(response) {
                        $scope.node = response.data;
                    });
            };

            var subscribed_extra = false;
            var subscribe_machine_info= function(url) {
                var ws = new WebSocket(url);
                ws.onopen = function(event) { ws.send('machine_info/'+$scope.showmachineId) };
                ws.onmessage = function(event) {
                    var data = JSON.parse(event.data);
                    if (data === null || typeof(data) == undefined ) {
                        ws.close();
                        window.location.href="/";
                        return;
                    }
                    $scope.$apply(function () {
                        if ($scope.lock_info) {
                            $scope.showmachine.requests = data.requests;
                            return;
                        }
                        $scope.hardware = Object.keys(data.hardware);
                        $scope.hardware.sort(function(a,b) {
                            if( a == 'features' && b != 'cpu') return -1;
                            if( b == 'features' && b != 'cpu') return 1;
                            if( a == 'memory' && b != 'cpu') return -1;
                            if( b == 'memory' && b != 'cpu') return 1;
                            return a >b;
                        });
                        $scope.showmachine = data;
                        $scope.hardware_add = [];
                        for ( var n_key=0 ; n_key< $scope.hardware.length; n_key++) {

                            var item = $scope.hardware[n_key];
                            if (item != 'cpu' && item != 'features'
                                && item != 'memory'
                        && !($scope.showmachine.is_base && item == 'disk')
                            ) {
                                $scope.hardware_add.push(item);
                            }
                        }
                        $scope.copy_is_volatile = $scope.showmachine.is_volatile;
                        if (!subscribed_extra) {
                            subscribed_extra = true;
                            subscribe_nodes(url,data.type);
                            //subscribe_bases(url);
                        }
                        if ($scope.edit) { $scope.lock_info = true }
                        $scope.topology_changed();
                    });
                    _select_new_base();
                }
            };

            $scope.getQueryStringFromObject = function(object) {
              var string = '';
              if (object) {
                var separator = '';
                for (var key in object) {
                  string += separator + key + '=' + escape(object[key]);
                  separator = '&';
                }
              }
              return string;
            };

            $scope.action = function(target,action,machineId,params){
              if (action === 'view-new-tab') {
                  window.open('/machine/view/' + machineId + '.html');
              }
              else if (action === 'view') {
                  window.location.assign('/machine/view/' + machineId + '.html');
              }
              else {
                  $http.get('/'+target+'/'+action+'/'+machineId+'.json'+'?'+this.getQueryStringFromObject(params))
                    .then(function() {
                    }, function(data,status) {
                          console.error('Repos error', status, data);
                          window.location.reload();
                    });
              }
            };

            var subscribe_requests = function(url) {
                var ws = new WebSocket(url);
                ws.onopen = function(event) { ws.send('list_requests') };
                ws.onmessage = function(event) {
                    var data = JSON.parse(event.data);
                    $scope.$apply(function () {
                        $scope.alerts_ws = data;
                    });
                }
            };

            var subscribe_isos = function(url) {
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
            var subscribe_nodes = function(url, type) {
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
            var _select_new_base = function() {
                if(typeof($scope.new_base) != 'undefined'
                    || typeof($scope.showmachine) == 'undefined'
                    || typeof($scope.bases) == 'undefined'
                ) {
                    return;
                }
                for (var i = 0; i < $scope.bases.length; i++) {
                    if ($scope.bases[i].id == $scope.showmachine.id_base) {
                        $scope.new_base = $scope.bases[i];
                    } else if ($scope.showmachine.is_base
                        && $scope.bases[i].id == $scope.showmachine.id) {
                        $scope.new_base = $scope.bases[i];
                    }
                }
                $scope.current_base = $scope.new_base;
            };

            var subscribe_bases = function(url, type) {
                var ws = new WebSocket(url);
                ws.onopen = function(event) { ws.send('list_bases') };
                ws.onmessage = function(event) {
                    var data = JSON.parse(event.data);
                    $scope.$apply(function () {
                        $scope.bases = data;
                        _select_new_base();
                    });
                }
            };

            var subscribe_ws = function(url, is_admin) {
                subscribe_machine_info(url);
                subscribe_bases(url);
                subscribe_requests(url);
                subscribe_isos(url);
                // other data will be subscribed on loading machine info
            };

          var url_ws;
          $scope.init = function(id, url,is_admin) {
                url_ws = url;
                $scope.showmachineId=id;
                $scope.tab_access=['group']
                $scope.client_attributes = [ 'User-Agent'
                   , 'Accept', 'Connection', 'Accept-Language', 'DNT', 'Host'
                   , 'Accept-Encoding', 'Cache-Control', 'X-Forwarded-For'
                ];

                subscribe_ws(url_ws, is_admin);
                $http.get('/machine/info/'+$scope.showmachineId+'.json')
                    .then(function(response) {
                            $scope.showmachine=response.data;
                            if (typeof $scope.new_name == 'undefined' ) {
                                $scope.new_name=$scope.showmachine.alias+"-2";
                                $scope.validate_new_name($scope.showmachine.alias);
                                $scope.new_n_virt_cpu= $scope.showmachine.n_virt_cpu;
                                $scope.new_memory = ($scope.showmachine.memory / 1024);
                                $scope.new_max_mem = ($scope.showmachine.max_mem / 1024);

                                $scope.new_run_timeout = ($scope.showmachine.run_timeout / 60);
                                if (!$scope.new_run_timeout) $scope.new_run_timeout = undefined;

                                $scope.new_volatile_clones = $scope.showmachine.volatile_clones;
                                $scope.new_autostart = $scope.showmachine.autostart;
                                $scope.new_shutdown_disconnected
                                    = $scope.showmachine.shutdown_disconnected;
                                $scope.new_balance_policy=$scope.showmachine.balance_policy;
                                $scope.new_auto_compact
                                    = $scope.showmachine.auto_compact;
                                load_balance_options();
                                get_node_info($scope.showmachine.id_vm);
                            }
                            if (is_admin) {
                                $scope.init_domain_access();
                                $scope.init_ldap_access();
                                $scope.list_ldap_attributes();
                                list_interfaces();
                                list_users();
                                list_host_devices();
                                list_access_groups();
                            }
                            $scope.copy_ram = $scope.showmachine.max_mem / 1024 / 1024;
                });
                if (is_admin ) {
                    $scope.list_ldap_attributes();
                    list_ldap_groups();
                }
                $scope.list_cpu_models();
          };

          var list_interfaces = function() {
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

          var subscribe_request = function(id_request, action) {
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

            var value_text = value;
            if (field == 'balance_policy')
                value_text = "'"+$scope.balance_options[value].name+"'";

            $http.post("/machine/set/"
                      , JSON.stringify({
                          'id': $scope.showmachine.id
                          ,'field': field
                          ,'value': value
                          ,'value_text': value_text
                      })
            );
          };
          $scope.set_public = function(machineId, value) {
            if (value) value=1;
            else value=0;
            $http.get("/machine/public/"+machineId+"/"+value);
          };
          $scope.set_base= function(vmId,machineId, value) {
            var url = 'set_base_vm';
            if (value == 0 || !value) {
                url = 'remove_base_vm';
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
                          ,'new_owner': $scope.copy_owner
                          ,'copy_is_volatile': $scope.copy_is_volatile
                          ,'copy_is_pool': $scope.copy_is_pool
                      })
              ).then(function(response) {
                  // if there are many , we pick the last one
                  var id_request = response.data.request;
                  subscribe_request(id_request, function(data) {
                    $scope.$apply(function () {
                        $scope.copy_request=data;
                    });
                  });
              });
          };

          //On load code
//          $scope.showmachineId = window.location.pathname.split("/")[3].split(".")[0] || -1 ;
            var new_hw={
                'network': {'driver': 'virtio', 'type': 'NAT' }
                ,'disk': {
                    'device': 'disk'
                    ,'bus': 'virtio'
                    ,'type': 'sys'
                    ,'capacity': '20G'
                    ,'allocation': '1G'
                    ,'driver': { 'cache': 'writeback' }
                }
            };
            $scope.pre_add_hw=function() {
                if (typeof(new_hw[$scope.new_hardware]) == 'undefined') {
                    new_hw[$scope.new_hardware] = {};
                }
                $scope.item = new_hw[$scope.new_hardware];
            }
            $scope.add_hardware = function(hardware) {
                var extra=new_hw[hardware];
                if ( hardware == 'disk') {
                    if ( extra.device == 'cdrom') {
                        extra.bus = 'sata';
                    } else {
                        extra.file= '';
                    }
                }

                $scope.new_hardware = undefined;

                $scope.request('add_hardware'
                      , { 'id_domain': $scope.showmachine.id
                            ,'name': hardware
                            ,'data': extra
                      })
            };
          $scope.remove_hardware = function(hardware, index ) {
            $scope.remove_item=undefined;
            if (hardware == 'disk') {
                var file = $scope.showmachine.hardware.disk[index].file;
                if (typeof(file) != 'undefined' && file) {
                    $scope.request('remove_hardware'
                        ,{
                            'id_domain': $scope.showmachine.id
                            ,'name': 'disk'
                            ,'option': { 'source/file': file }
                    });
                    return;
                }

            }
            $scope.request('remove_hardware',{
                    'id_domain': $scope.showmachine.id
                     ,'name': hardware
                     ,'index': index
            });
          };
          $scope.list_ldap_attributes= function() {
              $scope.ldap_entries = 0;
              $scope.ldap_verified = 0;
              if ($scope.cn) {
                  $http.get('/list_ldap_attributes/'+$scope.cn).then(function(response) {
                      $scope.ldap_error = response.data.error;
                      $scope.ldap_attributes = response.data.attributes;
                  });
              }
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
            $scope.set_defaults=function(hardware,index) {
                var hw2 = hardware.replace(/\d+(.*)/,'$1');
                $scope.request('change_hardware',
                    {'id_domain': $scope.showmachine.id
                        ,'hardware': hw2
                        ,'index': index
                    }
                );
                $scope.lock_info = false;
                if (hw2 == 'video') $scope.edit=false;

            };
            $scope.change_hardware= function(item,hardware,index) {
                var new_settings = JSON.parse(JSON.stringify($scope.showmachine.hardware[hardware][index]));
                if($scope.showmachine.is_base) {
                    new_settings.capacity=undefined;
                }
                if (hardware=='memory') {
                    new_settings.memory *= 1024;
                    new_settings.max_mem *= 1024;
                }
                $scope.request('change_hardware',
                    {'id_domain': $scope.showmachine.id
                        ,'hardware': hardware
                        ,'index': index
                        ,'data': new_settings
                    }
                );
                $scope.lock_info = false;
                if (hardware == 'video') $scope.edit=false;
            }
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
            var list_users= function() {
                $http.get('/list_users.json')
                    .then(function(response) {
                        $scope.list_users=response.data;
                        for (var i = 0; i < response.data.length; i++) {
                            if (response.data[i].id == $scope.showmachine.id_owner) {
                                $scope.copy_owner = response.data[i].id;
                                $scope.new_owner = response.data[i];
                            }
                        }
                    });
            }
            var list_ldap_groups = function() {
                $http.get('/list_ldap_groups')
                    .then(function(response) {
                        $scope.ldap_groups=response.data;
                    });
            };

            /* Host Devices */
            var list_host_devices = function() {
                $http.get('/list_host_devices/'+$scope.showmachine.id_vm)
                    .then(function(response) {
                        for ( var i=0;i<response.data.length; i++ ) {
                            response.data[i].is_attached
                                = _host_device_in_machine(response.data[i].id);
                        }
                        $scope.host_devices=response.data;
                    });
            };

            var _host_device_in_machine = function(id_hd) {
                for ( var i=0;i<$scope.showmachine.host_devices.length; i++ ) {
                    var hd = $scope.showmachine.host_devices[i];
                    console.log(hd.id+ " "+id_hd);
                    if (hd.id_host_device == id_hd) {
                        return true;
                    }
                }
                return false;
            };

            $scope.toggle_host_device = function(id_hd) {
                if (_host_device_in_machine(id_hd)) {
                    $scope.request('remove_host_device',
                        {id_domain: $scope.showmachine.id
                        ,id_host_device: id_hd});
                } else {
                    $http.get('/machine/host_device/add/'+$scope.showmachine.id
                        +"/"+id_hd).then(function(response) {
                            $scope.error = response.data.error;
                    });
                }
            };
            /* End Host Devices */

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
                        });
                    });
                });
            };

            $scope.request = function(request, args) {
                $scope.showmachine.requests++;
                $scope.pending_request = undefined;
                $http.post('/request/'+request+'/'
                    ,JSON.stringify(args)
                ).then(function(response) {
                    if (typeof(response) == null || response.status == 401 || response.status == 403 ) {
                        window.location.href="/logout";
                    }
                    if (! response.data.request ) {
                        $scope.pending_request = {
                            'status': 'done'
                            ,'error': response.data.error
                        };
                        return;
                    }
                    var id_request = response.data.request;
                    subscribe_request(id_request, function(data) {
                        $scope.$apply(function () {
                            $scope.pending_request=data;
                        });
                    });
                });
            };

            var list_access_groups = function() {
                $http.get("/machine/list_access_groups/"+$scope.showmachine.id).then(function(response) {
                    $scope.access_groups=response.data;
                });
            };
            $scope.add_group_access = function(group) {
                $http.get("/machine/add_access_group/"+$scope.showmachine.id+"/"+group)
                    .then(function(response) {
                        list_access_groups();
                });
            };

            $scope.remove_group_access = function(group) {
                $http.get("/machine/remove_access_group/"+$scope.showmachine.id+"/"+group)
                    .then(function(response) {
                        list_access_groups();
                });
            };

            $scope.list_cpu_models = function() {
                $http.get("/list_cpu_models.json?id_domain="
                +$scope.showmachineId).then(function(response) {
                    $scope.cpu_models=response.data;
                });
            };

            $scope.reboot = function() {
                $http.get("/machine/stop_start/"+$scope.showmachine.id+".json")
                .then(function(response) {
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

            $scope.new_base = undefined;
            $scope.list_ldap_attributes();
            $scope.list_caches = ['default','none','writethrough'
                ,'writeback','directsync','unsafe'];
            $scope.list_ios = ['default', 'native', 'threads'];

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
        var already_subscribed_to_domain = false;
        var already_refreshed_ports = false;
        $scope.count_start = 0;
        $scope.copy_password= function(driver) {
            $scope.view_password=1;
            var copyTextarea = document.querySelector('.js-copytextarea-'+driver);
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
        $scope.subscribe_request= function(url, id_request) {
            already_subscribed_to_domain = false;
            var ws = new WebSocket(url);
            ws.onopen = function(event) { ws.send('request/'+id_request) };

            ws.onmessage = function(event) {
                var data = JSON.parse(event.data);
                $scope.$apply(function () {
                    $scope.request = data;
                });
                if ( data.id_domain && ! already_subscribed_to_domain ) {
                    already_subscribed_to_domain = true;
                    $scope.id_domain=data.id_domain;
                    $scope.subscribe_domain_info(url, data.id_domain);
                }
            }
        }
        $scope.refresh_ports = function(url, id_domain ) {
            var id_request = $scope.request.id;
            $http.post('/request/open_exposed_ports/'
                ,JSON.stringify(
                    { 'id_domain': id_domain
                        ,'after_request': id_request
                        ,'retry': 20
                    })
            ).then(function(response) {
                if (response.data.request) {
                    id_request = response.data.request;
                }
                $http.post('/request/refresh_machine_ports/'
                    ,JSON.stringify(
                    { 'id_domain': id_domain
                        ,'after_request': id_request
                        ,'retry': 20
                    })
                    ).then(function(response) {
                        $scope.request_open_ports = true;
                    });
            });
        }
        $scope.subscribe_domain_info= function(url, id_domain) {
            already_subscribed_to_domain = true;
            var ws = new WebSocket(url);
            ws.onopen = function(event) { ws.send('machine_info/'+id_domain) };
            ws.onmessage = function(event) {
                var data = JSON.parse(event.data);
                $scope.$apply(function () {
                    if ($scope.edit) {
                        return;
                    }
                    if (data.is_base) {
                        already_subscribed_to_domain = false;
                        $scope.count_start = 0;
                        return;
                    } else if(!already_refreshed_ports) {
                        if(data.ports && data.ports.length) {
                            $scope.refresh_ports(url, data.id);
                        }
                        already_refreshed_ports = true;
                    }
                    $scope.count_start++;
                    $scope.domain = data;
                    for ( var i=0;i<$scope.domain.hardware.display.length; i++ ) {
                        if (typeof($scope.domain_display[i]) == 'undefined') {
                            $scope.domain_display[i]= {};
                        }
                        var display = $scope.domain.hardware.display[i];
                        if (display.driver.substr(-4,4) != '-tls'
                        && typeof(display.port) != 'undefined' && display.port) {
                            display.display=display.driver+"://"+display.ip+":"+display.port;
                        }
                        var keys = Object.keys(display);
                        for ( var n_key=0 ; n_key<keys.length ; n_key++) {
                            var field=keys[n_key];
                            if (typeof($scope.domain_display[i][field]) == 'undefined'
                                || $scope.domain_display[i][field] != display[field]) {
                                $scope.domain_display[i][field] = display[field];
                            }
                        }
                    }
                });
                if ($scope.request_open_ports && $scope.domain && $scope.domain.ip && $scope.domain.requests == 0) {
                    $scope.request_open_ports_done = true;
                }

                if ($scope.domain && $scope.domain.is_active && $scope.request.status == 'done' && $scope.domain.requests == 0 && (!$scope.open_ports || $scope.request_open_ports_done) && $scope.redirect_time--<0) {
                    $scope.redirect();
                    if ($scope.auto_view && !redirected_display && $scope.domain_display[0]
                        && $scope.domain_display[0].file_extension
                        && $scope.domain.ports.length==0
                        && !$scope.domain_display[0].password) {
                        location.href='/machine/display/'+$scope.domain_display[0].driver+"/"
                            +$scope.domain.id+"."+$scope.domain_display[0].file_extension;
                        redirected_display=true;
                    }
                }
            }
        }

        $scope.reload_ports = function() {
            $scope.request_open_ports_done = false;
            $scope.redirect_time=2;
            $scope.domain.requests=-1;
            $http.post('/request/close_exposed_ports/'
                ,JSON.stringify(
                    { 'id_domain': $scope.domain.id})
            ).then(function(response) {
                var id_request = 0;
                if (response.data.request) {
                    id_request = response.data.request;
                }
                $http.post('/request/open_exposed_ports/'
                    ,JSON.stringify(
                    { 'id_domain': $scope.domain.id
                        ,'after_request': id_request
                        ,'_force': 1
                        ,'retry': 20
                    })
                    ).then(function(response) {
                        $scope.request_open_ports = true;
                        $scope.request_open_ports_done = false;
                    });
            });
        }

        $scope.domain_display = [];
        $scope.redirect_done = false;
        //$scope.wait_request();
        $scope.view_clicked=false;
        $scope.redirect_time = 1;
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
                ).then function(response) {
                    $scope.conflicts = response.data
            })
        };

        $http.get('/list_ldap_groups/')
                    .then(function(response) {
                        $scope.ldap_groups=response.data;
        });
        $http.get('/list_bases.json')
                    .then(function(response) {
                         $scope.bases=response.data;
        });

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
