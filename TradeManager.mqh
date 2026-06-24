/*
   TradeManager.mqh
   Single responsibility: manage open EA positions with breakeven, trailing, partial close, and target rules.
*/
#ifndef GOLDEA_TRADE_MANAGER_MQH
#define GOLDEA_TRADE_MANAGER_MQH

#include "Config.mqh"
#include "PipCalculator.mqh"
#include "TradeExecutor.mqh"

struct SManagementTarget
{
   bool              enabled;
   EPartialCloseMode triggerMode;
   double            triggerValue;
   double            closePercent;
   string            stateSuffix;
};

class CTradeManager
{
private:
   string          m_symbol;
   CPipCalculator *m_pip;
   CTradeExecutor *m_executor;
   CLogger        *m_logger;
   int             m_atrHandle;
   int             m_targetCount;
   SManagementTarget m_targets[GOLDEA_MAX_TARGETS];

   void ClearTargets()
   {
      for(int index = 0; index < GOLDEA_MAX_TARGETS; index++)
      {
         m_targets[index].enabled      = false;
         m_targets[index].triggerMode  = PARTIAL_MODE_R_MULTIPLE;
         m_targets[index].triggerValue = 0.0;
         m_targets[index].closePercent = 0.0;
         m_targets[index].stateSuffix  = "";
      }

      m_targetCount = 0;
   }

   void SetTarget(int index, EPartialCloseMode mode, double triggerValue, double closePercent, string suffix)
   {
      if(index < 0 || index >= GOLDEA_MAX_TARGETS)
         return;

      m_targets[index].enabled      = true;
      m_targets[index].triggerMode  = mode;
      m_targets[index].triggerValue = triggerValue;
      m_targets[index].closePercent = closePercent;
      m_targets[index].stateSuffix  = suffix;
   }

   void ConfigureTargets()
   {
      ClearTargets();

      if(InpEnableMultiTargets)
      {
         m_targetCount = InpTargetCount;
         if(m_targetCount < 1)
            m_targetCount = 1;
         if(m_targetCount > GOLDEA_MAX_TARGETS)
            m_targetCount = GOLDEA_MAX_TARGETS;

         SetTarget(0, InpTargetTriggerMode, InpTarget1Trigger, InpTarget1ClosePercent, "TARGET_1_DONE");
         if(m_targetCount >= 2)
            SetTarget(1, InpTargetTriggerMode, InpTarget2Trigger, InpTarget2ClosePercent, "TARGET_2_DONE");
         if(m_targetCount >= 3)
            SetTarget(2, InpTargetTriggerMode, InpTarget3Trigger, InpTarget3ClosePercent, "TARGET_3_DONE");

         return;
      }

      if(InpEnablePartialClose)
      {
         double triggerValue = InpPartialCloseTriggerPips;
         if(InpPartialCloseMode == PARTIAL_MODE_R_MULTIPLE)
            triggerValue = InpPartialCloseTriggerR;

         m_targetCount = 1;
         SetTarget(0, InpPartialCloseMode, triggerValue, InpPartialClosePercent, "PARTIAL_DONE");
      }
   }

   bool IsManagedSelectedPosition()
   {
      string positionSymbol = PositionGetString(POSITION_SYMBOL);
      long positionMagic = PositionGetInteger(POSITION_MAGIC);

      return (positionSymbol == m_symbol && positionMagic == InpMagicNumber);
   }

   string StateKey(ulong ticket, string suffix)
   {
      return "GOLDEA_" + IntegerToString(InpMagicNumber) + "_" + IntegerToString((long)ticket) + "_" + suffix;
   }

   double StateGet(ulong ticket, string suffix, double fallback)
   {
      string key = StateKey(ticket, suffix);
      if(GlobalVariableCheck(key))
         return GlobalVariableGet(key);

      return fallback;
   }

   void StateSet(ulong ticket, string suffix, double value)
   {
      GlobalVariableSet(StateKey(ticket, suffix), value);
   }

