'use strict';

export default {
    require: {
        ngModel: '^ngModel',
    },
    bindings: {
        editable: '<'
    },
    templateUrl: '/js/booking/ldapGroup.component.html',
    controller: grpCtrl
}
grpCtrl.$inject = ["apiLDAP","$scope","$timeout"];

function grpCtrl(apiLDAP, $scope, $timeout) {
    const self = this;
    const remove_array_element = (arr,el) => arr.filter(e => e !== el);
    const msgError = msg => { self.err = msg; $timeout(() => self.err=null,2000)};
    self.available_groups = [];
    self.group_selected = null;
    self.$onInit = () => {
        this.ngModel.$render = () => {
            self.selected_groups = self.ngModel.$viewValue;
        };
        $scope.$watch(function() { return self.selected_groups; }, function(value) {
            self.ngModel.$setViewValue(value);
        });
        apiLDAP.list_groups({}, res => self.available_groups = res)

    };
    self.add_ldap_group = () => {
        if (self.selected_groups.indexOf(self.group_selected) >= 0) {
            msgError(self.selected_groups + ' already there');
        } else {
            self.selected_groups.push(self.group_selected);
        }
        self.group_selected = null;
    };
    self.remove_ldap_group =  group => self.selected_groups = remove_array_element(self.selected_groups,group);

}
