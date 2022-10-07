'use strict';

export default {
    require: {
        ngModel: '^ngModel',
    },
    bindings: {
        editable: '<',
        onAdd: '&',
        onDelete: '&'
    },
    templateUrl: '/booking/ldapGroup.component.html',
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
        self.ngModel.$render = () => {
            self.selected_groups = self.ngModel.$viewValue;
        };
        $scope.$watchCollection( () => self.selected_groups, value => {
            self.ngModel.$setViewValue(value);
            self.required = Object.prototype.hasOwnProperty.call(self.ngModel.$validators,"required");
            if (self.required) self.ngModel.$setValidity("required",!!value.length);
        });
        self.getGroups()
    };
    self.getGroups = async qry => await apiLDAP.list_groups({ qry }).$promise

    self.add_ldap_group = () => {
        if (!self.group_selected) return;
        if (self.selected_groups.indexOf(self.group_selected) >= 0) {
            msgError(self.group_selected + ' already there');
        } else {
            self.selected_groups.push(self.group_selected);
        }
        self.onAdd({ group: self.group_selected})
        self.group_selected = null;
    };
    self.remove_ldap_group =  group => {
        self.selected_groups = remove_array_element(self.selected_groups,group)
        self.onDelete({ group })
    }

}
