/*
   PipCalculator.mqh
   Single responsibility: symbol-aware point, pip, tick value, stop level, and volume conversions.
*/
#ifndef GOLDEA_PIP_CALCULATOR_MQH
#define GOLDEA_PIP_CALCULATOR_MQH

#include "Logger.mqh"

#define GOLDEA_PIPCALC_EPSILON 0.00000001
#define GOLDEA_MAX_VOLUME_DIGITS 8
#define GOLDEA_FRACTIONAL_PIP_MULTIPLIER 10.0

class CPipCalculator
{
private:
   string   m_symbol;
   int      m_digits;
   double   m_point;
   double   m_pipSize;
   double   m_tickSize;
   double   m_tickValue;
   double   m_pipValuePerLot;
   double   m_pointValuePerLot;
   long     m_stopsLevelPoints;
   long     m_freezeLevelPoints;
   double   m_volumeMin;
   double   m_volumeMax;
   double   m_volumeStep;
   CLogger *m_logger;

   void Reset()
   {
      m_symbol            = "";
      m_digits            = 0;
      m_point             = 0.0;
      m_pipSize           = 0.0;
      m_tickSize          = 0.0;
      m_tickValue         = 0.0;
      m_pipValuePerLot    = 0.0;
      m_pointValuePerLot  = 0.0;
      m_stopsLevelPoints  = 0;
      m_freezeLevelPoints = 0;
      m_volumeMin         = 0.0;
      m_volumeMax         = 0.0;
      m_volumeStep        = 0.0;
      m_logger            = NULL;
   }

   bool ReadInteger(ENUM_SYMBOL_INFO_INTEGER property, long &value, string name)
   {
      if(SymbolInfoInteger(m_symbol, property, value))
         return true;

      if(m_logger != NULL)
         m_logger.Error("Unable to read symbol integer property: " + name);

      return false;
   }

   bool ReadDouble(ENUM_SYMBOL_INFO_DOUBLE property, double &value, string name)
   {
      if(SymbolInfoDouble(m_symbol, property, value))
         return true;

      if(m_logger != NULL)
         m_logger.Error("Unable to read symbol double property: " + name);

      return false;
   }

   int VolumeDigits()
   {
      int digits = 0;
      double step = m_volumeStep;

      while(digits < GOLDEA_MAX_VOLUME_DIGITS && MathAbs(step - MathRound(step)) > GOLDEA_PIPCALC_EPSILON)
      {
         step *= 10.0;
         digits++;
      }

      return digits;
   }

public:
   CPipCalculator()
   {
      Reset();
   }

   bool Init(string symbol, CLogger *logger)
   {
      Reset();
      m_symbol = symbol;
      m_logger = logger;

      return Refresh();
   }

   bool Refresh()
   {
      long digitsRaw = 0;

      if(!ReadInteger(SYMBOL_DIGITS, digitsRaw, "SYMBOL_DIGITS"))
         return false;

      m_digits = (int)digitsRaw;

      if(!ReadDouble(SYMBOL_POINT, m_point, "SYMBOL_POINT"))
         return false;
      if(!ReadDouble(SYMBOL_TRADE_TICK_SIZE, m_tickSize, "SYMBOL_TRADE_TICK_SIZE"))
         return false;
      if(!ReadDouble(SYMBOL_TRADE_TICK_VALUE, m_tickValue, "SYMBOL_TRADE_TICK_VALUE"))
         return false;
      if(!ReadInteger(SYMBOL_TRADE_STOPS_LEVEL, m_stopsLevelPoints, "SYMBOL_TRADE_STOPS_LEVEL"))
         return false;
      if(!ReadInteger(SYMBOL_TRADE_FREEZE_LEVEL, m_freezeLevelPoints, "SYMBOL_TRADE_FREEZE_LEVEL"))
         return false;
      if(!ReadDouble(SYMBOL_VOLUME_MIN, m_volumeMin, "SYMBOL_VOLUME_MIN"))
         return false;
      if(!ReadDouble(SYMBOL_VOLUME_MAX, m_volumeMax, "SYMBOL_VOLUME_MAX"))
         return false;
      if(!ReadDouble(SYMBOL_VOLUME_STEP, m_volumeStep, "SYMBOL_VOLUME_STEP"))
         return false;

      if(m_point <= 0.0 || m_tickSize <= 0.0 || m_volumeMin <= 0.0 || m_volumeMax <= 0.0 || m_volumeStep <= 0.0)
      {
         if(m_logger != NULL)
            m_logger.Error("Invalid symbol settings. Point, tick size, and volume limits must be positive.");

         return false;
      }

      double pipMultiplier = 1.0;
      if(m_digits == 3 || m_digits == 5)
         pipMultiplier = GOLDEA_FRACTIONAL_PIP_MULTIPLIER;

      m_pipSize          = m_point * pipMultiplier;
      m_pointValuePerLot = m_tickValue * (m_point / m_tickSize);
      m_pipValuePerLot   = m_tickValue * (m_pipSize / m_tickSize);

      if(m_pipSize <= 0.0 || m_pipValuePerLot <= 0.0 || m_pointValuePerLot <= 0.0)
      {
         if(m_logger != NULL)
            m_logger.Error("Invalid symbol value conversion. Tick value, tick size, point, or pip size is not usable.");

         return false;
      }

      return true;
   }

