
ravadaApp.directive("solShowAdminNavigation", swAdminNavigation)
        .directive("solShowAdminContent", swAdminContent)
        .controller("adminPage", adminPageC)

    function swAdminNavigation() {

        return {
            restrict: "E",
            templateUrl: '/templates/admin_nav.html',
        };

    };

    function swAdminContent() {

        return {
            restrict: "E",
            templateUrl: '/templates/admin_cont.html',
        };

    };

  function adminPageC($scope, $http, request, listMach) {
    $scope.showing = 'machines';
    $scope.showMachines = function(){
      $scope.showing = 'machines';
    }
    $scope.showUsers = function(){
      $scope.showing = 'users';
    }
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

    $scope.rename= {new_name: 'new_name'};
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
