/*
   SignalInterface.mqh
   Single responsibility: define the strategy signal contract and a no-op dummy implementation.
*/
#ifndef GOLDEA_SIGNAL_INTERFACE_MQH
#define GOLDEA_SIGNAL_INTERFACE_MQH

#include "Config.mqh"
#include "Logger.mqh"

enum ESignalDirection
{
   SIGNAL_SELL = -1,
   SIGNAL_NONE = 0,
   SIGNAL_BUY  = 1
};

class CSignalBase
{
protected:
   CLogger *m_logger;

public:
   CSignalBase()
   {
      m_logger = NULL;
   }

   virtual bool Init(CLogger *logger)
   {
      m_logger = logger;
      return true;
   }

   virtual ESignalDirection GetSignal(string symbol) = 0;

   virtual double StopLossPips()
   {
      return InpStrategyStopLossPips;
   }

   virtual double TakeProfitPips()
   {
      return InpStrategyTakeProfitPips;
   }

   virtual string Name()
   {
      return "CSignalBase";
   }
};

class CSignalDummy : public CSignalBase
{
public:
   virtual ESignalDirection GetSignal(string symbol)
   {
      return SIGNAL_NONE;
   }

   virtual string Name()
   {
      return "CSignalDummy";
   }
};

#endif