   string Symbol()
   {
      return m_symbol;
   }

   int Digits()
   {
      return m_digits;
   }

   double Point()
   {
      return m_point;
   }

   double PipSize()
   {
      return m_pipSize;
   }

   double PriceToPips(double priceDistance)
   {
      if(m_pipSize <= 0.0)
         return 0.0;

      return priceDistance / m_pipSize;
   }

   double PipsToPrice(double pips)
   {
      return pips * m_pipSize;
   }

   double PipValuePerLot()
   {
      return m_pipValuePerLot;
   }

   double PointValuePerLot()
   {
      return m_pointValuePerLot;
   }

   long StopsLevelPoints()
   {
      return m_stopsLevelPoints;
   }

   long FreezeLevelPoints()
   {
      return m_freezeLevelPoints;
   }

   double StopLevelPips()
   {
      return PriceToPips((double)m_stopsLevelPoints * m_point);
   }

   double FreezeLevelPips()
   {
      return PriceToPips((double)m_freezeLevelPoints * m_point);
   }

   double MinimumTradeDistancePips()
   {
      long distancePoints = m_stopsLevelPoints;
      if(m_freezeLevelPoints > distancePoints)
         distancePoints = m_freezeLevelPoints;

      return PriceToPips((double)distancePoints * m_point);
   }

   bool CurrentSpreadPips(double &spreadPips)
   {
      spreadPips = 0.0;

      MqlTick tick;

      if(!SymbolInfoTick(m_symbol, tick))
      {
         return false;
      }

      spreadPips = PriceToPips(MathAbs(tick.ask - tick.bid));
      return true;
   }

   double NormalizePrice(double price)
   {
      return NormalizeDouble(price, m_digits);
   }

   double VolumeMin()
   {
      return m_volumeMin;
   }

   double VolumeMax()
   {
      return m_volumeMax;
   }

   double VolumeStep()
   {
      return m_volumeStep;
   }

   double NormalizeVolumeDown(double volume)
   {
      if(volume <= 0.0 || m_volumeStep <= 0.0)
         return 0.0;

      double steps = MathFloor((volume / m_volumeStep) + GOLDEA_PIPCALC_EPSILON);
      double normalized = steps * m_volumeStep;

      return NormalizeDouble(normalized, VolumeDigits());
   }

   bool IsVolumeWithinLimits(double volume)
   {
      if(volume < m_volumeMin - GOLDEA_PIPCALC_EPSILON)
         return false;
      if(volume > m_volumeMax + GOLDEA_PIPCALC_EPSILON)
         return false;

      double normalized = NormalizeVolumeDown(volume);
      return (MathAbs(normalized - volume) <= GOLDEA_PIPCALC_EPSILON);
   }
};

#endif