   void RegisterInitialState(ulong ticket, double openPrice, double stopLoss, double volume)
   {
      string riskKey = StateKey(ticket, "INITIAL_RISK_PIPS");
      if(!GlobalVariableCheck(riskKey))
      {
         double riskPips = InpStrategyStopLossPips;

         if(stopLoss > 0.0)
            riskPips = MathAbs(openPrice - stopLoss) / m_pip.PipSize();

         if(riskPips > 0.0)
            GlobalVariableSet(riskKey, riskPips);
      }

      string volumeKey = StateKey(ticket, "INITIAL_VOLUME");
      if(!GlobalVariableCheck(volumeKey))
         GlobalVariableSet(volumeKey, volume);
   }

   bool LoadProfitPips(ENUM_POSITION_TYPE positionType, double openPrice, double &profitPips)
   {
      profitPips = 0.0;

      MqlTick tick;
      if(!SymbolInfoTick(m_symbol, tick))
      {
         if(m_logger != NULL)
            m_logger.Warn("Unable to read tick while calculating position profit in pips.");

         return false;
      }

      if(positionType == POSITION_TYPE_BUY)
         profitPips = m_pip.PriceToPips(tick.bid - openPrice);
      else
         profitPips = m_pip.PriceToPips(openPrice - tick.ask);

      return true;
   }

   double TargetTriggerPips(SManagementTarget &target, double initialRiskPips)
   {
      if(target.triggerMode == PARTIAL_MODE_R_MULTIPLE)
         return initialRiskPips * target.triggerValue;

      return target.triggerValue;
   }

   double TargetCloseVolume(double initialVolume, double currentVolume, double closePercent)
   {
      double rawVolume = initialVolume * (closePercent / 100.0);
      double closeVolume = m_pip.NormalizeVolumeDown(rawVolume);

      if(closeVolume <= 0.0)
         return 0.0;

      if(closeVolume >= currentVolume - GOLDEA_DOUBLE_EPSILON)
         return m_pip.NormalizeVolumeDown(currentVolume);

      double remainingVolume = currentVolume - closeVolume;

      if(remainingVolume < m_pip.VolumeMin() - GOLDEA_DOUBLE_EPSILON)
         return m_pip.NormalizeVolumeDown(currentVolume);

      if(closeVolume < m_pip.VolumeMin() - GOLDEA_DOUBLE_EPSILON)
         return 0.0;

      return closeVolume;
   }

   bool ManageTargets(ulong ticket, ENUM_POSITION_TYPE positionType, double openPrice, double currentVolume)
   {
      if(m_targetCount <= 0)
         return true;

      double profitPips = 0.0;
      if(!LoadProfitPips(positionType, openPrice, profitPips))
         return true;

      double initialRiskPips = StateGet(ticket, "INITIAL_RISK_PIPS", InpStrategyStopLossPips);
      double initialVolume = StateGet(ticket, "INITIAL_VOLUME", currentVolume);

      for(int index = 0; index < m_targetCount; index++)
      {
         if(!m_targets[index].enabled)
            continue;

         if(GlobalVariableCheck(StateKey(ticket, m_targets[index].stateSuffix)))
            continue;

         double triggerPips = TargetTriggerPips(m_targets[index], initialRiskPips);
         if(triggerPips <= 0.0 || profitPips + GOLDEA_DOUBLE_EPSILON < triggerPips)
            continue;

         double closeVolume = TargetCloseVolume(initialVolume, currentVolume, m_targets[index].closePercent);
         string remainingSuffix = m_targets[index].stateSuffix + "_REMAINING_VOLUME";
         if(GlobalVariableCheck(StateKey(ticket, remainingSuffix)))
         {
            closeVolume = m_pip.NormalizeVolumeDown(StateGet(ticket, remainingSuffix, closeVolume));
            if(closeVolume > currentVolume)
               closeVolume = m_pip.NormalizeVolumeDown(currentVolume);
         }

         if(closeVolume <= 0.0)
         {
            if(m_logger != NULL)
               m_logger.Warn("Target close volume is not valid after broker normalization.");

            continue;
         }

         if(m_executor.ClosePartialPosition(ticket, closeVolume))
         {
            uint closeRetcode = m_executor.LastCloseRetcode();
            double filledVolume = m_executor.LastCloseFilledVolume();

            if(closeRetcode == TRADE_RETCODE_DONE && filledVolume + GOLDEA_DOUBLE_EPSILON >= closeVolume)
            {
               StateSet(ticket, m_targets[index].stateSuffix, (double)TimeCurrent());
               if(GlobalVariableCheck(StateKey(ticket, remainingSuffix)))
                  GlobalVariableDel(StateKey(ticket, remainingSuffix));

               currentVolume -= filledVolume;

               if(currentVolume <= 0.0)
                  return false;
            }
            else if(filledVolume > 0.0)
            {
               double remainingTargetVolume = m_pip.NormalizeVolumeDown(closeVolume - filledVolume);
               if(remainingTargetVolume > 0.0)
                  StateSet(ticket, remainingSuffix, remainingTargetVolume);

               currentVolume -= filledVolume;

               if(m_logger != NULL)
                  m_logger.Warn("Target close not fully complete. Retcode: " + IntegerToString((int)closeRetcode)
                                + ", requested volume: " + DoubleToString(closeVolume, 8)
                                + ", filled volume: " + DoubleToString(filledVolume, 8));

               if(currentVolume <= 0.0)
                  return false;
            }
         }
      }

      return true;
   }

