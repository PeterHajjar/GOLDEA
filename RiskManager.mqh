/*
   RiskManager.mqh
   Single responsibility: calculate and validate broker-normalized position size.
*/
#ifndef GOLDEA_RISK_MANAGER_MQH
#define GOLDEA_RISK_MANAGER_MQH

#include "Config.mqh"
#include "PipCalculator.mqh"

class CRiskManager
{
private:
   string          m_symbol;
   CPipCalculator *m_pip;
   CLogger        *m_logger;

   bool FinalizeVolume(double requestedVolume, double &volume)
   {
      volume = 0.0;

      if(m_pip == NULL)
         return false;

      m_pip.Refresh();

      if(requestedVolume <= 0.0)
      {
         if(m_logger != NULL)
            m_logger.Error("Calculated volume is not positive.");

         return false;
      }

      if(requestedVolume < m_pip.VolumeMin() - GOLDEA_DOUBLE_EPSILON)
      {
         if(m_logger != NULL)
            m_logger.Warn("Calculated volume " + DoubleToString(requestedVolume, 8) + " is below broker minimum " + DoubleToString(m_pip.VolumeMin(), 8) + ". Trade rejected.");

         return false;
      }

      double cappedVolume = requestedVolume;

      if(cappedVolume > m_pip.VolumeMax())
      {
         if(m_logger != NULL)
            m_logger.Warn("Calculated volume exceeds broker maximum. Capping to " + DoubleToString(m_pip.VolumeMax(), 8) + ".");

         cappedVolume = m_pip.VolumeMax();
      }

      double normalizedVolume = m_pip.NormalizeVolumeDown(cappedVolume);

      if(normalizedVolume < m_pip.VolumeMin() - GOLDEA_DOUBLE_EPSILON)
      {
         if(m_logger != NULL)
            m_logger.Warn("Normalized volume is below broker minimum. Trade rejected.");

         return false;
      }

      if(normalizedVolume > m_pip.VolumeMax() + GOLDEA_DOUBLE_EPSILON)
      {
         if(m_logger != NULL)
            m_logger.Warn("Normalized volume is above broker maximum. Trade rejected.");

         return false;
      }

      volume = normalizedVolume;
      return true;
   }

public:
   CRiskManager()
   {
      m_symbol = "";
      m_pip    = NULL;
      m_logger = NULL;
   }

   bool Init(string symbol, CPipCalculator *pip, CLogger *logger)
   {
      m_symbol = symbol;
      m_pip    = pip;
      m_logger = logger;

      if(m_pip == NULL)
      {
         if(m_logger != NULL)
            m_logger.Error("RiskManager requires PipCalculator.");

         return false;
      }

      return true;
   }

   bool CalculateLotSize(double stopLossPips, double &volume)
   {
      volume = 0.0;

      if(m_pip == NULL)
         return false;

      if(InpRiskMode == RISK_MODE_FIXED_LOT)
      {
         if(!FinalizeVolume(InpFixedLotSize, volume))
            return false;

         if(MathAbs(volume - InpFixedLotSize) > GOLDEA_DOUBLE_EPSILON && m_logger != NULL)
         {
            m_logger.Warn("Fixed-lot volume adjusted to broker volume step. Requested: "
                          + DoubleToString(InpFixedLotSize, 8)
                          + ", rounded: " + DoubleToString(volume, 8));
         }

         if(m_logger != NULL)
            m_logger.Info("Fixed-lot risk mode selected. Volume: " + DoubleToString(volume, 8));

         return true;
      }

      if(stopLossPips <= 0.0)
      {
         if(m_logger != NULL)
            m_logger.Error("Risk percent mode requires a positive stop-loss distance in pips.");

         return false;
      }

      double pipValue = m_pip.PipValuePerLot();
      if(pipValue <= 0.0)
      {
         if(m_logger != NULL)
            m_logger.Error("Pip value per lot is not positive. Cannot size trade.");

         return false;
      }

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(equity <= 0.0)
      {
         if(m_logger != NULL)
            m_logger.Error("Account equity is not positive. Cannot size trade.");

         return false;
      }

      double riskAmount = equity * (InpRiskPercent / 100.0);
      double rawVolume = riskAmount / (stopLossPips * pipValue);

      if(!FinalizeVolume(rawVolume, volume))
         return false;

      if(m_logger != NULL)
      {
         string message = "Risk percent mode selected. Equity: " + DoubleToString(equity, 2)
                          + ", risk amount: " + DoubleToString(riskAmount, 2)
                          + ", stop pips: " + DoubleToString(stopLossPips, 2)
                          + ", volume: " + DoubleToString(volume, 8);
         m_logger.Info(message);
      }

      return true;
   }
};

#endif
