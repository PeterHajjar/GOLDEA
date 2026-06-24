/*
   SessionFilter.mqh
   Single responsibility: decide whether new entries are allowed in the configured broker-server session window.
*/
#ifndef GOLDEA_SESSION_FILTER_MQH
#define GOLDEA_SESSION_FILTER_MQH

#include "Config.mqh"
#include "Logger.mqh"

class CSessionFilter
{
private:
   CLogger *m_logger;

   bool DayAllowed(int dayOfWeek)
   {
      if(dayOfWeek == 0)
         return InpAllowSunday;
      if(dayOfWeek == 1)
         return InpAllowMonday;
      if(dayOfWeek == 2)
         return InpAllowTuesday;
      if(dayOfWeek == 3)
         return InpAllowWednesday;
      if(dayOfWeek == 4)
         return InpAllowThursday;
      if(dayOfWeek == 5)
         return InpAllowFriday;
      if(dayOfWeek == 6)
         return InpAllowSaturday;

      return false;
   }

public:
   CSessionFilter()
   {
      m_logger = NULL;
   }

   bool Init(CLogger *logger)
   {
      m_logger = logger;
      return true;
   }

   bool IsEntryAllowed()
   {
      if(!InpEnableSessionFilter)
         return true;

      datetime serverTime = TimeTradeServer();
      if(serverTime <= 0)
         serverTime = TimeCurrent();

      MqlDateTime parts;
      TimeToStruct(serverTime, parts);

      if(!DayAllowed(parts.day_of_week))
         return false;

      int currentMinute = (parts.hour * 60) + parts.min;
      int startMinute = (InpSessionStartHour * 60) + InpSessionStartMinute;
      int endMinute = (InpSessionEndHour * 60) + InpSessionEndMinute;

      if(startMinute <= endMinute)
         return (currentMinute >= startMinute && currentMinute <= endMinute);

      return (currentMinute >= startMinute || currentMinute <= endMinute);
   }
};

#endif
