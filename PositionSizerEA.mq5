//+------------------------------------------------------------------+
//|                                           PositionSizerEA.mq5    |
//|                        Risk-Based Position Sizer & Order Placer   |
//|                                                                    |
//|  Two modes: Market Order & Limit Order                             |
//|  Auto-calculates lot size from Risk %, SL distance, tick value     |
//|  Graphical panel with Buy/Sell buttons and confirmation dialog     |
//|  Break-Even SL: moves SL to entry when profit trigger is reached   |
//+------------------------------------------------------------------+
#property copyright "Position Sizer EA"
#property version   "1.10"
#property description "Risk-based position sizing with Market & Limit order modes + Break-Even SL"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Enums                                                              |
//+------------------------------------------------------------------+
enum ENUM_ORDER_MODE
  {
   MODE_MARKET = 0,  // Market Order
   MODE_LIMIT  = 1   // Limit Order
  };

//+------------------------------------------------------------------+
//| Input Parameters (also shown in EA Inputs tab)                     |
//+------------------------------------------------------------------+
input group "=== General Settings ==="
input ENUM_ORDER_MODE InpDefaultMode     = MODE_MARKET; // Default Order Mode
input double           InpDefaultRiskPct  = 1.0;        // Default Risk % of Balance
input color            InpPanelColor      = clrDarkSlateGray; // Panel Background Color
input color            InpTextColor       = clrWhite;         // Panel Text Color
input color            InpBuyColor        = clrDodgerBlue;    // Buy Button Color
input color            InpSellColor       = clrCrimson;       // Sell Button Color
input int              InpPanelX          = 20;         // Panel X Position
input int              InpPanelY          = 50;         // Panel Y Position

input group "=== Market Mode Defaults ==="
input int              InpDefaultSLTicks  = 100;        // Default SL (ticks)
input int              InpDefaultTPTicks  = 0;          // Default TP (ticks, 0=none)

input group "=== Limit Mode Defaults ==="
input double           InpDefaultEntry    = 0.0;        // Default Entry Price (0=current)
input double           InpDefaultSLPrice  = 0.0;        // Default SL Price
input double           InpDefaultTPPrice  = 0.0;        // Default TP Price (0=none)

input group "=== Break-Even Defaults ==="
input bool             InpDefaultBEOn     = false;       // Break-Even enabled by default
input int              InpDefaultBETicks  = 50;          // BE Trigger (ticks in profit)
input double           InpDefaultBEPrice  = 0.0;         // BE Trigger Price (0=use ticks)

//+------------------------------------------------------------------+
//| Global Variables                                                   |
//+------------------------------------------------------------------+
CTrade trade;

// Panel dimensions
const int PANEL_W        = 320;
const int PANEL_H        = 576;
const int FIELD_H        = 22;
const int LABEL_W        = 130;
const int INPUT_W        = 160;
const int BTN_W          = 140;
const int BTN_H          = 32;
const int MARGIN         = 10;
const int ROW_H          = 28;

// State
ENUM_ORDER_MODE g_mode;
double g_riskPct;
int    g_slTicks;
int    g_tpTicks;
double g_entryPrice;
double g_slPrice;
double g_tpPrice;
bool   g_confirmShowing = false;
int    g_confirmDirection = 0; // 1=buy, -1=sell

// Break-Even state
bool   g_beEnabled;
int    g_beTicks;
double g_bePrice;

// Object name prefixes
const string PFX = "PS_";

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
  {
   // Initialize state from inputs
   g_mode       = InpDefaultMode;
   g_riskPct    = InpDefaultRiskPct;
   g_slTicks    = InpDefaultSLTicks;
   g_tpTicks    = InpDefaultTPTicks;
   g_entryPrice = InpDefaultEntry;
   g_slPrice    = InpDefaultSLPrice;
   g_tpPrice    = InpDefaultTPPrice;

   // Break-Even
   g_beEnabled  = InpDefaultBEOn;
   g_beTicks    = InpDefaultBETicks;
   g_bePrice    = InpDefaultBEPrice;

   // Enable chart events
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);

   // Build panel
   CreatePanel();
   UpdatePanel();

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PFX);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
  {
   UpdatePanel();
   CheckBreakEven();
  }

