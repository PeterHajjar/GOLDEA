# GOLDEA Enterprise EA Skeleton

This folder contains a modular MQL5 Expert Advisor foundation for XAUUSD. The entry file is `EA_Main.mq5`; strategy logic is intentionally absent and isolated behind `SignalInterface.mqh`.

## Files

- `EA_Main.mq5`: EA entry points and orchestration.
- `Config.mqh`: grouped inputs and OnInit validation helper.
- `Logger.mqh`: centralized INFO/WARN/ERROR logging.
- `PipCalculator.mqh`: symbol-derived pip size, pip value, point value, spread, stop/freeze levels, and volume normalization.
- `RiskManager.mqh`: fixed lot and equity-risk position sizing.
- `TradeExecutor.mqh`: trade open, close, partial close, SL/TP modification, retries, deviation, and magic tagging.
- `TradeManager.mqh`: breakeven, trailing stop, partial close, and multi-target position management.
- `SpreadFilter.mqh`: entry-only spread filter.
- `SessionFilter.mqh`: entry-only broker-server session filter.
- `SignalInterface.mqh`: `CSignalBase` plus `CSignalDummy`, which always returns `SIGNAL_NONE`.

## Plugging In A Real Strategy

Create a new `.mqh` file with a class that inherits `CSignalBase`, then override `GetSignal()`. Keep indicator and entry rules inside that class. If the strategy needs custom SL/TP distances, override `StopLossPips()` and `TakeProfitPips()`.

Example:

```mql5
#include "SignalInterface.mqh"

class CMyGoldSignal : public CSignalBase
{
public:
   virtual ESignalDirection GetSignal(string symbol)
   {
      // Return SIGNAL_BUY, SIGNAL_SELL, or SIGNAL_NONE.
      return SIGNAL_NONE;
   }

   virtual double StopLossPips()
   {
      return 100.0;
   }

   virtual double TakeProfitPips()
   {
      return 200.0;
   }
};
```

Then include the new signal file in `EA_Main.mq5` and replace the global `CSignalDummy g_signal;` with your signal class. The risk manager, trade executor, filters, pip calculator, and trade manager should not need strategy-specific edits.
