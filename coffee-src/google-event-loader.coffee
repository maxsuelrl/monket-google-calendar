class MKT.GoogleEventLoader
  constructor: (service, loading) ->
    @service = service
    @loading = loading
    @cache = {}

    @addEventHook = ->
    @updateEventHook = ->
    @removeEventHook = ->

  init: (successCallback, failureCallback) ->
    @loading.show()
    @service.getAllCalendarsFeed 'http://www.google.com/calendar/feeds/default/allcalendars/full', (result) =>
      @loading.hide()
      @calendars = result.feed.entry

      for calendar in @calendars
        accessValue = calendar.getAccessLevel().getValue()
        calendar.editable = accessValue == google.gdata.calendar.AccessLevelProperty.VALUE_OWNER or 
          accessValue == google.gdata.calendar.AccessLevelProperty.VALUE_EDITOR

      successCallback()
    , =>
      @loading.hide()
      failureCallback()
    
    # // if (localStorage && localStorage.offlineCache) {
    # //  me.offlineCache = JSON.parse(localStorage.offlineCache, function (key, value) {
    # //         var a;
    # //         if (typeof value === 'string') {
    # //           a = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2}(?:\.\d*)?)Z$/.exec(value);
    # //           if (a) {
    # //             return new Date(Date.UTC(+a[1], +a[2] - 1, +a[3], +a[4], +a[5], +a[6]));
    # //           }
    # //         }
    # //         return value;
    # //       });      
    # // }

  getFeedUriForCalendar: (calNumber) ->
    calendar = @calendars[calNumber]
    calendar.getLink().href

  load: (startDate, endDate, successCallback, failureCallback) ->
    # // if (me.offlineCache && me.datesInOfflineCache(startDate, endDate)) {
    # //  successCallback(me.getOfflineCachedEvents(startDate, endDate), startDate, endDate);
    # // }
    
    if @datesInCache(startDate, endDate)
      successCallback @getCachedEvents(startDate, endDate), startDate, endDate
    else if @isLoading(startDate, endDate)
      @addCallbacks startDate, endDate, successCallback, failureCallback
    else
      cacheStartDate = new Date(startDate.getFullYear(), 0, 1)
      cacheEndDate = new Date(startDate.getFullYear() +1, 0, 7)

      @cache[@getCacheKey(startDate)] = {
        remaining: @calendars.length
        entries: []
        callbacks: []
      }

      @loading.show()

      @addCallbacks startDate, endDate, successCallback, failureCallback

      for i in [0...@calendars.length]
        @loadFromGoogle cacheStartDate, cacheEndDate, (entries) => 
          cacheInfo = @cache[@getCacheKey startDate]
          cacheInfo.remaining--
          cacheInfo.entries = cacheInfo.entries.concat entries

          console.log "loaded #{i} of #{@calendars.length}. #{cacheInfo.remaining} remaining"
        


          @fireCallbacks cacheInfo, true
          if cacheInfo.remaining == 0
            console.log "No calendars remaining to load"
            @clearCallbacks cacheInfo
            @loading.hide()

          # // if (localStorage) {
          # //  localStorage.offlineCache = JSON.stringify(me.cache);
          # // }
        , =>
          cacheInfo = @cache[@getCacheKey startDate]
          cacheInfo.remaining--

          console.log "Error Loading #{i} of #{@calendars.length}. #{cacheInfo.remaining} remaining"
          console.log arguments

          @fireCallbacks cacheInfo, false
          if cacheInfo.remaining == 0
            @clearCallbacks cacheInfo
            @loading.hide()
        , i

  getCacheKey: (startDate) ->
    startDate.getFullYear()

  isLoading: (startDate, endDate) ->
    !!@cache[@getCacheKey startDate]
  
  datesInCache: (startDate, endDate) ->
    cacheInfo = @cache[@getCacheKey startDate]
    return cacheInfo and cacheInfo.remaining == 0
  
  addCallbacks: (startDate, endDate, successCallback, failureCallback) ->
    cacheInfo = @cache[@getCacheKey startDate]
    cacheInfo.callbacks.push {
      success: successCallback
      failure: failureCallback
      startDate: startDate
      endDate: endDate
    }
  
  fireCallbacks: (cacheInfo, success) ->
    for cb in cacheInfo.callbacks
      if success
        entries = @getCachedEvents cb.startDate, cb.endDate
        cb.success entries, cb.startDate, cb.endDate
      else
        cb.failure cb.startDate, cb.endDate
  
  clearCallbacks: (cacheInfo) ->
    cacheInfo.callbacks = []
  
  getCachedEvents: (startDate, endDate) ->
    cacheInfo = @cache[@getCacheKey startDate]
    cacheEntries = cacheInfo.entries

    entries = []
    for entry in cacheEntries
      if entry.end > startDate and entry.start <= endDate
        entries.push entry
        
    return entries
  