//+------------------------------------------------------------------+
//| Chart event handler                                                |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      HandleClick(sparam);
      ChartRedraw();
     }
   // Handle edit field changes
   if(id == CHARTEVENT_OBJECT_ENDEDIT)
     {
      HandleEditEnd(sparam);
      UpdatePanel();
      ChartRedraw();
     }
  }

//+------------------------------------------------------------------+
//| Create all panel objects                                           |
//+------------------------------------------------------------------+
void CreatePanel()
  {
   int x = InpPanelX;
   int y = InpPanelY;

   // --- Background ---
   CreateRect(PFX + "BG", x, y, PANEL_W, PANEL_H, InpPanelColor);

   // --- Title ---
   int row = y + MARGIN;
   CreateLabel(PFX + "Title", x + MARGIN, row, "POSITION SIZER EA", InpTextColor, 11, true);
   row += ROW_H + 4;

   // --- Mode Toggle Buttons ---
   CreateButton(PFX + "BtnMarket", x + MARGIN, row, BTN_W, BTN_H, "MARKET MODE",
                (g_mode == MODE_MARKET) ? clrDodgerBlue : clrGray);
   CreateButton(PFX + "BtnLimit", x + MARGIN + BTN_W + 10, row, BTN_W, BTN_H, "LIMIT MODE",
                (g_mode == MODE_LIMIT) ? clrDodgerBlue : clrGray);
   row += BTN_H + 10;

   // --- Separator ---
   CreateRect(PFX + "Sep1", x + MARGIN, row, PANEL_W - 2 * MARGIN, 1, clrGray);
   row += 8;

   // --- Account Info ---
   CreateLabel(PFX + "LblAcct", x + MARGIN, row, "Account Balance:", InpTextColor, 9, false);
   CreateLabel(PFX + "ValAcct", x + MARGIN + LABEL_W + 10, row, "---", clrLime, 9, true);
   row += ROW_H;

   CreateLabel(PFX + "LblSymbol", x + MARGIN, row, "Symbol:", InpTextColor, 9, false);
   CreateLabel(PFX + "ValSymbol", x + MARGIN + LABEL_W + 10, row, _Symbol, clrLime, 9, true);
   row += ROW_H;

   CreateLabel(PFX + "LblContract", x + MARGIN, row, "Contract Size:", InpTextColor, 9, false);
   CreateLabel(PFX + "ValContract", x + MARGIN + LABEL_W + 10, row, "---", clrLime, 9, true);
   row += ROW_H;

   CreateLabel(PFX + "LblTickInfo", x + MARGIN, row, "Tick Size / Value:", InpTextColor, 9, false);
   CreateLabel(PFX + "ValTickInfo", x + MARGIN + LABEL_W + 10, row, "---", clrLime, 9, true);
   row += ROW_H;

   // --- Separator ---
   CreateRect(PFX + "Sep2", x + MARGIN, row, PANEL_W - 2 * MARGIN, 1, clrGray);
   row += 8;

   // --- Input Fields ---
   // Risk %
   CreateLabel(PFX + "LblRisk", x + MARGIN, row, "Risk %:", InpTextColor, 9, false);
   CreateEdit(PFX + "EdtRisk", x + MARGIN + LABEL_W + 10, row, INPUT_W, FIELD_H,
              DoubleToString(g_riskPct, 2));
   row += ROW_H;

   // -- Market-specific fields --
   CreateLabel(PFX + "LblSLTicks", x + MARGIN, row, "SL (ticks):", InpTextColor, 9, false);
   CreateEdit(PFX + "EdtSLTicks", x + MARGIN + LABEL_W + 10, row, INPUT_W, FIELD_H,
              IntegerToString(g_slTicks));
   row += ROW_H;

   CreateLabel(PFX + "LblTPTicks", x + MARGIN, row, "TP (ticks, 0=none):", InpTextColor, 9, false);
   CreateEdit(PFX + "EdtTPTicks", x + MARGIN + LABEL_W + 10, row, INPUT_W, FIELD_H,
              IntegerToString(g_tpTicks));
   row += ROW_H;

   // -- Limit-specific fields --
   CreateLabel(PFX + "LblEntry", x + MARGIN, row, "Entry Price:", InpTextColor, 9, false);
   CreateEdit(PFX + "EdtEntry", x + MARGIN + LABEL_W + 10, row, INPUT_W, FIELD_H,
              DoubleToString(g_entryPrice, _Digits));
   row += ROW_H;

   CreateLabel(PFX + "LblSLPrice", x + MARGIN, row, "SL Price:", InpTextColor, 9, false);
   CreateEdit(PFX + "EdtSLPrice", x + MARGIN + LABEL_W + 10, row, INPUT_W, FIELD_H,
              DoubleToString(g_slPrice, _Digits));
   row += ROW_H;

   CreateLabel(PFX + "LblTPPrice", x + MARGIN, row, "TP Price (0=none):", InpTextColor, 9, false);
   CreateEdit(PFX + "EdtTPPrice", x + MARGIN + LABEL_W + 10, row, INPUT_W, FIELD_H,
              DoubleToString(g_tpPrice, _Digits));
   row += ROW_H;

   // --- Separator ---
   CreateRect(PFX + "Sep3", x + MARGIN, row, PANEL_W - 2 * MARGIN, 1, clrGray);
   row += 8;

   // --- Calculated Info ---
   CreateLabel(PFX + "LblCalcLots", x + MARGIN, row, "Lot Size:", InpTextColor, 9, false);
   CreateLabel(PFX + "ValCalcLots", x + MARGIN + LABEL_W + 10, row, "---", clrYellow, 9, true);
   row += ROW_H;

   CreateLabel(PFX + "LblCalcRisk", x + MARGIN, row, "Risk Amount:", InpTextColor, 9, false);
   CreateLabel(PFX + "ValCalcRisk", x + MARGIN + LABEL_W + 10, row, "---", clrYellow, 9, true);
   row += ROW_H;

   CreateLabel(PFX + "LblWarn", x + MARGIN, row, "", clrOrangeRed, 8, false);
   row += ROW_H;

   // --- Separator ---
   CreateRect(PFX + "Sep4", x + MARGIN, row, PANEL_W - 2 * MARGIN, 1, clrGray);
   row += 8;

   // --- Break-Even Section ---
   CreateLabel(PFX + "LblBETitle", x + MARGIN, row, "BREAK EVEN", InpTextColor, 9, true);
   CreateButton(PFX + "BtnBE", x + MARGIN + 100, row - 2, 70, 24,
                g_beEnabled ? "ON" : "OFF",
                g_beEnabled ? clrGreen : clrGray);
   row += ROW_H;

   CreateLabel(PFX + "LblBETicks", x + MARGIN, row, "BE Trigger (ticks):", InpTextColor, 9, false);
   CreateEdit(PFX + "EdtBETicks", x + MARGIN + LABEL_W + 10, row, INPUT_W, FIELD_H,
              IntegerToString(g_beTicks));
   row += ROW_H;

   CreateLabel(PFX + "LblBEPrice", x + MARGIN, row, "BE Trigger Price:", InpTextColor, 9, false);
   CreateEdit(PFX + "EdtBEPrice", x + MARGIN + LABEL_W + 10, row, INPUT_W, FIELD_H,
              (g_bePrice > 0) ? DoubleToString(g_bePrice, _Digits) : "0");
   row += ROW_H;

   CreateLabel(PFX + "LblBEStatus", x + MARGIN, row, "BE Status:", InpTextColor, 9, false);
   CreateLabel(PFX + "ValBEStatus", x + MARGIN + LABEL_W + 10, row,
              g_beEnabled ? "Monitoring..." : "Disabled",
              g_beEnabled ? clrLime : clrGray, 9, false);
   row += ROW_H;

   // --- Separator ---
   CreateRect(PFX + "Sep5", x + MARGIN, row, PANEL_W - 2 * MARGIN, 1, clrGray);
   row += 8;

   // --- Buy / Sell Buttons ---
   CreateButton(PFX + "BtnBuy", x + MARGIN, row, BTN_W, BTN_H + 4, "BUY", InpBuyColor);
   CreateButton(PFX + "BtnSell", x + MARGIN + BTN_W + 10, row, BTN_W, BTN_H + 4, "SELL", InpSellColor);
   row += BTN_H + 14;

   // --- Confirmation overlay (hidden by default) ---
   CreateRect(PFX + "ConfBG", x + 10, y + PANEL_H / 2 - 70, PANEL_W - 20, 140, clrBlack);
   CreateLabel(PFX + "ConfText1", x + 20, y + PANEL_H / 2 - 60, "", clrWhite, 9, false);
   CreateLabel(PFX + "ConfText2", x + 20, y + PANEL_H / 2 - 40, "", clrWhite, 9, false);
   CreateLabel(PFX + "ConfText3", x + 20, y + PANEL_H / 2 - 20, "", clrWhite, 9, false);
   CreateLabel(PFX + "ConfText4", x + 20, y + PANEL_H / 2 + 0, "", clrYellow, 9, true);
   CreateLabel(PFX + "ConfText5", x + 20, y + PANEL_H / 2 + 20, "", clrLime, 8, false);
   CreateButton(PFX + "BtnConfirm", x + 20, y + PANEL_H / 2 + 42, 120, BTN_H, "CONFIRM", clrGreen);
   CreateButton(PFX + "BtnCancel", x + 160, y + PANEL_H / 2 + 42, 120, BTN_H, "CANCEL", clrGray);

   ShowConfirmation(false);
   SetModeVisibility();
  }

