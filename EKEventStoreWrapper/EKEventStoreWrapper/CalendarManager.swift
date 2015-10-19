//
//  CalendarManager.swift
//  ExportToCalendar
//
//  Created by Bruno Henriques on 17/08/15.
//  Copyright (c) 2015 Bruno Henriques. All rights reserved.
//

import EventKit

public class CalendarManager{
    public let eventStore = EKEventStore()
    public let calendarName: String
    
    private let sourceType: EKSourceType
    public var calendar: EKCalendar? {
        get {
            return calendarsWithSameIdentifier.first
        }
    }
    
    public var calendarsWithSameIdentifier: [EKCalendar] {
        get {
            return (eventStore.calendarsForEntityType(EKEntityType.Event)).filter({$0.title == self.calendarName})
        }
    }
    
    /**
        Init
    
        :param: `String`:            name of the calendar
        :param: `EKSourceType opt`:  sourceType, by default is EKSourceTypeCalDav (iCloud)
    */
    public init(calendarName: String, sourceType: EKSourceType = EKSourceType.CalDAV){
        self.calendarName = calendarName
        self.sourceType = sourceType
    }
    
    /**
        Request access and execute block of code
        
        :param: `completion: (error: NSError?) -> ()` block of code
    */
    public func requestAuthorization(completion: (error: NSError?) -> ()){
        switch EKEventStore.authorizationStatusForEntityType(EKEntityType.Event) {
        case .Authorized:
            completion(error: nil)
        case .Denied:
            completion(error: generateDeniedAccessToCalendarError())
        case .NotDetermined:
            eventStore.requestAccessToEntityType(EKEntityType.Event, completion: {[weak self] (granted: Bool, error: NSError?) -> Void in
                completion(error: granted ? nil : error)
                })
        default:
            completion(error: generateDeniedAccessToCalendarError())
        }
    }
    
    /**
        Add calendar
        
        :param: `Bool optional`: commit, default true
        :param: `(wasSaved: Bool, error: NSError?) -> () optional`: completion in main_queue, default nil
    */
    public func addCalendar(commit: Bool = true, completion: ((wasSaved: Bool, error: NSError?) -> ())? = nil) {
        let newCalendar = EKCalendar(forEntityType: EKEntityType.Event, eventStore: eventStore)
        newCalendar.title = calendarName
        
        // Filter the available sources and select the ones pretended. The instance MUST com from eventStore
        let sourcesInEventStore = eventStore.sources
        guard let source = (sourcesInEventStore.filter{ $0.sourceType == self.sourceType }.first) else {
            return
        }
        newCalendar.source = source
        
        do {
            try eventStore.saveCalendar(newCalendar, commit: commit)
            completion?(wasSaved: true, error: nil)
        } catch let error as NSError {
            completion?(wasSaved: false, error: error)
        }
    }
    
    /**
        Returns a new event attached to this calendar or nil if the calendar doesn't exist yet
        
        :return: `EKEvent?`
    */
    public func createEvent() -> EKEvent? {
        if let c = calendar {
            let event = EKEvent(eventStore: eventStore)
            event.calendar = c
            return event
        }
        
        return nil
    }
    
    /**
        Remove the event from the event store
        
        :param: `String`: eventId
        :param: `Bool optional`: commit, true
        :param: `(wasRemoved: Bool, error: NSError?)-> () optional`: completion block in main_queue, default nil
    */
    public func removeEvent(eventId: String, commit: Bool = true, completion: ((wasRemoved: Bool, error: NSError?)-> ())? = nil){
        // Remove event from Calendar
        guard let event = getEvent(eventId) else {
            return
        }
        do {
            try eventStore.removeEvent(event, span: EKSpan.ThisEvent, commit: commit)
            completion?(wasRemoved: true, error: nil)
        } catch let error as NSError {
            completion?(wasRemoved: false, error: error)
        }
    }
    