   bool ManageBreakeven(ulong ticket, ENUM_POSITION_TYPE positionType, double openPrice, double currentSl, double currentTp)
   {
      if(!InpEnableBreakeven)
         return false;

      double profitPips = 0.0;
      if(!LoadProfitPips(positionType, openPrice, profitPips))
         return false;

      if(profitPips + GOLDEA_DOUBLE_EPSILON < InpBreakevenTriggerPips)
         return false;

      double offsetPrice = m_pip.PipsToPrice(InpBreakevenOffsetPips);
      double desiredSl = 0.0;

      if(positionType == POSITION_TYPE_BUY)
      {
         desiredSl = m_pip.NormalizePrice(openPrice + offsetPrice);
         if(currentSl > 0.0 && desiredSl <= currentSl + m_pip.Point())
            return false;
      }
      else
      {
         desiredSl = m_pip.NormalizePrice(openPrice - offsetPrice);
         if(currentSl > 0.0 && desiredSl >= currentSl - m_pip.Point())
            return false;
      }

      if(m_logger != NULL)
         m_logger.Info("Moving position to breakeven. Ticket: " + IntegerToString((long)ticket));

      return m_executor.ModifyPosition(ticket, desiredSl, currentTp);
   }

   bool LoadAtrDistance(double &distancePrice)
   {
      distancePrice = 0.0;

      if(m_atrHandle == INVALID_HANDLE)
         return false;

      double values[];
      ArrayResize(values, 1);
      ArraySetAsSeries(values, true);

      if(CopyBuffer(m_atrHandle, 0, 0, 1, values) != 1)
      {
         if(m_logger != NULL)
            m_logger.Warn("Unable to read ATR buffer for trailing stop.");

         return false;
      }

      if(values[0] <= 0.0)
         return false;

      distancePrice = values[0] * InpTrailingAtrMultiplier;
      return (distancePrice > 0.0);
   }

