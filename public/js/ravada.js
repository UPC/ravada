

    angular.module("ravada.app",['ngResource','ngSanitize'])
            .directive("solShowSupportform", swSupForm)
            .directive("solShowNewmachine", swNewMach)
            .directive("solShowListmachines", swListMach)
	    .directive("solShowListusers", swListUsers)
            .directive("solShowCardsmachines", swCardsMach)
            .directive("solShowMachinesNotifications", swMachNotif)
            .directive("solShowMessages", swMess)
            .service("request", gtRequest)
            .service("listMach", gtListMach)
            .service("listMess", gtListMess)
	    .service("listUsers", gtListUsers)
            .controller("new_machine", newMachineCtrl)
            .controller("SupportForm", suppFormCtrl)
            .controller("machines", machinesCrtl)
            .controller("bases", mainpageCrtl)
            .controller("messages", messagesCrtl)
            .controller("users", usersCrtl)
            .controller("notifCrtl", notifCrtl)




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
            templateUrl: '/templates/support_form.html',
        };

    };

    function swNewMach() {

        return {
            restrict: "E",
            templateUrl: '/templates/new_machine.html',
        };

    };

// list machines
    function machinesCrtl($scope, $http, request, listMach) {

        $scope.rename= {
            // why this line does nothing ?
            new_name: 'new_name'
        };
        $scope.show_rename = false;
        $scope.new_name_duplicated=false;
        $url_list = "/list_machines.json";
        if ( typeof $_anonymous !== 'undefined' && $_anonymous ) {
            $url_list = "/list_bases_anonymous.json";
        }
        $http.get($url_list).then(function(response) {
                $scope.list_machines= response.data;
        });

        $http.get('/pingbackend.json').then(function(response) {
            $scope.pingbe_fail = !response.data;

        });

        $scope.shutdown = function(machineId){
            var toGet = '/machine/shutdown/'+machineId+'.json';
            $http.get(toGet);
        };

        $scope.prepare = function(machineId){
            var toGet = '/machine/prepare/'+machineId+'.json';
            $http.get(toGet);
        };

        $scope.remove_base= function(machineId){
            var toGet = '/machine/remove_base/'+machineId+'.json';
            $http.get(toGet);
        };

        $scope.screenshot = function(machineId){
            var toGet = '/machine/screenshot/'+machineId+'.json';
            $http.get(toGet);
        };

        $scope.pause = function(machineId){
            var toGet = '/machine/pause/'+machineId+'.json';
            $http.get(toGet);
        };

        $scope.resume = function(machineId){
            var toGet = '/machine/resume/'+machineId+'.json';
            $http.get(toGet);
        };

        $scope.start = function(machineId){
            var toGet = '/machine/start/'+machineId+'.json';
            $http.get(toGet);
        };

        $scope.removeb = function(machineId){
            var toGet = '/machine/remove_b/'+machineId+'.json';
            $http.get(toGet);
        };

        $scope.rename = function(machineId, old_name) {
            if (old_name == $scope.rename.new_name) {
                // why the next line does nothing ?
                $scope.show_rename= false;
                return;
            }
            $http.get('/machine/rename/'+machineId+'/'
                        +$scope.rename.new_name);
            alert('Rename machine '+old_name
                +' to '+$scope.rename.new_name
                +'. It may take some seconds to complete.');
            // why the next line does nothing ?
            $scope.show_rename= false;
        };

        $scope.validate_new_name = function(old_name) {
            if(old_name == $scope.rename.new_name) {
                $scope.new_name_duplicated=false;
                return;
            }
            $http.get('/machine/exists/'+$scope.rename.new_name)
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


    function swListMach() {

        return {
            restrict: "E",
            templateUrl: '/templates/list_machines.html',
        };

    };

    function swCardsMach() {

        $url =  '/templates/user_machines.html';
        if ( typeof $_anonymous !== 'undefined' && $_anonymous ) {
            $url =  '/templates/user_machines_anonymous.html';
        }

        return {
            restrict: "E",
            templateUrl: $url,
        };

    };

    function swMachNotif() {
        return {
            restrict: "E",
            templateUrl: '/templates/machines_notif.html',
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

// list users
    function usersCrtl($scope, $http, request, listUsers) {

        $http.get('/list_users.json').then(function(response) {
                $scope.list_users= response.data;
        });

        $scope.make_admin = function(id) {
            $http.get('/users/make_admin/' + id + '.json')
            location.reload();
        };

        $scope.remove_admin = function(id) {
            $http.get('/users/remove_admin/' + id + '.json')
            location.reload();
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
            templateUrl: '/templates/list_users.html',
        };

    };

    function gtListUsers($resource){

        return $resource('/list_users.json',{},{
            get:{isArray:true}
        });

    };


// list messages
    function messagesCrtl($scope, $http, request) {
        $http.get('/pingbackend.json').then(function(response) {
            $scope.pingbe_fail = !response.data;

        });

        $http.get('/messages.json').then(function(response) {
                $scope.list_message= response.data;
        });

        $scope.asRead = function(messId){
            var toGet = '/messages/read/'+messId+'.json';
            $http.get(toGet);
        };
        $http.get('/pingbackend.json').then(function(response) {
            $scope.pingbe = response.data;
        });
    };

    function swMess() {
        return {
            restrict: "E",
            templateUrl: '/templates/list_messages.html',
        };
    };

    function gtListMess($resource){

        return $resource('/messages.json',{},{
            get:{isArray:true}
        });

    };

    function notifCrtl($scope, $interval, $http, request){
      $scope.alerts = [
      ];

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
