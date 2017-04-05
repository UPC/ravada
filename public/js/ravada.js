

    var ravadaApp = angular.module("ravada.app",['ngResource','ngSanitize'])
            .directive("solShowSupportform", swSupForm)
            .directive("solShowListmachines", swListMach)
	    .directive("solShowListusers", swListUsers)
            .directive("solShowCardsmachines", swCardsMach)
            .directive("solShowMachinesNotifications", swMachNotif)
            .service("request", gtRequest)
            .service("listMach", gtListMach)
            .service("listMess", gtListMess)
	    .service("listUsers", gtListUsers)
            .controller("SupportForm", suppFormCtrl)
            .controller("bases", mainpageCrtl)
            .controller("singleMachinePage", singleMachinePageC)
        .controller("notifCrtl", notifCrtl)

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

        };

        function singleMachinePageC($scope, $http, $interval, request, $location) {
          $scope.domain_remove = 0;
          $http.get('/pingbackend.json').then(function(response) {
            $scope.pingbe_fail = !response.data;
          });
          $scope.getSingleMachine = function(){
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
          $scope.remove = function(machineId) {
            $http.get('/machine/remove/'+machineId+'.json');
          };
          $scope.remove_clones = function(machineId) {
                $http.get('/machine/remove_clones/'+machineId+'.json');
          };

          $scope.action = function(target,action,machineId){
            $http.get('/'+target+'/'+action+'/'+machineId+'.json');
          };
          $scope.rename = function(machineId, old_name) {
            if ($scope.new_name_duplicated) return;
            $http.get('/machine/rename/'+machineId+'/'
            +$scope.new_name);
          };

          $scope.validate_new_name = function(old_name) {
            if(old_name == $scope.new_name) {
              $scope.new_name_duplicated=false;
              return;
            }
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
          $scope.getSingleMachine();
          $scope.updatePromise = $interval($scope.getSingleMachine,3000);
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

    function swListUsers() {

        return {
            restrict: "E",
            templateUrl: '/ng-templates/list_users.html',
        };

    };

    function gtListUsers($resource){

        return $resource('/list_users.json',{},{
            get:{isArray:true}
        });

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
