/*
   SpreadFilter.mqh
   Single responsibility: decide whether new entries are allowed based on current spread.
*/
#ifndef GOLDEA_SPREAD_FILTER_MQH
#define GOLDEA_SPREAD_FILTER_MQH

#include "Config.mqh"
#include "PipCalculator.mqh"

#define GOLDEA_SPREAD_WARN_COOLDOWN_SECONDS 60

class CSpreadFilter
{
private:
   CPipCalculator *m_pip;
   CLogger        *m_logger;
   datetime        m_lastWarnTime;

public:
   CSpreadFilter()
   {
      m_pip          = NULL;
      m_logger       = NULL;
      m_lastWarnTime = 0;
   }

   bool Init(CPipCalculator *pip, CLogger *logger)
   {
      m_pip    = pip;
      m_logger = logger;

      if(m_pip == NULL)
      {
         if(m_logger != NULL)
            m_logger.Error("SpreadFilter requires PipCalculator.");

         return false;
      }

      return true;
   }

   bool IsEntryAllowed()
   {
      if(!InpEnableSpreadFilter)
         return true;

      if(m_pip == NULL)
         return false;

      double spreadPips = 0.0;
      if(!m_pip.CurrentSpreadPips(spreadPips))
      {
         datetime now = TimeCurrent();
         if(m_logger != NULL && (m_lastWarnTime == 0 || now - m_lastWarnTime >= GOLDEA_SPREAD_WARN_COOLDOWN_SECONDS))
         {
            m_logger.Warn("Entry blocked by spread filter because current spread could not be determined.");
            m_lastWarnTime = now;
         }

         return false;
      }

      if(spreadPips <= InpMaxSpreadPips + GOLDEA_DOUBLE_EPSILON)
         return true;

      datetime now = TimeCurrent();
      if(m_logger != NULL && (m_lastWarnTime == 0 || now - m_lastWarnTime >= GOLDEA_SPREAD_WARN_COOLDOWN_SECONDS))
      {
         m_logger.Warn("Entry blocked by spread filter. Current spread: " + DoubleToString(spreadPips, 2)
                       + " pips, max allowed: " + DoubleToString(InpMaxSpreadPips, 2) + " pips.");
         m_lastWarnTime = now;
      }

      return false;
   }
};

#endif