//+------------------------------------------------------------------+
//| Update panel values on each tick                                   |
//+------------------------------------------------------------------+
void UpdatePanel()
  {
   // Account balance
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   string currency = AccountInfoString(ACCOUNT_CURRENCY);
   ObjectSetString(0, PFX + "ValAcct", OBJPROP_TEXT,
                   DoubleToString(balance, 2) + " " + currency);

   // Auto-detect symbol properties from broker specifications
   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double tickSize     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   // Display contract size and tick info for verification
   ObjectSetString(0, PFX + "ValContract", OBJPROP_TEXT,
                   DoubleToString(contractSize, 2));
   ObjectSetString(0, PFX + "ValTickInfo", OBJPROP_TEXT,
                   DoubleToString(tickSize, _Digits) + " / " +
                   DoubleToString(tickValue, 4) + " " + currency);

   // Calculate monetary value per tick per lot
   // MT5's SYMBOL_TRADE_TICK_VALUE = contractSize * tickSize / <conversion>
   // This already accounts for contract size and currency conversion
   // So: loss per lot = numberOfTicks * tickValue
   double moneyPerTickPerLot = tickValue;  // already includes contract size

   // Calculate and display lot size
   double lots = 0;
   string warning = "";
   bool   clamped = false;
   double slTotalTicks = 0;

   if(g_mode == MODE_MARKET)
     {
      slTotalTicks = g_slTicks;
      if(slTotalTicks > 0 && moneyPerTickPerLot > 0)
        {
         double riskMoney     = balance * g_riskPct / 100.0;
         double slMoneyPerLot = slTotalTicks * moneyPerTickPerLot;
         lots = riskMoney / slMoneyPerLot;
         lots = ClampLots(lots, clamped);
         if(clamped)
           {
            double actualRisk = lots * slMoneyPerLot;
            double actualPct  = (balance > 0) ? (actualRisk / balance * 100.0) : 0;
            warning = "Risk adjusted to " + DoubleToString(actualPct, 2) + "% due to lot limits";
           }
        }
     }
   else // LIMIT mode
     {
      if(g_entryPrice > 0 && g_slPrice > 0 && tickSize > 0 &&
         MathAbs(g_entryPrice - g_slPrice) > 0)
        {
         slTotalTicks = MathAbs(g_entryPrice - g_slPrice) / tickSize;
         if(moneyPerTickPerLot > 0)
           {
            double riskMoney     = balance * g_riskPct / 100.0;
            double slMoneyPerLot = slTotalTicks * moneyPerTickPerLot;
            if(slMoneyPerLot > 0)
              {
               lots = riskMoney / slMoneyPerLot;
               lots = ClampLots(lots, clamped);
               if(clamped)
                 {
                  double actualRisk = lots * slMoneyPerLot;
                  double actualPct  = (balance > 0) ? (actualRisk / balance * 100.0) : 0;
                  warning = "Risk adjusted to " + DoubleToString(actualPct, 2) + "% due to lot limits";
                 }
              }
           }
        }
     }

   // Display lot size
   ObjectSetString(0, PFX + "ValCalcLots", OBJPROP_TEXT,
                   (lots > 0) ? DoubleToString(lots, 2) : "---");

   // Display risk amount
   double riskAmt = (lots > 0 && slTotalTicks > 0) ?
                    lots * slTotalTicks * moneyPerTickPerLot : 0;
   ObjectSetString(0, PFX + "ValCalcRisk", OBJPROP_TEXT,
                   (riskAmt > 0) ? (DoubleToString(riskAmt, 2) + " " + currency) : "---");

   ObjectSetString(0, PFX + "LblWarn", OBJPROP_TEXT, warning);

   // Update BE status display
   if(g_beEnabled)
     {
      string currentStatus = ObjectGetString(0, PFX + "ValBEStatus", OBJPROP_TEXT);
      if(StringFind(currentStatus, "BE applied") < 0)
        {
         ObjectSetString(0, PFX + "ValBEStatus", OBJPROP_TEXT, "Monitoring...");
         ObjectSetInteger(0, PFX + "ValBEStatus", OBJPROP_COLOR, clrLime);
        }
     }
   else
     {
      ObjectSetString(0, PFX + "ValBEStatus", OBJPROP_TEXT, "Disabled");
      ObjectSetInteger(0, PFX + "ValBEStatus", OBJPROP_COLOR, clrGray);
     }

   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Check and apply Break-Even SL for open positions                   |
//+------------------------------------------------------------------+
void CheckBreakEven()
  {
   if(!g_beEnabled)
      return;

   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0)
      return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;

      // Only manage positions on the current symbol
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;

      // Only manage positions placed by this EA (check comment)
      string comment = PositionGetString(POSITION_COMMENT);
      if(StringFind(comment, "PositionSizer") < 0)
         continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      long   posType   = PositionGetInteger(POSITION_TYPE);

      // Skip if SL is already at or beyond entry (break-even already applied)
      if(posType == POSITION_TYPE_BUY && currentSL >= openPrice)
         continue;
      if(posType == POSITION_TYPE_SELL && currentSL > 0 && currentSL <= openPrice)
         continue;

      // Determine the trigger price for this position
      // If user set a specific BE trigger price, use it; otherwise use ticks
      double triggerPrice = 0;

      if(g_bePrice > 0)
        {
         // User specified an explicit trigger price — use it directly
         triggerPrice = g_bePrice;
        }
      else
        {
         // Calculate trigger from ticks relative to entry
         double triggerDistance = g_beTicks * tickSize;
         if(posType == POSITION_TYPE_BUY)
            triggerPrice = openPrice + triggerDistance;
         else
            triggerPrice = openPrice - triggerDistance;
        }

      // Check if current price has reached the trigger
      double currentPrice = 0;
      if(posType == POSITION_TYPE_BUY)
         currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      else
         currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      bool triggered = false;
      if(posType == POSITION_TYPE_BUY && currentPrice >= triggerPrice)
         triggered = true;
      if(posType == POSITION_TYPE_SELL && currentPrice <= triggerPrice)
         triggered = true;

      if(triggered)
        {
         // Move SL to entry price (break-even)
         double newSL = NormalizeDouble(openPrice, _Digits);

         if(trade.PositionModify(ticket, newSL, currentTP))
           {
            string dirStr = (posType == POSITION_TYPE_BUY) ? "Buy" : "Sell";
            Print("Break-Even applied: ", dirStr, " #", ticket,
                  " SL moved to entry ", DoubleToString(newSL, _Digits));

            // Update status on panel
            ObjectSetString(0, PFX + "ValBEStatus", OBJPROP_TEXT,
                           "BE applied #" + IntegerToString((int)ticket));
            ObjectSetInteger(0, PFX + "ValBEStatus", OBJPROP_COLOR, clrYellow);
           }
         else
           {
            Print("Break-Even modify failed for #", ticket,
                  " Error: ", GetLastError());
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Clamp lots to broker min/max/step                                  |
//+------------------------------------------------------------------+
double ClampLots(double lots, bool &wasClamped)
  {
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   wasClamped = false;

   // Round to lot step
   if(lotStep > 0)
      lots = MathFloor(lots / lotStep) * lotStep;

   // Clamp
   if(lots < minLot)
     {
      lots = minLot;
      wasClamped = true;
     }
   if(lots > maxLot)
     {
      lots = maxLot;
      wasClamped = true;
     }

   // Normalize
   lots = NormalizeDouble(lots, 2);
   return lots;
  }

//+------------------------------------------------------------------+
//| Handle button and object clicks                                    |
//+------------------------------------------------------------------+
void HandleClick(const string objName)
  {
   // Mode toggles
   if(objName == PFX + "BtnMarket")
     {
      g_mode = MODE_MARKET;
      ObjectSetInteger(0, PFX + "BtnMarket", OBJPROP_BGCOLOR, clrDodgerBlue);
      ObjectSetInteger(0, PFX + "BtnLimit",  OBJPROP_BGCOLOR, clrGray);
      SetModeVisibility();
      ObjectSetInteger(0, PFX + "BtnMarket", OBJPROP_STATE, false);
      UpdatePanel();
      return;
     }
   if(objName == PFX + "BtnLimit")
     {
      g_mode = MODE_LIMIT;
      ObjectSetInteger(0, PFX + "BtnLimit",  OBJPROP_BGCOLOR, clrDodgerBlue);
      ObjectSetInteger(0, PFX + "BtnMarket", OBJPROP_BGCOLOR, clrGray);
      SetModeVisibility();
      ObjectSetInteger(0, PFX + "BtnLimit", OBJPROP_STATE, false);
      UpdatePanel();
      return;
     }

   // Break-Even toggle
   if(objName == PFX + "BtnBE")
     {
      g_beEnabled = !g_beEnabled;
      ObjectSetString(0, PFX + "BtnBE", OBJPROP_TEXT, g_beEnabled ? "ON" : "OFF");
      ObjectSetInteger(0, PFX + "BtnBE", OBJPROP_BGCOLOR, g_beEnabled ? clrGreen : clrGray);
      ObjectSetInteger(0, PFX + "BtnBE", OBJPROP_STATE, false);
      UpdatePanel();
      return;
     }

   // Buy / Sell
   if(objName == PFX + "BtnBuy")
     {
      ObjectSetInteger(0, PFX + "BtnBuy", OBJPROP_STATE, false);
      ShowOrderConfirmation(1);
      return;
     }
   if(objName == PFX + "BtnSell")
     {
      ObjectSetInteger(0, PFX + "BtnSell", OBJPROP_STATE, false);
      ShowOrderConfirmation(-1);
      return;
     }

   // Confirmation
   if(objName == PFX + "BtnConfirm")
     {
      ObjectSetInteger(0, PFX + "BtnConfirm", OBJPROP_STATE, false);
      ExecuteOrder(g_confirmDirection);
      ShowConfirmation(false);
      return;
     }
   if(objName == PFX + "BtnCancel")
     {
      ObjectSetInteger(0, PFX + "BtnCancel", OBJPROP_STATE, false);
      ShowConfirmation(false);
      return;
     }
  }

//+------------------------------------------------------------------+
//| Handle edit field changes                                          |
//+------------------------------------------------------------------+
void HandleEditEnd(const string objName)
  {
   if(objName == PFX + "EdtRisk")
      g_riskPct = StringToDouble(ObjectGetString(0, objName, OBJPROP_TEXT));

   if(objName == PFX + "EdtSLTicks")
      g_slTicks = (int)StringToInteger(ObjectGetString(0, objName, OBJPROP_TEXT));

   if(objName == PFX + "EdtTPTicks")
      g_tpTicks = (int)StringToInteger(ObjectGetString(0, objName, OBJPROP_TEXT));

   if(objName == PFX + "EdtEntry")
      g_entryPrice = StringToDouble(ObjectGetString(0, objName, OBJPROP_TEXT));

   if(objName == PFX + "EdtSLPrice")
      g_slPrice = StringToDouble(ObjectGetString(0, objName, OBJPROP_TEXT));

   if(objName == PFX + "EdtTPPrice")
      g_tpPrice = StringToDouble(ObjectGetString(0, objName, OBJPROP_TEXT));

   // Break-Even fields
   if(objName == PFX + "EdtBETicks")
      g_beTicks = (int)StringToInteger(ObjectGetString(0, objName, OBJPROP_TEXT));

   if(objName == PFX + "EdtBEPrice")
      g_bePrice = StringToDouble(ObjectGetString(0, objName, OBJPROP_TEXT));
  }

//+------------------------------------------------------------------+
//| Show/hide fields based on mode                                     |
//+------------------------------------------------------------------+
void SetModeVisibility()
  {
   bool isMarket = (g_mode == MODE_MARKET);

   // Market-specific
   SetObjVisible(PFX + "LblSLTicks",  isMarket);
   SetObjVisible(PFX + "EdtSLTicks",  isMarket);
   SetObjVisible(PFX + "LblTPTicks",  isMarket);
   SetObjVisible(PFX + "EdtTPTicks",  isMarket);

   // Limit-specific
   SetObjVisible(PFX + "LblEntry",    !isMarket);
   SetObjVisible(PFX + "EdtEntry",    !isMarket);
   SetObjVisible(PFX + "LblSLPrice",  !isMarket);
   SetObjVisible(PFX + "EdtSLPrice",  !isMarket);
   SetObjVisible(PFX + "LblTPPrice",  !isMarket);
   SetObjVisible(PFX + "EdtTPPrice",  !isMarket);
  }

//+------------------------------------------------------------------+
//| Show order confirmation overlay                                    |
//+------------------------------------------------------------------+
void ShowOrderConfirmation(int direction)
  {
   g_confirmDirection = direction;
   g_confirmShowing   = true;

   string dirStr = (direction > 0) ? "BUY" : "SELL";

   // Calculate lots for display
   double lots = CalculateLots();
   double entry = 0, sl = 0, tp = 0;

   if(g_mode == MODE_MARKET)
     {
      double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
      entry = (direction > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = (direction > 0) ? entry - g_slTicks * tickSize
                           : entry + g_slTicks * tickSize;
      if(g_tpTicks > 0)
         tp = (direction > 0) ? entry + g_tpTicks * tickSize
                              : entry - g_tpTicks * tickSize;
     }
   else
     {
      entry = g_entryPrice;
      sl    = g_slPrice;
      tp    = g_tpPrice;
     }

   string modeStr = (g_mode == MODE_MARKET) ? "MARKET" : "LIMIT";

   ObjectSetString(0, PFX + "ConfText1", OBJPROP_TEXT,
                   modeStr + " " + dirStr + "  |  " + DoubleToString(lots, 2) + " lots");
   ObjectSetString(0, PFX + "ConfText2", OBJPROP_TEXT,
                   "Entry: " + DoubleToString(entry, _Digits) +
                   "  SL: " + DoubleToString(sl, _Digits));
   ObjectSetString(0, PFX + "ConfText3", OBJPROP_TEXT,
                   (tp > 0) ? ("TP: " + DoubleToString(tp, _Digits)) : "TP: None");

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt = balance * g_riskPct / 100.0;
   ObjectSetString(0, PFX + "ConfText4", OBJPROP_TEXT,
                   "Risk: " + DoubleToString(g_riskPct, 2) + "% = " +
                   DoubleToString(riskAmt, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY));

   // Show BE info in confirmation
   if(g_beEnabled)
     {
      string beInfo = "Break-Even: ON | Trigger: ";
      if(g_bePrice > 0)
         beInfo += DoubleToString(g_bePrice, _Digits);
      else
         beInfo += IntegerToString(g_beTicks) + " ticks";
      ObjectSetString(0, PFX + "ConfText5", OBJPROP_TEXT, beInfo);
     }
   else
      ObjectSetString(0, PFX + "ConfText5", OBJPROP_TEXT, "Break-Even: OFF");

   ShowConfirmation(true);
  }

//+------------------------------------------------------------------+
//| Show or hide confirmation overlay objects                          |
//+------------------------------------------------------------------+
void ShowConfirmation(bool show)
  {
   g_confirmShowing = show;
   SetObjVisible(PFX + "ConfBG",      show);
   SetObjVisible(PFX + "ConfText1",   show);
   SetObjVisible(PFX + "ConfText2",   show);
   SetObjVisible(PFX + "ConfText3",   show);
   SetObjVisible(PFX + "ConfText4",   show);
   SetObjVisible(PFX + "ConfText5",   show);
   SetObjVisible(PFX + "BtnConfirm",  show);
   SetObjVisible(PFX + "BtnCancel",   show);
  }

//+------------------------------------------------------------------+
//| Calculate lot size                                                 |
//+------------------------------------------------------------------+
double CalculateLots()
  {
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double tickSize   = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   // tickValue from MT5 = monetary value of 1 tick movement for 1 standard lot
   // It already incorporates contract size and currency conversion
   // Formula: lots = riskMoney / (slTicks * tickValue)
   double riskMoney  = balance * g_riskPct / 100.0;
   double lots       = 0;
   bool   clamped    = false;

   if(g_mode == MODE_MARKET)
     {
      if(g_slTicks > 0 && tickValue > 0)
        {
         double slMoneyPerLot = g_slTicks * tickValue;
         lots = riskMoney / slMoneyPerLot;
        }
     }
   else
     {
      if(g_entryPrice > 0 && g_slPrice > 0 && tickSize > 0 && tickValue > 0)
        {
         double slDistTicks   = MathAbs(g_entryPrice - g_slPrice) / tickSize;
         double slMoneyPerLot = slDistTicks * tickValue;
         if(slMoneyPerLot > 0)
            lots = riskMoney / slMoneyPerLot;
        }
     }

   lots = ClampLots(lots, clamped);
   return lots;
  }

//+------------------------------------------------------------------+
//| Execute order                                                      |
//+------------------------------------------------------------------+
void ExecuteOrder(int direction)
  {
   double lots = CalculateLots();
   if(lots <= 0)
     {
      Alert("Cannot place order: lot size is zero. Check your inputs.");
      return;
     }

   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double entry = 0, sl = 0, tp = 0;
   bool result = false;

   if(g_mode == MODE_MARKET)
     {
      // Market order
      entry = (direction > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                              : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = (direction > 0) ? entry - g_slTicks * tickSize
                           : entry + g_slTicks * tickSize;
      if(g_tpTicks > 0)
         tp = (direction > 0) ? entry + g_tpTicks * tickSize
                              : entry - g_tpTicks * tickSize;

      // Normalize
      sl = NormalizeDouble(sl, _Digits);
      tp = NormalizeDouble(tp, _Digits);

      if(direction > 0)
         result = trade.Buy(lots, _Symbol, 0, sl, tp, "PositionSizer Buy");
      else
         result = trade.Sell(lots, _Symbol, 0, sl, tp, "PositionSizer Sell");
     }
   else
     {
      // Limit order
      entry = NormalizeDouble(g_entryPrice, _Digits);
      sl    = NormalizeDouble(g_slPrice, _Digits);
      tp    = (g_tpPrice > 0) ? NormalizeDouble(g_tpPrice, _Digits) : 0;

      double currentAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double currentBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(direction > 0)
        {
         // Buy Limit: entry below current ask
         if(entry < currentAsk)
            result = trade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "PositionSizer BuyLimit");
         // Buy Stop: entry above current ask
         else
            result = trade.BuyStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "PositionSizer BuyStop");
        }
      else
        {
         // Sell Limit: entry above current bid
         if(entry > currentBid)
            result = trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "PositionSizer SellLimit");
         // Sell Stop: entry below current bid
         else
            result = trade.SellStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "PositionSizer SellStop");
        }
     }

   if(result)
     {
      string modeStr = (g_mode == MODE_MARKET) ? "Market" : "Limit";
      string dirStr  = (direction > 0) ? "Buy" : "Sell";
      Alert(modeStr + " " + dirStr + " order placed: " +
            DoubleToString(lots, 2) + " lots at " +
            DoubleToString(entry, _Digits) +
            " SL=" + DoubleToString(sl, _Digits) +
            ((tp > 0) ? (" TP=" + DoubleToString(tp, _Digits)) : ""));
     }
   else
     {
      Alert("Order failed! Error: " + IntegerToString(GetLastError()) +
            " | Retcode: " + IntegerToString(trade.ResultRetcode()) +
            " | " + trade.ResultRetcodeDescription());
     }
  }

//+------------------------------------------------------------------+
//| Helper: Create rectangle label                                     |
//+------------------------------------------------------------------+
void CreateRect(const string name, int x, int y, int w, int h, color clr)
  {
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrGray);
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
//| Helper: Create label                                               |
//+------------------------------------------------------------------+
void CreateLabel(const string name, int x, int y, string text, color clr, int fontSize, bool bold)
  {
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
   ObjectSetString(0, name, OBJPROP_FONT, bold ? "Arial Bold" : "Arial");
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
//| Helper: Create button                                              |
//+------------------------------------------------------------------+
void CreateButton(const string name, int x, int y, int w, int h, string text, color bgClr)
  {
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgClr);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
//| Helper: Create edit field                                          |
//+------------------------------------------------------------------+
void CreateEdit(const string name, int x, int y, int w, int h, string text)
  {
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_EDIT, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
   ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
   ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clrGray);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_READONLY, false);
  }

//+------------------------------------------------------------------+
//| Helper: Set object visibility                                      |
//+------------------------------------------------------------------+
void SetObjVisible(const string name, bool visible)
  {
   if(ObjectFind(0, name) < 0)
      return;
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
  }
//+------------------------------------------------------------------+
