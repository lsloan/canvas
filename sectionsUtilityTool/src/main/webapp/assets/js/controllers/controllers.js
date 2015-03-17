'use strict';
/* global $,  angular, getTermArray, getCurrentTerm, errorDisplay */

var sectionsApp = angular.module('sectionsApp', ['sectionsFilters','ui.sortable']);

sectionsApp.run(function ($rootScope) {
  $rootScope.user = $.trim($('#uniqname').val());
});

function generateCurrentTimestamp(){
	return new Date().getTime();
};

/* TERMS CONTROLLER */
sectionsApp.controller('termsController', ['Courses', '$rootScope', '$scope', '$http', function (Courses, $rootScope, $scope, $http) {
  //void the currently selected term
  $scope.selectedTerm = null;
  //reset term scope
  $scope.terms = [];
  var termsUrl ='manager/api/v1/accounts/1/terms?per_page=4000&_=' + generateCurrentTimestamp();
  $http.get(termsUrl).success(function (data) {
    if(data.enrollment_terms){
      $scope.terms = data.enrollment_terms;
      $scope.$parent.currentTerm =  getCurrentTerm(data.enrollment_terms);
    }
    else {
      errorDisplay(termsUrl,status,'Unable to get terms data');  
    }
  }).error(function () {
    errorDisplay(termsUrl,status,'Unable to get terms data');
  });

  //user selects a term from the dropdown that has been 
  //populated by $scope.terms 
  $scope.getTerm = function (termId, termName, termCanvasId) {
    $scope.$parent.currentTerm.currentTermName = termName;
    $scope.$parent.currentTerm.currentTermId = termId;
    $scope.$parent.currentTerm.currentTermCanvasId = termCanvasId;
  };

}]);


//COURSES CONTROLLER
sectionsApp.controller('coursesController', ['Courses', 'Sections', '$rootScope', '$scope', function (Courses, Sections, $rootScope, $scope) {
  //$scope.courses = [];


 $scope.getCoursesForUniqname = function () {
    var uniqname = $.trim($('#uniqname').val());
    $scope.uniqname = uniqname;
    var mini='/manager/api/v1/courses?as_user_id=sis_login_id:' +uniqname+ '&include=sections&per_page=200&published=true&with_enrollments=true&enrollment_type=teacher&_='+ generateCurrentTimestamp();
    var url = '/sectionsUtilityTool'+mini;
    $scope.loading = true;
    Courses.getCourses(url).then(function (result) {
      if (result.data.errors) {
        if(uniqname) {
          $scope.errorMessage = result.data.errors + uniqname;
          $scope.errorLookup = true;
        }
        else {
          $scope.errorMessage = 'Please supply a uniqname at left.';
          $scope.instructions = false;
          $scope.errorLookup = false;
        }
        $scope.success = false;
        $scope.error = true;
        $scope.instructions = false;
        $scope.loading = false;
      }
      else {
        if(result.errors){
          $scope.success = false;
          $scope.error = true;
          $scope.instructions = false;
          $scope.loading = false;
        }
        else {
          $scope.courses = result.data;
          $scope.termArray = getTermArray(result.data);
          $scope.error = false;
          $scope.success = true;
          $scope.instructions = true;
          $scope.errorLookup = false;
          $scope.loading = false;
        }
      }
    });
  };

  $scope.sortableOptions = {
      placeholder: 'section',
      connectWith: '.sectionList',
      start: function(event, ui) {
        ui.item.addClass('grabbing');
      },
      receive: function(event, ui) {
      //on drop, append the name of the source course
        var prevMovEl = ui.item.find('.status');
        if(prevMovEl.text() !==''){
          prevMovEl.next('span').show();
        }
        if(ui.sender.closest('.course').find('.section').length ===1){
          ui.sender.closest('.course').addClass('onlyOneSection');
        }
        if(ui.sender.closest('.course').find('.section').length ===0){
          ui.sender.closest('.course').addClass('noSections');
        }
        prevMovEl.text('Moved  from ' + ui.sender.closest('.course').find('.courseLink').text());
        $('li.course').removeClass('activeCourse');
        ui.item.closest('li.course').addClass('activeCourse');
      },
      stop: function( event, ui ) {
        //add some animation feedback to the move
        ui.item.css('background-color', '#FFFF9C')
          .animate({ backgroundColor: '#FFFFFF'}, 1500);
        ui.item.removeClass('grabbing');
      }
  };
  

  /*User clicks on Get Sections and the sections for that course
  gets added to the course scope*/
  $scope.getSections = function () {

    $('.sectionList').sortable({
      connectWith: '.sectionList',
      receive: function(event, ui) {
        //on drop, append the name of the source course
        var prevMovEl = ui.item.find('.status');
        if(prevMovEl.text() !==''){
          prevMovEl.next('span').show();
        }
        prevMovEl.text('Moved  from ' + ui.sender.closest('.course').find('.courseLink').text());
      },
      stop: function( event, ui ) {
        //add some animation feedback to the move
        $('li.course').removeClass('activeCourse');
        ui.item.closest('li.course').addClass('activeCourse');
        ui.item.css('background-color', '#FFFF9C')
          .animate({ backgroundColor: '#FFFFFF'}, 1500);
      }
    }).disableSelection();
   };
}]);


