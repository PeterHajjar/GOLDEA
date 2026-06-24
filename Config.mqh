/*
   Config.mqh
   Single responsibility: declare EA inputs and validate static input values during OnInit.
*/
#ifndef GOLDEA_CONFIG_MQH
#define GOLDEA_CONFIG_MQH

#include "Logger.mqh"

#define GOLDEA_MAX_TARGETS 3
#define GOLDEA_DOUBLE_EPSILON 0.00000001

enum ERiskSizingMode
{
   RISK_MODE_FIXED_LOT      = 0,
   RISK_MODE_EQUITY_PERCENT = 1
};

enum ETrailingStopMode
{
   TRAILING_MODE_STEP = 0,
   TRAILING_MODE_ATR  = 1
};

enum EPartialCloseMode
{
   PARTIAL_MODE_R_MULTIPLE = 0,
   PARTIAL_MODE_PIPS       = 1
};

input group "General"
input long      InpMagicNumber         = 2026062301;
input string    InpTradeComment        = "GOLDEA Skeleton";
input int       InpTimerSeconds        = 30;
input ELogLevel InpLogLevel            = LOG_LEVEL_INFO;
input bool      InpOnePositionPerSymbol = true;

input group "Execution"
input int InpDeviationPoints      = 50;
input int InpMaxExecutionRetries  = 3;
input int InpRetryDelayMs         = 250;

input group "Risk"
input ERiskSizingMode InpRiskMode     = RISK_MODE_FIXED_LOT;
input double          InpFixedLotSize = 0.10;
input double          InpRiskPercent  = 1.00;

input group "Strategy Placeholder"
input bool   InpAllowBuySignals        = true;
input bool   InpAllowSellSignals       = true;
input double InpStrategyStopLossPips   = 100.0;
input double InpStrategyTakeProfitPips = 200.0;

input group "Filters"
input bool   InpEnableSpreadFilter = true;
input double InpMaxSpreadPips      = 5.0;
input bool   InpEnableSessionFilter = false;
input int    InpSessionStartHour    = 0;
input int    InpSessionStartMinute  = 0;
input int    InpSessionEndHour      = 23;
input int    InpSessionEndMinute    = 59;
input bool   InpAllowMonday         = true;
input bool   InpAllowTuesday        = true;
input bool   InpAllowWednesday      = true;
input bool   InpAllowThursday       = true;
input bool   InpAllowFriday         = true;
input bool   InpAllowSaturday       = false;
input bool   InpAllowSunday         = false;

input group "Trade Management"
input bool              InpEnableBreakeven          = false;
input double            InpBreakevenTriggerPips     = 50.0;
input double            InpBreakevenOffsetPips      = 2.0;
input bool              InpEnableTrailingStop       = false;
input ETrailingStopMode InpTrailingMode             = TRAILING_MODE_STEP;
input double            InpTrailingStartPips        = 75.0;
input double            InpTrailingDistancePips     = 50.0;
input double            InpTrailingStepPips         = 10.0;
input ENUM_TIMEFRAMES   InpTrailingAtrTimeframe     = PERIOD_CURRENT;
input int               InpTrailingAtrPeriod        = 14;
input double            InpTrailingAtrMultiplier    = 2.0;
input bool              InpEnablePartialClose       = false;
input EPartialCloseMode InpPartialCloseMode         = PARTIAL_MODE_R_MULTIPLE;
input double            InpPartialClosePercent      = 50.0;
input double            InpPartialCloseTriggerR     = 1.0;
input double            InpPartialCloseTriggerPips  = 100.0;
input bool              InpEnableMultiTargets       = false;
input int               InpTargetCount              = 2;
input EPartialCloseMode InpTargetTriggerMode        = PARTIAL_MODE_R_MULTIPLE;
input double            InpTarget1Trigger           = 1.0;
input double            InpTarget1ClosePercent      = 50.0;
input double            InpTarget2Trigger           = 2.0;
input double            InpTarget2ClosePercent      = 25.0;
input double            InpTarget3Trigger           = 3.0;
input double            InpTarget3ClosePercent      = 25.0;

class CConfigValidator
{
private:
   bool Check(bool condition, string message, CLogger *logger)
   {
      if(condition)
         return true;

      if(logger != NULL)
         logger.Error(message);

      return false;
   }

   bool CheckPercent(double value, string name, CLogger *logger)
   {
      return Check(value > 0.0 && value <= 100.0, name + " must be greater than 0 and less than or equal to 100.", logger);
   }

