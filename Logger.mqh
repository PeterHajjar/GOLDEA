/*
   Logger.mqh
   Single responsibility: centralized, level-based logging for all EA modules.
*/
#ifndef GOLDEA_LOGGER_MQH
#define GOLDEA_LOGGER_MQH

enum ELogLevel
{
   LOG_LEVEL_INFO  = 0,
   LOG_LEVEL_WARN  = 1,
   LOG_LEVEL_ERROR = 2
};

class CLogger
{
private:
   ELogLevel m_minLevel;

   string LevelName(ELogLevel level)
   {
      switch(level)
      {
         case LOG_LEVEL_INFO:
            return "INFO";
         case LOG_LEVEL_WARN:
            return "WARN";
         case LOG_LEVEL_ERROR:
            return "ERROR";
      }

      return "UNKNOWN";
   }

   bool ShouldLog(ELogLevel level)
   {
      return ((int)level >= (int)m_minLevel);
   }

   void Write(ELogLevel level, string message)
   {
      if(!ShouldLog(level))
         return;

      PrintFormat("[GOLDEA][%s] %s", LevelName(level), message);
   }

public:
   CLogger()
   {
      m_minLevel = LOG_LEVEL_INFO;
   }

   void Init(ELogLevel minLevel)
   {
      m_minLevel = minLevel;
   }

   void Info(string message)
   {
      Write(LOG_LEVEL_INFO, message);
   }

   void Warn(string message)
   {
      Write(LOG_LEVEL_WARN, message);
   }

   void Error(string message)
   {
      Write(LOG_LEVEL_ERROR, message);
   }
};

#endif