    /**
        Removes the calendar along with its events
        
        :param: `Bool optional`: commit, default true
        :param: `(wasRemoved: Bool, error: NSError?)-> () optional`: completion, default nil
    */
    public func removeCalendar(commit: Bool = true, completion: ((wasRemoved: Bool, error: NSError?)-> ())? = nil){
        guard let calendar = calendar else {
            return
        }
        for c in calendarsWithSameIdentifier {
            print("Removing \(c.title)")
            do {
                try eventStore.removeCalendar(calendar, commit: commit)
                completion?(wasRemoved: true, error: nil)
            } catch let error as NSError {
                completion?(wasRemoved: false, error: error)
                break
            }
        }
        completion?(wasRemoved: true, error: nil)
    }
    
    /**
        Get events
        
        :param: `NSDate`: start date
        :param: `NSDate`: end date
        
        :returns: `(events: [EKEvent], error: NSError?)`
    */
    public func getEvents(startDate: NSDate, endDate: NSDate) -> (events: [EKEvent], error: NSError?){
        if let c = calendar {
            let pred = eventStore.predicateForEventsWithStartDate(startDate, endDate: endDate, calendars: [c])
            return (eventStore.eventsMatchingPredicate(pred), nil)
        }
        
        return ([], generateErrorCalendarNotFoundError())
    }
    
    /**
        Get event with id
        
        :return: `EKEvent?`: the event if exists
    */
    
    public func getEvent(eventId: String) -> EKEvent?{
        return eventStore.eventWithIdentifier(eventId)
    }
    
    
    /**
        Clear all events from the calendar. Removes and then creates the calendar
        
        :param: `(error: NSError?) -> () optional`: completion block in main_queue, default nil
    */
    public func clearEvents(completion: ((error: NSError?) -> ())? = nil){
        removeCalendar(true, completion: {(wasRemoved: Bool, error: NSError?) in
            if wasRemoved {
                self.addCalendar(completion: {(wasSaved: Bool, error: NSError?) in
                    completion?(error: wasSaved ? nil : error)
                })
            }else {
                completion?(error: wasRemoved ? nil : error)
            }
        })
    }
    
    /**
        Insert new event in the calendar. Use createEvent method of don't forget to attach the intended calendar to the event
        
        :param: `EKEvent`: the event
        :param: `Bool optional`: commit, default true
        :param: `(wasSaved: Bool, error: NSError?)-> () optional`: completion block in main_queue, default nil
    */
    public func insertEvent(event: EKEvent, commit: Bool = true, completion: ((wasSaved: Bool, error: NSError?)-> ())? = nil) {
        // Save Event in Calendar
        do {
            try eventStore.saveEvent(event, span: EKSpan.ThisEvent, commit: commit)
            completion?(wasSaved: true, error: nil)
        } catch let error as NSError {
            completion?(wasSaved: false, error: error)
        }
    }
    
    /**
        Commit
        
        :returns: `NSError?`
    */
    public func commit() -> NSError?{
        do {
            try eventStore.commit()
            return nil
        } catch let error as NSError {
            return error
        }
    }
    
    /**
        Reset eventStore to latest saved state
    */
    public func reset(){
        eventStore.reset()
    }
}

extension CalendarManager {
    private func generateErrorCalendarNotFoundError() -> NSError{
        let userInfo = [
            NSLocalizedDescriptionKey: "Calendar not found",
            NSLocalizedFailureReasonErrorKey: "Calendar not found",
            NSLocalizedRecoverySuggestionErrorKey: "Add calendar before adding events"
        ]
        
        return NSError(domain: "CalendarNotFound", code: 667, userInfo: userInfo)
    }
    
    private func generateDeniedAccessToCalendarError() -> NSError{
        let userInfo = [
            NSLocalizedDescriptionKey: "Denied access to calendar",
            NSLocalizedFailureReasonErrorKey: "Authorization was rejected",
            NSLocalizedRecoverySuggestionErrorKey: "Try accepting authorization"
        ]
        return NSError(domain: "CalendarAuthorization", code: 666, userInfo: userInfo)
    }
    
    private func generateInvalidRangeError() -> NSError{
        let userInfo = [
            NSLocalizedDescriptionKey: "Invalid range",
            NSLocalizedFailureReasonErrorKey: "Error generating predicate",
            NSLocalizedRecoverySuggestionErrorKey: "Use a shorter range (e.g. 4 years)"
        ]
        return NSError(domain: "CalendarFetchError", code: 668, userInfo: userInfo)
    }
}