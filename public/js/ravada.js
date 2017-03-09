

    var ravadaApp = angular.module("ravada.app",['ngResource','ngSanitize'])
            .directive("solShowSupportform", swSupForm)
            .directive("solShowNewmachine", swNewMach)
            .directive("solShowListmachines", swListMach)
	    .directive("solShowListusers", swListUsers)
            .directive("solShowCardsmachines", swCardsMach)
            .directive("solShowMachinesNotifications", swMachNotif)
            .service("request", gtRequest)
            .service("listMach", gtListMach)
            .service("listMess", gtListMess)
	    .service("listUsers", gtListUsers)
            .controller("new_machine", newMachineCtrl)
            .controller("SupportForm", suppFormCtrl)
            .controller("bases", mainpageCrtl)


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

    function gtListMess($resource){

        return $resource('/messages.json',{},{
            get:{isArray:true}
        });

    };