   bool CheckPositive(double value, string name, CLogger *logger)
   {
      return Check(value > 0.0, name + " must be greater than 0.", logger);
   }

public:
   bool Validate(CLogger *logger)
   {
      bool ok = true;

      if(!Check(InpMagicNumber > 0, "InpMagicNumber must be greater than 0.", logger))
         ok = false;
      if(!Check(InpTimerSeconds > 0, "InpTimerSeconds must be greater than 0.", logger))
         ok = false;
      if(!Check(InpDeviationPoints >= 0, "InpDeviationPoints must be zero or greater.", logger))
         ok = false;
      if(!Check(InpMaxExecutionRetries >= 0, "InpMaxExecutionRetries must be zero or greater.", logger))
         ok = false;
      if(!Check(InpRetryDelayMs >= 0, "InpRetryDelayMs must be zero or greater.", logger))
         ok = false;

      if(!CheckPositive(InpFixedLotSize, "InpFixedLotSize", logger))
         ok = false;
      if(!CheckPercent(InpRiskPercent, "InpRiskPercent", logger))
         ok = false;
      if(!CheckPositive(InpStrategyStopLossPips, "InpStrategyStopLossPips", logger))
         ok = false;
      if(!Check(InpStrategyTakeProfitPips >= 0.0, "InpStrategyTakeProfitPips must be zero or greater.", logger))
         ok = false;

      if(!Check(InpMaxSpreadPips >= 0.0, "InpMaxSpreadPips must be zero or greater.", logger))
         ok = false;
      if(!Check(InpSessionStartHour >= 0 && InpSessionStartHour <= 23, "InpSessionStartHour must be between 0 and 23.", logger))
         ok = false;
      if(!Check(InpSessionEndHour >= 0 && InpSessionEndHour <= 23, "InpSessionEndHour must be between 0 and 23.", logger))
         ok = false;
      if(!Check(InpSessionStartMinute >= 0 && InpSessionStartMinute <= 59, "InpSessionStartMinute must be between 0 and 59.", logger))
         ok = false;
      if(!Check(InpSessionEndMinute >= 0 && InpSessionEndMinute <= 59, "InpSessionEndMinute must be between 0 and 59.", logger))
         ok = false;

      if(InpEnableSessionFilter)
      {
         bool anyDayAllowed = InpAllowMonday || InpAllowTuesday || InpAllowWednesday || InpAllowThursday || InpAllowFriday || InpAllowSaturday || InpAllowSunday;
         if(!Check(anyDayAllowed, "At least one session day must be enabled when InpEnableSessionFilter is true.", logger))
            ok = false;
      }

      if(!Check(InpBreakevenTriggerPips >= 0.0, "InpBreakevenTriggerPips must be zero or greater.", logger))
         ok = false;
      if(!Check(InpBreakevenOffsetPips >= 0.0, "InpBreakevenOffsetPips must be zero or greater.", logger))
         ok = false;
      if(!Check(InpTrailingStartPips >= 0.0, "InpTrailingStartPips must be zero or greater.", logger))
         ok = false;
      if(!CheckPositive(InpTrailingDistancePips, "InpTrailingDistancePips", logger))
         ok = false;
      if(!CheckPositive(InpTrailingStepPips, "InpTrailingStepPips", logger))
         ok = false;
      if(!Check(InpTrailingAtrPeriod > 0, "InpTrailingAtrPeriod must be greater than 0.", logger))
         ok = false;
      if(!CheckPositive(InpTrailingAtrMultiplier, "InpTrailingAtrMultiplier", logger))
         ok = false;

      if(!CheckPercent(InpPartialClosePercent, "InpPartialClosePercent", logger))
         ok = false;
      if(!CheckPositive(InpPartialCloseTriggerR, "InpPartialCloseTriggerR", logger))
         ok = false;
      if(!CheckPositive(InpPartialCloseTriggerPips, "InpPartialCloseTriggerPips", logger))
         ok = false;
      if(!Check(InpTargetCount >= 1 && InpTargetCount <= GOLDEA_MAX_TARGETS, "InpTargetCount must be between 1 and GOLDEA_MAX_TARGETS.", logger))
         ok = false;
      if(!CheckPositive(InpTarget1Trigger, "InpTarget1Trigger", logger))
         ok = false;
      if(!CheckPercent(InpTarget1ClosePercent, "InpTarget1ClosePercent", logger))
         ok = false;
      if(!CheckPositive(InpTarget2Trigger, "InpTarget2Trigger", logger))
         ok = false;
      if(!CheckPercent(InpTarget2ClosePercent, "InpTarget2ClosePercent", logger))
         ok = false;
      if(!CheckPositive(InpTarget3Trigger, "InpTarget3Trigger", logger))
         ok = false;
      if(!CheckPercent(InpTarget3ClosePercent, "InpTarget3ClosePercent", logger))
         ok = false;

      return ok;
   }
};

#endif