   void ManageTrailing(ulong ticket, ENUM_POSITION_TYPE positionType, double openPrice, double currentSl, double currentTp)
   {
      if(!InpEnableTrailingStop)
         return;

      double profitPips = 0.0;
      if(!LoadProfitPips(positionType, openPrice, profitPips))
         return;

      if(profitPips + GOLDEA_DOUBLE_EPSILON < InpTrailingStartPips)
         return;

      double trailingDistancePrice = m_pip.PipsToPrice(InpTrailingDistancePips);
      if(InpTrailingMode == TRAILING_MODE_ATR)
      {
         if(!LoadAtrDistance(trailingDistancePrice))
            return;
      }

      MqlTick tick;
      if(!SymbolInfoTick(m_symbol, tick))
         return;

      double desiredSl = 0.0;
      double stepPrice = m_pip.PipsToPrice(InpTrailingStepPips);

      if(positionType == POSITION_TYPE_BUY)
      {
         desiredSl = m_pip.NormalizePrice(tick.bid - trailingDistancePrice);
         if(currentSl > 0.0 && desiredSl <= currentSl + stepPrice)
            return;
      }
      else
      {
         desiredSl = m_pip.NormalizePrice(tick.ask + trailingDistancePrice);
         if(currentSl > 0.0 && desiredSl >= currentSl - stepPrice)
            return;
      }

      if(m_logger != NULL)
         m_logger.Info("Updating trailing stop. Ticket: " + IntegerToString((long)ticket));

      m_executor.ModifyPosition(ticket, desiredSl, currentTp);
   }

   void ManagePosition(ulong ticket)
   {
      if(!PositionSelectByTicket(ticket))
         return;

      if(!IsManagedSelectedPosition())
         return;

      ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSl = PositionGetDouble(POSITION_SL);
      double currentTp = PositionGetDouble(POSITION_TP);
      double currentVolume = PositionGetDouble(POSITION_VOLUME);

      RegisterInitialState(ticket, openPrice, currentSl, currentVolume);
      if(!ManageTargets(ticket, positionType, openPrice, currentVolume))
         return;
      if(!PositionSelectByTicket(ticket))
         return;

      currentSl = PositionGetDouble(POSITION_SL);
      currentTp = PositionGetDouble(POSITION_TP);

      if(ManageBreakeven(ticket, positionType, openPrice, currentSl, currentTp))
      {
         if(!PositionSelectByTicket(ticket))
            return;

         currentSl = PositionGetDouble(POSITION_SL);
         currentTp = PositionGetDouble(POSITION_TP);
      }

      ManageTrailing(ticket, positionType, openPrice, currentSl, currentTp);
   }

public:
   CTradeManager()
   {
      m_symbol      = "";
      m_pip         = NULL;
      m_executor    = NULL;
      m_logger      = NULL;
      m_atrHandle   = INVALID_HANDLE;
      m_targetCount = 0;
      ClearTargets();
   }

   bool Init(string symbol, CPipCalculator *pip, CTradeExecutor *executor, CLogger *logger)
   {
      m_symbol   = symbol;
      m_pip      = pip;
      m_executor = executor;
      m_logger   = logger;

      if(m_pip == NULL || m_executor == NULL)
      {
         if(m_logger != NULL)
            m_logger.Error("TradeManager requires PipCalculator and TradeExecutor.");

         return false;
      }

      ConfigureTargets();

      if(InpEnableTrailingStop && InpTrailingMode == TRAILING_MODE_ATR)
      {
         ENUM_TIMEFRAMES timeframe = InpTrailingAtrTimeframe;
         if(timeframe == PERIOD_CURRENT)
            timeframe = (ENUM_TIMEFRAMES)Period();

         m_atrHandle = iATR(m_symbol, timeframe, InpTrailingAtrPeriod);
         if(m_atrHandle == INVALID_HANDLE)
         {
            if(m_logger != NULL)
               m_logger.Error("Unable to create ATR handle for trailing stop.");

            return false;
         }
      }

      return true;
   }

   void Deinit()
   {
      if(m_atrHandle != INVALID_HANDLE)
      {
         IndicatorRelease(m_atrHandle);
         m_atrHandle = INVALID_HANDLE;
      }
   }

   void Update()
   {
      if(m_pip == NULL || m_executor == NULL)
         return;

      m_pip.Refresh();

      for(int index = PositionsTotal() - 1; index >= 0; index--)
      {
         ulong ticket = PositionGetTicket(index);
         if(ticket == 0)
            continue;

         ManagePosition(ticket);
      }
   }
};

#endif
