/*
   EA_Main.mq5
   Single responsibility: Expert Advisor entry points and high-level orchestration only.
*/
#property strict
#property version   "1.00"
#property description "GOLDEA enterprise EA skeleton for XAUUSD with isolated strategy interface."

#include "Logger.mqh"
#include "Config.mqh"
#include "PipCalculator.mqh"
#include "SignalInterface.mqh"
#include "RiskManager.mqh"
#include "TradeExecutor.mqh"
#include "TradeManager.mqh"
#include "SpreadFilter.mqh"
#include "SessionFilter.mqh"

CLogger        g_logger;
CPipCalculator g_pipCalculator;
CRiskManager   g_riskManager;
CTradeExecutor g_tradeExecutor;
CTradeManager  g_tradeManager;
CSpreadFilter  g_spreadFilter;
CSessionFilter g_sessionFilter;
CSignalBase   *g_signal = NULL;
bool           g_initialized = false;

bool TradingEnvironmentReady()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      return false;

   return true;
}

int OnInit()
{
   g_logger.Init(InpLogLevel);
   g_logger.Info("Initializing GOLDEA EA skeleton on " + _Symbol + ".");

   CConfigValidator configValidator;
   if(!configValidator.Validate(GetPointer(g_logger)))
      return INIT_PARAMETERS_INCORRECT;

   if(!g_pipCalculator.Init(_Symbol, GetPointer(g_logger)))
      return INIT_FAILED;

   if(!g_riskManager.Init(_Symbol, GetPointer(g_pipCalculator), GetPointer(g_logger)))
      return INIT_FAILED;

   if(!g_tradeExecutor.Init(_Symbol, GetPointer(g_pipCalculator), GetPointer(g_logger)))
      return INIT_FAILED;

   if(!g_tradeManager.Init(_Symbol, GetPointer(g_pipCalculator), GetPointer(g_tradeExecutor), GetPointer(g_logger)))
      return INIT_FAILED;

   if(!g_spreadFilter.Init(GetPointer(g_pipCalculator), GetPointer(g_logger)))
      return INIT_FAILED;

   if(!g_sessionFilter.Init(GetPointer(g_logger)))
      return INIT_FAILED;

   if(g_signal != NULL)
   {
      delete g_signal;
      g_signal = NULL;
   }

   g_signal = new CSignalDummy();
   if(g_signal == NULL)
   {
      g_logger.Error("Unable to allocate signal module.");
      return INIT_FAILED;
   }

   if(!g_signal.Init(GetPointer(g_logger)))
   {
      delete g_signal;
      g_signal = NULL;
      return INIT_FAILED;
   }

   if(!EventSetTimer(InpTimerSeconds))
      g_logger.Warn("Unable to set timer. OnTick and OnTrade will still run.");

   g_initialized = true;
   g_logger.Info("Initialization complete. Active signal module: " + g_signal.Name() + ".");

   return INIT_SUCCEEDED;
}

void OnDeinit(const int reason)
{
   EventKillTimer();
   g_tradeManager.Deinit();
   g_initialized = false;

   if(g_signal != NULL)
   {
      delete g_signal;
      g_signal = NULL;
   }

   g_logger.Info("GOLDEA EA skeleton deinitialized. Reason: " + IntegerToString(reason) + ".");
}

void OnTick()
{
   if(!g_initialized)
      return;

   g_tradeManager.Update();

   if(!TradingEnvironmentReady())
      return;

   if(InpOnePositionPerSymbol && g_tradeExecutor.HasManagedPosition())
      return;

   if(!g_sessionFilter.IsEntryAllowed())
      return;

   if(!g_spreadFilter.IsEntryAllowed())
      return;

   if(g_signal == NULL)
      return;

   ESignalDirection signal = g_signal.GetSignal(_Symbol);
   if(signal == SIGNAL_NONE)
      return;

   if(signal == SIGNAL_BUY && !InpAllowBuySignals)
      return;
   if(signal == SIGNAL_SELL && !InpAllowSellSignals)
      return;

   double stopLossPips = g_signal.StopLossPips();
   double takeProfitPips = g_signal.TakeProfitPips();
   double volume = 0.0;

   if(!g_riskManager.CalculateLotSize(stopLossPips, volume))
      return;

   g_tradeExecutor.OpenPosition(signal, volume, stopLossPips, takeProfitPips);
}

void OnTrade()
{
   if(!g_initialized)
      return;

   g_tradeManager.Update();
}

void OnTimer()
{
   if(!g_initialized)
      return;

   g_pipCalculator.Refresh();
   g_tradeManager.Update();
}
