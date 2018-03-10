

    var ravadaApp = angular.module("ravada.app",['ngResource','ngSanitize'])
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
            .controller("notifCrtl", notifCrtl)
            .controller("run_domain",run_domain_ctrl)



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
        function mainpageCrtl($scope, $http, request, listMach) {
            $scope.set_restore=function(machineId) {
                $scope.host_restore = machineId;
            };
            $scope.restore= function(machineId){
                var toGet = '/machine/remove/'+machineId+'.html?sure=yes';
                $http.get(toGet);
                setTimeout(function(){ }, 2000);
                window.location.reload();
            };
            $scope.action = function(machineId) {
//                alert(machineId+" - "+$scope.host_action);
                if ( $scope.host_action.indexOf('restore') !== -1 ) {
                    $scope.host_restore = machineId;
                    $scope.host_shutdown = 0;
                } else if ($scope.host_action.indexOf('shutdown') !== -1) {
                    $scope.host_shutdown = machineId;
                    $scope.host_restore = 0;
                    $http.get( '/machine/shutdown/'+machineId+'.json');
                    window.location.reload();
                }  else if ($scope.host_action.indexOf('hybernate') !== -1) {
                    $scope.host_hybernate = machineId;
                    $scope.host_restore = 0;
                    $http.get( '/machine/hybernate/'+machineId+'.json');
                    window.location.reload();
                } 

            };

            $url_list = "/list_bases.json";
            if ( typeof $_anonymous !== 'undefined' && $_anonymous ) {
                $url_list = "/list_bases_anonymous.json";
            }
            $http.get($url_list).then(function(response) {
                    $scope.list_bases= response.data;
            });

            $http.get('/pingbackend.json').then(function(response) {
                $scope.pingbe_fail = !response.data;

            });
            
            $scope.only_public = false;
            $scope.toggle_only_public=function() {
                    $scope.only_public = !$scope.only_public;
            };
            $scope.startIntro = startIntro;
        };

        function singleMachinePageC($scope, $http, $interval, request, $location) {
          $scope.domain_remove = 0;
          $scope.new_name_invalid = false;
          $http.get('/pingbackend.json').then(function(response) {
            $scope.pingbe_fail = !response.data;
          });
/*          $scope.getSingleMachine = function(){
            $http.get("/list_machines.json").then(function(response) {
              for (var i=0, iLength=response.data.length; i<iLength; i++) {
                if (response.data[i].id == $scope.showmachineId) {
                  $scope.showmachine = response.data[i];
                  if (!$scope.new_name) {
                    $scope.new_name =   $scope.showmachine.name;
                  }
                return;
                }
              }
              window.location.href = "/admin/machines";
            });
          };
            */
          $scope.remove = function(machineId) {
            $http.get('/machine/remove/'+machineId+'.json');
          };
          $scope.remove_clones = function(machineId) {
                $http.get('/machine/remove_clones/'+machineId+'.json');
          };

          $scope.reload_page_msg = false;
          $scope.fail_page_msg = false;
          $scope.screenshot = function(machineId, isActive){
              if (isActive) {
                  $http.get('/machine/screenshot/'+machineId+'.json');
                  $scope.fail_page_msg = false;
                  $scope.reload_page_msg = true;
                  setTimeout(function () {
                      window.location.reload(false);
                  }, 5000);
              }
              else {
                  $scope.reload_page_msg = false;
                  $scope.fail_page_msg = true;
              }
          };
          
          $scope.reload_page_copy_msg = false;
          $scope.fail_page_copy_msg = false;
          $scope.copy_done = false;
          $scope.copy_screenshot = function(machineId, fileScreenshot){
              if (fileScreenshot != '') {
                $http.get('/machine/copy_screenshot/'+machineId+'.json');
                $scope.fail_page_copy_msg = false;
                $scope.reload_page_copy_msg = true;
                setTimeout(function () {
                    $scope.reload_page_copy_msg = false;
                }, 2000);
              }
              else {
                  $scope.reload_page_copy_msg = false;
                  $scope.fail_page_copy_msg = true;
              }
          };

          $scope.rename = function(machineId, old_name) {
            if ($scope.new_name_duplicated || $scope.new_name_invalid) return;
            $scope.rename_requested=1;
            $http.get('/machine/rename/'+machineId+'/'
            +$scope.new_name);
            $scope.message_rename = 1;
            //   TODO check previous rename returned ok
            window.location.href = "/admin/machines";
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
          $scope.set_public = function(machineId, value) {
            $http.get("/machine/public/"+machineId+"/"+value);
          };
          
          //On load code
          $scope.showmachineId = window.location.pathname.split("/")[3].split(".")[0] || -1 ;
          $http.get('/machine/info/'+$scope.showmachineId+'.json').then(function(response) {
              $scope.showmachine=response.data;
          });
//          $scope.getSingleMachine();
//          $scope.updatePromise = $interval($scope.getSingleMachine,3000);
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
                    copyTextarea.select();
                    try {
                        var successful = document.execCommand('copy');
                        var msg = successful ? 'successful' : 'unsuccessful';
                        console.log('Copying text command was ' + msg);
                    } catch (err) {
                        console.log('Oops, unable to copy');
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
