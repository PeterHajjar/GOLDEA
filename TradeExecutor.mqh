/*
   TradeExecutor.mqh
   Single responsibility: execute, close, and modify trades with retries, slippage, magic tagging, and broker checks.
*/
#ifndef GOLDEA_TRADE_EXECUTOR_MQH
#define GOLDEA_TRADE_EXECUTOR_MQH

#include <Trade/Trade.mqh>
#include "Config.mqh"
#include "PipCalculator.mqh"
#include "SignalInterface.mqh"

class CTradeExecutor
{
private:
   CTrade          m_trade;
   string          m_symbol;
   long            m_magic;
   CPipCalculator *m_pip;
   CLogger        *m_logger;
   uint            m_lastCloseRetcode;
   double          m_lastCloseFilledVolume;

   bool LoadTick(MqlTick &tick)
   {
      if(SymbolInfoTick(m_symbol, tick))
         return true;

      if(m_logger != NULL)
         m_logger.Error("Unable to read current tick for " + m_symbol + ".");

      return false;
   }

   ENUM_ORDER_TYPE_FILLING FillingMode()
   {
      long fillingMode = 0;

      if(!SymbolInfoInteger(m_symbol, SYMBOL_FILLING_MODE, fillingMode))
         return ORDER_FILLING_RETURN;

      if((fillingMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
         return ORDER_FILLING_FOK;
      if((fillingMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
         return ORDER_FILLING_IOC;

      return ORDER_FILLING_RETURN;
   }

   bool IsSuccessRetcode(uint retcode)
   {
      return (retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_PLACED || retcode == TRADE_RETCODE_DONE_PARTIAL);
   }

   bool IsRetryableRetcode(uint retcode)
   {
      return (retcode == TRADE_RETCODE_REQUOTE
              || retcode == TRADE_RETCODE_PRICE_CHANGED
              || retcode == TRADE_RETCODE_PRICE_OFF
              || retcode == TRADE_RETCODE_TIMEOUT
              || retcode == TRADE_RETCODE_CONNECTION
              || retcode == TRADE_RETCODE_TOO_MANY_REQUESTS
              || retcode == TRADE_RETCODE_LOCKED);
   }

   bool ShouldRetry(uint retcode, int attempt)
   {
      if(attempt > InpMaxExecutionRetries)
         return false;

      return IsRetryableRetcode(retcode);
   }

   bool StopsValidForType(ENUM_POSITION_TYPE positionType, double sl, double tp, string action)
   {
      MqlTick tick;
      if(!LoadTick(tick))
         return false;

      double minDistancePrice = m_pip.PipsToPrice(m_pip.MinimumTradeDistancePips());
      if(minDistancePrice <= 0.0)
         return true;

      bool valid = true;

      if(positionType == POSITION_TYPE_BUY)
      {
         if(sl > 0.0 && sl > tick.bid - minDistancePrice + GOLDEA_DOUBLE_EPSILON)
            valid = false;
         if(tp > 0.0 && tp < tick.bid + minDistancePrice - GOLDEA_DOUBLE_EPSILON)
            valid = false;
      }
      else if(positionType == POSITION_TYPE_SELL)
      {
         if(sl > 0.0 && sl < tick.ask + minDistancePrice - GOLDEA_DOUBLE_EPSILON)
            valid = false;
         if(tp > 0.0 && tp > tick.ask - minDistancePrice + GOLDEA_DOUBLE_EPSILON)
            valid = false;
      }

      if(!valid && m_logger != NULL)
      {
         string message = action + " rejected by local stop/freeze validation. Minimum distance: "
                          + DoubleToString(m_pip.MinimumTradeDistancePips(), 2) + " pips.";
         m_logger.Warn(message);
      }

      return valid;
   }

   bool BuildMarketStops(ESignalDirection signal, double stopLossPips, double takeProfitPips, double &sl, double &tp)
   {
      sl = 0.0;
      tp = 0.0;

      if(m_pip == NULL)
         return false;

      m_pip.Refresh();

      if(stopLossPips > 0.0 && stopLossPips < m_pip.MinimumTradeDistancePips() - GOLDEA_DOUBLE_EPSILON)
      {
         if(m_logger != NULL)
            m_logger.Warn("Stop-loss distance is below broker stop/freeze level. Trade rejected.");

         return false;
      }

      if(takeProfitPips > 0.0 && takeProfitPips < m_pip.MinimumTradeDistancePips() - GOLDEA_DOUBLE_EPSILON)
      {
         if(m_logger != NULL)
            m_logger.Warn("Take-profit distance is below broker stop/freeze level. Trade rejected.");

         return false;
      }

      MqlTick tick;
      if(!LoadTick(tick))
         return false;

      double entryPrice = tick.ask;
      ENUM_POSITION_TYPE positionType = POSITION_TYPE_BUY;

      if(signal == SIGNAL_SELL)
      {
         entryPrice = tick.bid;
         positionType = POSITION_TYPE_SELL;
      }

      if(stopLossPips > 0.0)
      {
         if(signal == SIGNAL_BUY)
            sl = m_pip.NormalizePrice(entryPrice - m_pip.PipsToPrice(stopLossPips));
         else
            sl = m_pip.NormalizePrice(entryPrice + m_pip.PipsToPrice(stopLossPips));
      }

      if(takeProfitPips > 0.0)
      {
         if(signal == SIGNAL_BUY)
            tp = m_pip.NormalizePrice(entryPrice + m_pip.PipsToPrice(takeProfitPips));
         else
            tp = m_pip.NormalizePrice(entryPrice - m_pip.PipsToPrice(takeProfitPips));
      }

      return StopsValidForType(positionType, sl, tp, "Open position");
   }

   bool SendCloseRequest(ulong ticket, double closeVolume, bool closeAll)
   {
      m_lastCloseRetcode = 0;
      m_lastCloseFilledVolume = 0.0;

      if(!PositionSelectByTicket(ticket))
      {
         if(m_logger != NULL)
            m_logger.Warn("Close request ignored. Position ticket not found: " + IntegerToString((long)ticket));

         return false;
      }

      string positionSymbol = PositionGetString(POSITION_SYMBOL);
      long positionMagic = PositionGetInteger(POSITION_MAGIC);

      if(positionSymbol != m_symbol || positionMagic != m_magic)
      {
         if(m_logger != NULL)
            m_logger.Warn("Close request ignored. Position is not managed by this EA.");

         return false;
      }

      double positionVolume = PositionGetDouble(POSITION_VOLUME);
      if(closeAll)
         closeVolume = positionVolume;

      closeVolume = m_pip.NormalizeVolumeDown(closeVolume);

      if(closeVolume <= 0.0)
      {
         if(m_logger != NULL)
            m_logger.Warn("Close volume is not positive.");

         return false;
      }

      if(closeVolume < m_pip.VolumeMin() - GOLDEA_DOUBLE_EPSILON && closeVolume < positionVolume - GOLDEA_DOUBLE_EPSILON)
      {
         if(m_logger != NULL)
            m_logger.Warn("Close volume is below broker minimum.");

         return false;
      }

      if(closeVolume > positionVolume)
         closeVolume = positionVolume;

      ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      ENUM_ORDER_TYPE closeType = ORDER_TYPE_SELL;
      if(positionType == POSITION_TYPE_SELL)
         closeType = ORDER_TYPE_BUY;

      for(int attempt = 0; attempt <= InpMaxExecutionRetries; attempt++)
      {
         MqlTick tick;
         if(!LoadTick(tick))
            return false;

         MqlTradeRequest request;
         MqlTradeResult result;
         ZeroMemory(request);
         ZeroMemory(result);

         request.action       = TRADE_ACTION_DEAL;
         request.position     = ticket;
         request.symbol       = m_symbol;
         request.volume       = closeVolume;
         request.magic        = (ulong)m_magic;
         request.deviation    = (ulong)InpDeviationPoints;
         request.type         = closeType;
         request.price        = (closeType == ORDER_TYPE_SELL ? tick.bid : tick.ask);
         request.type_filling = FillingMode();
         request.comment      = InpTradeComment;

         ResetLastError();
         bool sent = OrderSend(request, result);
         m_lastCloseRetcode = result.retcode;

         if(sent && IsSuccessRetcode(result.retcode))
         {
            double remainingVolume = 0.0;
            if(PositionSelectByTicket(ticket))
               remainingVolume = PositionGetDouble(POSITION_VOLUME);

            m_lastCloseFilledVolume = positionVolume - remainingVolume;
            if(m_lastCloseFilledVolume <= 0.0 && result.volume > 0.0)
               m_lastCloseFilledVolume = result.volume;

            if(m_logger != NULL)
            {
               string message = "Close request completed. Ticket: " + IntegerToString((long)ticket)
                                + ", volume: " + DoubleToString(closeVolume, 8)
                                + ", retcode: " + IntegerToString((int)result.retcode);
               if(result.retcode == TRADE_RETCODE_DONE_PARTIAL)
                  m_logger.Warn("Close request partially filled. " + message);
               else
                  m_logger.Info(message);
            }

            return true;
         }

         if(!ShouldRetry(result.retcode, attempt + 1))
         {
            if(m_logger != NULL)
            {
               string message = "Close request failed. Ticket: " + IntegerToString((long)ticket)
                                + ", retcode: " + IntegerToString((int)result.retcode)
                                + ", last error: " + IntegerToString(GetLastError())
                                + ", broker comment: " + result.comment;
               m_logger.Error(message);
            }

            return false;
         }

         if(m_logger != NULL)
            m_logger.Warn("Retrying close request after broker retcode " + IntegerToString((int)result.retcode) + ".");

         if(InpRetryDelayMs > 0)
            Sleep(InpRetryDelayMs);
      }

      return false;
   }

public:
   CTradeExecutor()
   {
      m_symbol = "";
      m_magic  = 0;
      m_pip    = NULL;
      m_logger = NULL;
      m_lastCloseRetcode = 0;
      m_lastCloseFilledVolume = 0.0;
   }

   bool Init(string symbol, CPipCalculator *pip, CLogger *logger)
   {
      m_symbol = symbol;
      m_magic  = InpMagicNumber;
      m_pip    = pip;
      m_logger = logger;

      if(m_pip == NULL)
      {
         if(m_logger != NULL)
            m_logger.Error("TradeExecutor requires PipCalculator.");

         return false;
      }

      m_trade.SetExpertMagicNumber((ulong)m_magic);
      m_trade.SetDeviationInPoints((ulong)InpDeviationPoints);
      m_trade.SetTypeFillingBySymbol(m_symbol);

      return true;
   }

   bool OpenPosition(ESignalDirection signal, double volume, double stopLossPips, double takeProfitPips)
   {
      if(signal != SIGNAL_BUY && signal != SIGNAL_SELL)
         return false;

      if(volume <= 0.0)
      {
         if(m_logger != NULL)
            m_logger.Error("OpenPosition called with non-positive volume.");

         return false;
      }

      for(int attempt = 0; attempt <= InpMaxExecutionRetries; attempt++)
      {
         double sl = 0.0;
         double tp = 0.0;

         if(!BuildMarketStops(signal, stopLossPips, takeProfitPips, sl, tp))
            return false;

         ResetLastError();
         bool sent = false;

         if(signal == SIGNAL_BUY)
            sent = m_trade.Buy(volume, m_symbol, 0.0, sl, tp, InpTradeComment);
         else
            sent = m_trade.Sell(volume, m_symbol, 0.0, sl, tp, InpTradeComment);

         uint retcode = m_trade.ResultRetcode();

         if(sent && IsSuccessRetcode(retcode))
         {
            string side = (signal == SIGNAL_BUY ? "BUY" : "SELL");
            string message = "Open " + side + " completed. Volume: " + DoubleToString(volume, 8)
                             + ", SL: " + DoubleToString(sl, m_pip.Digits())
                             + ", TP: " + DoubleToString(tp, m_pip.Digits())
                             + ", retcode: " + IntegerToString((int)retcode);

            if(m_logger != NULL)
            {
               if(retcode == TRADE_RETCODE_DONE_PARTIAL)
                  m_logger.Warn("Open position partially filled. " + message);
               else
                  m_logger.Info(message);
            }

            return true;
         }

         if(!ShouldRetry(retcode, attempt + 1))
         {
            if(m_logger != NULL)
            {
               string message = "Open position failed. Retcode: " + IntegerToString((int)retcode)
                                + ", last error: " + IntegerToString(GetLastError())
                                + ", broker comment: " + m_trade.ResultRetcodeDescription();
               m_logger.Error(message);
            }

            return false;
         }

         if(m_logger != NULL)
            m_logger.Warn("Retrying open position after broker retcode " + IntegerToString((int)retcode) + ".");

         if(InpRetryDelayMs > 0)
            Sleep(InpRetryDelayMs);
      }

      return false;
   }

   bool ModifyPosition(ulong ticket, double sl, double tp)
   {
      if(!PositionSelectByTicket(ticket))
      {
         if(m_logger != NULL)
            m_logger.Warn("Modify request ignored. Position ticket not found: " + IntegerToString((long)ticket));

         return false;
      }

      string positionSymbol = PositionGetString(POSITION_SYMBOL);
      long positionMagic = PositionGetInteger(POSITION_MAGIC);

      if(positionSymbol != m_symbol || positionMagic != m_magic)
      {
         if(m_logger != NULL)
            m_logger.Warn("Modify request ignored. Position is not managed by this EA.");

         return false;
      }

      ENUM_POSITION_TYPE positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      sl = (sl > 0.0 ? m_pip.NormalizePrice(sl) : 0.0);
      tp = (tp > 0.0 ? m_pip.NormalizePrice(tp) : 0.0);

      if(!StopsValidForType(positionType, sl, tp, "Modify position"))
         return false;

      for(int attempt = 0; attempt <= InpMaxExecutionRetries; attempt++)
      {
         MqlTradeRequest request;
         MqlTradeResult result;
         ZeroMemory(request);
         ZeroMemory(result);

         request.action   = TRADE_ACTION_SLTP;
         request.position = ticket;
         request.symbol   = m_symbol;
         request.magic    = (ulong)m_magic;
         request.sl       = sl;
         request.tp       = tp;

         ResetLastError();
         bool sent = OrderSend(request, result);

         if(sent && IsSuccessRetcode(result.retcode))
         {
            if(m_logger != NULL)
            {
               string message = "Position modified. Ticket: " + IntegerToString((long)ticket)
                                + ", SL: " + DoubleToString(sl, m_pip.Digits())
                                + ", TP: " + DoubleToString(tp, m_pip.Digits())
                                + ", retcode: " + IntegerToString((int)result.retcode);
               m_logger.Info(message);
            }

            return true;
         }

         if(!ShouldRetry(result.retcode, attempt + 1))
         {
            if(m_logger != NULL)
            {
               string message = "Modify position failed. Ticket: " + IntegerToString((long)ticket)
                                + ", retcode: " + IntegerToString((int)result.retcode)
                                + ", last error: " + IntegerToString(GetLastError())
                                + ", broker comment: " + result.comment;
               m_logger.Error(message);
            }

            return false;
         }

         if(m_logger != NULL)
            m_logger.Warn("Retrying modify request after broker retcode " + IntegerToString((int)result.retcode) + ".");

         if(InpRetryDelayMs > 0)
            Sleep(InpRetryDelayMs);
      }

      return false;
   }

   bool ClosePosition(ulong ticket)
   {
      return SendCloseRequest(ticket, 0.0, true);
   }

   bool ClosePartialPosition(ulong ticket, double volume)
   {
      return SendCloseRequest(ticket, volume, false);
   }

   uint LastCloseRetcode()
   {
      return m_lastCloseRetcode;
   }

   double LastCloseFilledVolume()
   {
      return m_lastCloseFilledVolume;
   }

   int CountManagedPositions()
   {
      int count = 0;

      for(int index = PositionsTotal() - 1; index >= 0; index--)
      {
         ulong ticket = PositionGetTicket(index);
         if(ticket == 0)
            continue;

         string positionSymbol = PositionGetString(POSITION_SYMBOL);
         long positionMagic = PositionGetInteger(POSITION_MAGIC);

         if(positionSymbol == m_symbol && positionMagic == m_magic)
            count++;
      }

      return count;
   }

   bool HasManagedPosition()
   {
      return (CountManagedPositions() > 0);
   }
};

#endif