# // me.datesInOfflineCache = function(startDate, endDate) {
# //  var cacheInfo = me.offlineCache[me.getCacheKey(startDate)];
# //  return (cacheInfo && cacheInfo.remaining == 0);
# // };
# // 
# // me.getOfflineCachedEvents = function(startDate, endDate) {
# //  var cacheInfo = me.offlineCache[me.getCacheKey(startDate)];
# //  var cacheEntries = cacheInfo.entries;
# // 
# //  var entries = [];
# //  for (var i = 0; i < cacheEntries.length; i++) {
# //    var entry = cacheEntries[i];
# // 
# //    if (entry.end > startDate && entry.start <= endDate) {
# //      entries.push(entry);
# //    }
# //  }
# //      
# //  return entries;
# // }
  
  loadFromGoogle: (startDate, endDate, successCallback, failureCallback, calNumber) ->
    
    eventsCallback = (result) =>
      entries = result.feed.entry
      results = []

      for entry in entries
        event = @createEventFromGoogleEvent entry, calNumber

        results.push event if event.end > startDate

      successCallback results, startDate, endDate

    uri = @getFeedUriForCalendar calNumber

    query = new google.gdata.calendar.CalendarEventQuery(uri)

    startMin = new google.gdata.DateTime(startDate)
    startMax = new google.gdata.DateTime(endDate)
    query.setMinimumStartTime(startMin)
    query.setMaximumStartTime(startMax)
    query.setSingleEvents(true)
    query.setMaxResults(500)
    query.setOrderBy('starttime')
    query.setSortOrder('a')

    @service.getEventsFeed query, eventsCallback, failureCallback
  
  createEventFromGoogleEvent: (entry, calNumber) ->
    times = entry.getTimes()

    if times.length > 0
      startTime = times[0].getStartTime().getDate()
      entryStartDate = new Date(startTime.getFullYear(), startTime.getMonth(), startTime.getDate())

      endTime = times[0].getEndTime().getDate()
      endDate = new Date(endTime.getFullYear(), endTime.getMonth(), endTime.getDate())

      # Get the whole number of days difference
      # And then add on any extra hours in the last day
      # Done like this to avoid issues when summer time changes
      length = Math.round((endDate - entryStartDate) / (1000 * 60 * 60 * 24))
      if (endTime - endDate) > 0
        length = + 1

      entryEndDate = entryStartDate.addDays length

    summary = $.trim(entry.getTitle().getText())
    editable = @calendars[calNumber].editable
    
    @createEventObject summary, calNumber, entryStartDate, entryEndDate, length, editable, entry

  createEventObject: (summary, calNumber, start, end, length, editable, googleEvent, isNew) ->
    event = {
      summary: summary
      calNumber: calNumber
      start: start
      end: end
      length: length
      editable: editable
      googleEvent: googleEvent
      isNew: isNew
    }
    
    event.save = (success, failure, startCalNumber) =>
      if event.googleEvent
        # Set title
        event.googleEvent.getTitle().setText(event.summary)

        # Set time
        startTime = new google.gdata.DateTime(event.start, true)
        endTime = new google.gdata.DateTime(event.end, true)

        event_when = new google.gdata.When()
        event_when.setStartTime(startTime)
        event_when.setEndTime(endTime)
        event.googleEvent.setTimes([event_when])


        if startCalNumber? and event.calNumber != startCalNumber
          @moveToNewCalendar event, startCalNumber, success, failure
        else
          @saveChanges event, success, failure
      else
        event.isNew = false
        @createEvent event, success, failure


    event.remove = (success, failure) =>
      return success() unless event.googleEvent
      
      event.googleEvent.deleteEntry =>
        @removeEvent(event)
        success()
      , =>
        failure()

    
    event 

  addEvent: (event) ->
    startDate = event.start
    cacheInfo = @cache[@getCacheKey startDate]
    cacheInfo.entries.push event

    @addEventHook event

  createEvent: (event, successCallback, failureCallback) ->
    # Create an instance of CalendarEventEntry representing the new event
    entry = new google.gdata.calendar.CalendarEventEntry {
      title: {
        type: 'text'
        text: event.summary
      }
      times: [{
        startTime: new google.gdata.DateTime(event.start, true)
        endTime: new google.gdata.DateTime(event.end, true)
      }]
    }

    feedUri = @getFeedUriForCalendar(event.calNumber)
    
    # Submit the request using the calendar service object
    @service.insertEntry feedUri, entry, (response) =>
      event.googleEvent = response.entry
      successCallback()
    , =>
      failureCallback()
    , google.gdata.calendar.CalendarEventEntry

  saveChanges: (event, success, failure) ->
    event.googleEvent.updateEntry (response) =>
      event.googleEvent = response.entry
      event.googleEvent.getSequence().setValue(event.googleEvent.getSequence().getValue() + 1)
      success response
    , (response) =>
      failure response

  moveToNewCalendar: (event, oldCalNumber, success, failure) ->
    # Insert the entry into the new calendar
    # then if successful remove it from the old calendar

    event.googleEvent.getSequence().setValue(event.googleEvent.getSequence().getValue() + 1)
    
    feedUri = @getFeedUriForCalendar event.calNumber
    @service.insertEntry feedUri, event.googleEvent, (response) =>
      newGoogleEvent = response.entry

      event.googleEvent = newGoogleEvent
      event.googleEvent.getSequence().setValue(event.googleEvent.getSequence().getValue() + 1)
      
      event.googleEvent.deleteEntry (response) =>

        success response
        
      , (response) =>
        failure response
      
    , (response) =>
      failure response
    , google.gdata.calendar.CalendarEventEntry

  updateEvent: (event, oldStart, oldEnd) ->
    @updateEventHook event, oldStart, oldEnd
    
  removeEvent: (event) ->
    startDate = event.start
    cacheInfo = @cache[@getCacheKey startDate]
    cacheEntries = cacheInfo.entries

    for i in [0...cacheEntries.length]
      entry = cacheEntries[i]
      
      if @eventsAreEqual event, entry
        Array.remove cacheEntries, i
        @removeEventHook event
        return
        
    null
  
  eventsAreEqual: (a, b) ->
    return a.summary == b.summary and
      a.start == b.start and
      a.end == b.end

