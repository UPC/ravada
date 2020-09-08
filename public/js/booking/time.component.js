'use strict';

export default {
    bindings: {
        label: "@"
    },
    require: {
        ngModel: '^ngModel'
    },
    templateUrl: '/js/booking/time.component.html',
    controller: timeCtrl,
};
timeCtrl.$inject = ["$element","$scope"]
function timeCtrl($element, $scope) {
    const self = this;
    self.$postLink = () => {
        $element.find(".clockpicker").clockpicker();
    };
    self.$onInit = () => {
        this.ngModel.$render = () => {
            self.model = self.ngModel.$viewValue;
        };
        $scope.$watch(function() { return self.model; }, function(value) {
            self.ngModel.$setViewValue(value);
        });
    };
}
