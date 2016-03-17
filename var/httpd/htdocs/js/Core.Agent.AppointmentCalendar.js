// --
// Copyright (C) 2001-2016 OTRS AG, http://otrs.com/
// --
// This software comes with ABSOLUTELY NO WARRANTY. For details, see
// the enclosed file COPYING for license information (AGPL). If you
// did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
// --

"use strict";

var Core = Core || {};
Core.Agent = Core.Agent || {};

/**
 * @namespace Core.Agent.AppointmentCalendar
 * @memberof Core.Agent
 * @author OTRS AG
 * @description
 *      This namespace contains the appointment calendar functions.
 */
Core.Agent.AppointmentCalendar = (function (TargetNS) {

    /**
     * @name Init
     * @memberof Core.Agent.AppointmentCalendar
     * @function
     * @param {Object} Params - Hash with different config options.
     * @param {Array} Params.MonthNames - Array containing the localized strings for each month.
     * @param {Array} Params.MonthNamesShort - Array containing the localized strings for each month on shorth format.
     * @param {Array} Params.DayNames - Array containing the localized strings for each week day.
     * @param {Array} Params.DayNamesShort - Array containing the localized strings for each week day on short format.
     * @param {Array} Params.ButtonText - Array containing the localized strings for each week day on short format.
     * @param {String} Params.ButtonText.today - Localized string for the word "Today".
     * @param {String} Params.ButtonText.month - Localized string for the word "month".
     * @param {String} Params.ButtonText.week - Localized string for the word "week".
     * @param {String} Params.ButtonText.day - Localized string for the word "day".
     * @param {Array} Params.Events - Array of hashes including the data for each event.
     * @description
     *      Initializes the appointment calendar control.
     */
    TargetNS.Init = function (Params) {
        $('#calendar').fullCalendar({
            header: {
                left: 'yearly,month,agendaWeek,agendaDay timeline',
                center: 'title',
                right: 'today prev,next'
            },
            defaultView: 'timeline',
            allDayText: Params.AllDayText,
            isRTL: Params.IsRTL,
            columnFormat: 'ddd, D MMM',
            timeFormat: 'H:mm',
            slotLabelFormat: 'HH:mm',
            titleFormat: 'D MMM YYYY #W',
            businessHours: {
                start: '08:00',
                end: '18:00',
                dow: [ 1, 2, 3, 4, 5 ]
            },
            height: 600,
            editable: true,
            selectable: true,
            selectHelper: true,
            firstDay: Params.FirstDay,
            monthNames: Params.MonthNames,
            monthNamesShort: Params.MonthNamesShort,
            dayNames: Params.DayNames,
            dayNamesShort: Params.DayNamesShort,
            buttonText: Params.ButtonText,
            schedulerLicenseKey: 'GPL-My-Project-Is-Open-Source',
            slotDuration: '00:30:00',
            nowIndicator: true,
            views: {
                month: {
                    titleFormat: 'MMMM YYYY',
                    columnFormat: 'dddd'
                },
                agendaWeek: {
                    weekends: false
                },
                agendaDay: {
                    titleFormat: 'D MMM YYYY'
                },
                timeline: {
                    slotDuration: '02:00:00',
                    duration: {
                        days: 7
                    },
                    slotLabelFormat: [
                        'ddd, D MMM',
                        'HH'
                    ]
                }
            },
            select: function(Start, End, JSEvent, View, Resource) {
                var Data = {
                    Start: Start,
                    End: End,
                    JSEvent: JSEvent,
                    View: View,
                    Resource: Resource
                };
                OpenEditDialog(Params.CalendarID, Params.Callbacks.EditAction, Params.Callbacks.EditMaskSubaction, Params.DialogText, Data);
                // return true;
            },
            events: Params.Events,
            eventClick: function(CalEvent, JSEvent, View) {
                var Data = {
                    Start: CalEvent.start,
                    End: CalEvent.end,
                    CalEvent: CalEvent,
                    JSEvent: JSEvent,
                    View: View
                };
                OpenEditDialog(Params.CalendarID, Params.Callbacks.EditAction, Params.Callbacks.EditMaskSubaction, Params.DialogText, Data);
                return false;
            },
            eventDrop: function(CalEvent, Delta, RevertFunc, JSEvent, UI, View) {
                var Data = {
                    CalEvent: CalEvent,
                    Delta: Delta,
                    RevertFunc: RevertFunc,
                    JSEvent: JSEvent,
                    UI: UI,
                    View: View
                };
                UpdateAppointment(Params.CalendarID, Params.Callbacks.EditAction, Params.Callbacks.EditSubaction, Data);
                return false;
            },
            eventResize: function(CalEvent, Delta, RevertFunc, JSEvent, UI, View) {
                var Data = {
                    CalEvent: CalEvent,
                    Delta: Delta,
                    RevertFunc: RevertFunc,
                    JSEvent: JSEvent,
                    UI: UI,
                    View: View
                };
                UpdateAppointment(Params.CalendarID, Params.Callbacks.EditAction, Params.Callbacks.EditSubaction, Data);
                return false;
            }
        });
    };

    /**
     * @private
     * @name ShowWaitingDialog
     * @memberof Core.Agent.AppointmentCalendar
     * @function
     * @description
     *      Shows waiting dialog until dialog screen is ready.
     */
    function ShowWaitingDialog() {
        Core.UI.Dialog.ShowContentDialog('<div class="Spacing Center"><span class="AJAXLoader" title="' + Core.Config.Get('LoadingMsg') + '"></span></div>', Core.Config.Get('LoadingMsg'), '10px', 'Center', true);
    }

    /**
     * @private
     * @name OpenEditDialog
     * @memberof Core.Agent.AppointmentCalendar
     * @function
     * @param {Integer} CalendarID - ID of the calendar user is editing
     * @param {String} Action - Action which is used in framework right now.
     * @param {String} Subaction - Subaction which is used in framework right now.
     * @param {Object} DialogText - Hash with dialog text translations.
     * @param {Object} AppointmentData - Hash with appointment data.
     * @description
     *      This function open the add appointment dialog after selecting a time period.
     */
    function OpenEditDialog(CalendarID, Action, Subaction, DialogText, AppointmentData) {
        var Data;

        if (!Action) {
            Action = 'AgentAppointmentEdit';
        }

        if (!Subaction) {
            Subaction = 'AJAXMask';
        }

        Data = {
            CalendarID: CalendarID,
            Action: Action,
            Subaction: Subaction,
            AppointmentID: AppointmentData.CalEvent ? AppointmentData.CalEvent.id : null,
            Title: AppointmentData.CalEvent ? AppointmentData.CalEvent.title : null,
            Description: AppointmentData.CalEvent ? AppointmentData.CalEvent.Description : null,
            Location: AppointmentData.CalEvent ? AppointmentData.CalEvent.Location : null,
            StartYear: AppointmentData.Start.year(),
            StartMonth: AppointmentData.Start.month() + 1,
            StartDay: AppointmentData.Start.date(),
            StartHour: AppointmentData.Start.hour(),
            StartMinute: AppointmentData.Start.minute(),
            EndYear: AppointmentData.End.year(),
            EndMonth: AppointmentData.End.month() + 1,
            EndDay: AppointmentData.End.date(),
            EndHour: AppointmentData.End.hour(),
            EndMinute: AppointmentData.End.minute()
        };

        ShowWaitingDialog();

        Core.AJAX.FunctionCall(
            Core.Config.Get('CGIHandle'),
            Data,
            function (HTML) {

                // if the waiting dialog was cancelled, do not show the search
                // dialog as well
                if (!$('.Dialog:visible').length) {
                    return;
                }

                Core.UI.Dialog.ShowContentDialog(HTML, DialogText.EditTitle, '10px', 'Center', true, undefined, true);

                Core.UI.InputFields.Activate($('.Dialog:visible'));

            }, 'html'
        );
    }

    /**
     * @private
     * @name UpdateAppointment
     * @memberof Core.Agent.AppointmentCalendar
     * @function
     * @param {Integer} CalendarID - ID of the calendar user is editing
     * @param {String} Action - Action which is used in framework right now.
     * @param {String} Subaction - Subaction which is used in framework right now.
     * @param {Object} AppointmentData - Hash with appointment data.
     * @description
     *      This function updates the appointment with supplied data.
     */
    function UpdateAppointment(CalendarID, Action, Subaction, AppointmentData) {
        var Data;

        if (!Action) {
            Action = 'AgentAppointmentEdit';
        }

        if (!Subaction) {
            Subaction = 'EditAppointment';
        }

        Data = {
            CalendarID: CalendarID,
            Action: Action,
            Subaction: Subaction,
            AppointmentID: AppointmentData.CalEvent.id,
            Title: AppointmentData.CalEvent.title,
            Description: AppointmentData.CalEvent.Description,
            Location: AppointmentData.CalEvent.Location,
            StartYear: AppointmentData.CalEvent.start.year(),
            StartMonth: AppointmentData.CalEvent.start.month() + 1,
            StartDay: AppointmentData.CalEvent.start.date(),
            StartHour: AppointmentData.CalEvent.start.hour(),
            StartMinute: AppointmentData.CalEvent.start.minute(),
            EndYear: AppointmentData.CalEvent.end.year(),
            EndMonth: AppointmentData.CalEvent.end.month() + 1,
            EndDay: AppointmentData.CalEvent.end.date(),
            EndHour: AppointmentData.CalEvent.end.hour(),
            EndMinute: AppointmentData.CalEvent.end.minute()
        };

        Core.AJAX.FunctionCall(
            Core.Config.Get('CGIHandle'),
            Data,
            function (Response) {
                if (!Response.Success) {
                    AppointmentData.RevertFunc();
                }
            }
        );
    }

    return TargetNS;
}(Core.Agent.AppointmentCalendar || {}));