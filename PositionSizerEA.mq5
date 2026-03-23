//+------------------------------------------------------------------+
//|                                           PositionSizerEA.mq5    |
//|  v1.30 - Compact/Draggable/Minimizable panel + chart lines       |
//+------------------------------------------------------------------+
#property copyright "Position Sizer EA"
#property version   "1.30"
#property description "Risk-based position sizing with compact draggable panel"
#property strict

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Enums                                                              |
//+------------------------------------------------------------------+
enum ENUM_ORDER_MODE
  {
   MODE_MARKET = 0,
   MODE_LIMIT  = 1
  };

//+------------------------------------------------------------------+
//| Input Parameters                                                   |
//+------------------------------------------------------------------+
input group "=== General Settings ==="
input ENUM_ORDER_MODE InpDefaultMode     = MODE_MARKET;
input double           InpDefaultRiskPct  = 1.0;
input color            InpPanelColor      = clrDarkSlateGray;
input color            InpTextColor       = clrWhite;
input color            InpBuyColor        = clrDodgerBlue;
input color            InpSellColor       = clrCrimson;
input int              InpPanelX          = 20;
input int              InpPanelY          = 50;

input group "=== Market Mode Defaults ==="
input int              InpDefaultSLTicks  = 100;
input int              InpDefaultTPTicks  = 0;

input group "=== Limit Mode Defaults ==="
input double           InpDefaultEntry    = 0.0;
input double           InpDefaultSLPrice  = 0.0;
input double           InpDefaultTPPrice  = 0.0;

input group "=== Break-Even Defaults ==="
input bool             InpDefaultBEOn     = false;
input int              InpDefaultBETicks  = 50;
input double           InpDefaultBEPrice  = 0.0;

input group "=== Line Colors ==="
input color            InpEntryLineColor  = clrDodgerBlue;
input color            InpSLLineColor     = clrCrimson;
input color            InpTPLineColor     = clrLime;
input color            InpBELineColor     = clrYellow;
input color            InpBETrigLineColor = clrOrange;

//+------------------------------------------------------------------+
//| Constants                                                          |
//+------------------------------------------------------------------+
const int PANEL_W  = 310;
const int FIELD_H  = 20;
const int LABEL_W  = 120;
const int INPUT_W  = 155;
const int BTN_W    = 138;
const int BTN_H    = 28;
const int MARGIN   = 8;
const int ROW_H    = 24;
const int TITLE_H  = 26;

//+------------------------------------------------------------------+
//| Global Variables                                                   |
//+------------------------------------------------------------------+
CTrade trade;

// State
ENUM_ORDER_MODE g_mode;
double g_riskPct;
int    g_slTicks;
int    g_tpTicks;
double g_entryPrice;
double g_slPrice;
double g_tpPrice;
bool   g_confirmShowing = false;
int    g_confirmDirection = 0;

// Break-Even
bool   g_beEnabled;
int    g_beTicks;
double g_bePrice;

// Panel state
int    g_panelX;
int    g_panelY;
int    g_panelH = 100;
bool   g_minimized = false;
bool   g_dragging  = false;
int    g_dragOffsetX = 0;
int    g_dragOffsetY = 0;

// Prefixes
const string PFX     = "PS_";
const string LINE_PFX = "PSL_";
const string LINE_ENTRY      = "PSL_Entry";
const string LINE_SL         = "PSL_SL";
const string LINE_TP         = "PSL_TP";
const string LINE_BE_LEVEL   = "PSL_BELevel";
const string LINE_BE_TRIGGER = "PSL_BETrigger";

//+------------------------------------------------------------------+
//| Expert initialization                                              |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_mode       = InpDefaultMode;
   g_riskPct    = InpDefaultRiskPct;
   g_slTicks    = InpDefaultSLTicks;
   g_tpTicks    = InpDefaultTPTicks;
   g_entryPrice = InpDefaultEntry;
   g_slPrice    = InpDefaultSLPrice;
   g_tpPrice    = InpDefaultTPPrice;
   g_beEnabled  = InpDefaultBEOn;
   g_beTicks    = InpDefaultBETicks;
   g_bePrice    = InpDefaultBEPrice;
   g_panelX     = InpPanelX;
   g_panelY     = InpPanelY;

   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   ChartSetInteger(0, CHART_EVENT_OBJECT_CREATE, true);

   CreateChartLines();
   RebuildPanel();

   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
//| Expert deinitialization                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, PFX);
   ObjectsDeleteAll(0, LINE_PFX);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
  {
   UpdateLiveValues();
   UpdateChartLines();
   CheckBreakEven();
  }

//+------------------------------------------------------------------+
//| Chart event handler                                                |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
   // Mouse events for dragging
   if(id == CHARTEVENT_MOUSE_MOVE)
     {
      int mouseX = (int)lparam;
      int mouseY = (int)dparam;
      int mouseState = (int)sparam;

      if(g_dragging)
        {
         if((mouseState & 1) == 1) // left button held
           {
            g_panelX = mouseX - g_dragOffsetX;
            g_panelY = mouseY - g_dragOffsetY;
            if(g_panelX < 0) g_panelX = 0;
            if(g_panelY < 0) g_panelY = 0;
            RebuildPanel();
           }
         else
           {
            g_dragging = false;
            ChartSetInteger(0, CHART_MOUSE_SCROLL, true);
           }
        }
     }

   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      // Title bar click = start drag or toggle minimize
      if(sparam == PFX + "TitleBar" || sparam == PFX + "TitleText")
        {
         // Use minimize button for minimize, title for drag
        }
      if(sparam == PFX + "BtnMin")
        {
         g_minimized = !g_minimized;
         ObjectSetInteger(0, PFX + "BtnMin", OBJPROP_STATE, false);
         RebuildPanel();
         ChartRedraw();
         return;
        }
      HandleClick(sparam);
      ChartRedraw();
     }

   if(id == CHARTEVENT_OBJECT_ENDEDIT)
     {
      HandleEditEnd(sparam);
      UpdateLiveValues();
      UpdateChartLines();
      ChartRedraw();
     }

   if(id == CHARTEVENT_OBJECT_DRAG)
     {
      HandleLineDrag(sparam);
      UpdateLiveValues();
      UpdateChartLines();
      ChartRedraw();
     }

   // Detect mouse down on title bar for dragging
   if(id == CHARTEVENT_MOUSE_MOVE)
     {
      int mouseX = (int)lparam;
      int mouseY = (int)dparam;
      int mouseState = (int)sparam;

      if(!g_dragging && (mouseState & 1) == 1)
        {
         // Check if mouse is on title bar area
         if(mouseX >= g_panelX && mouseX <= g_panelX + PANEL_W &&
            mouseY >= g_panelY && mouseY <= g_panelY + TITLE_H)
           {
            g_dragging = true;
            g_dragOffsetX = mouseX - g_panelX;
            g_dragOffsetY = mouseY - g_panelY;
            ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Rebuild entire panel dynamically (no gaps)                         |
//+------------------------------------------------------------------+
void RebuildPanel()
  {
   // Delete all panel objects and recreate
   ObjectsDeleteAll(0, PFX);

   int x = g_panelX;
   int y = g_panelY;
   int row = y;

   // --- Title Bar ---
   CreateRect(PFX + "TitleBar", x, row, PANEL_W, TITLE_H, clrDarkBlue);
   CreateLabel(PFX + "TitleText", x + MARGIN, row + 5, "POSITION SIZER EA", clrWhite, 9, true);
   // Minimize button
   CreateButton(PFX + "BtnMin", x + PANEL_W - 30, row + 2, 26, TITLE_H - 4,
                g_minimized ? "+" : "-", clrDarkBlue);
   row += TITLE_H;

   if(g_minimized)
     {
      // Just show the title bar
      g_panelH = TITLE_H;
      ChartRedraw();
      return;
     }

   // --- Panel Body Background (create FIRST so it's behind all content) ---
   // Use large temp height; will resize at end
   CreateRect(PFX + "BG", x, row, PANEL_W, 600, InpPanelColor);
   int bodyStart = row;

   // --- Mode Toggle ---
   row += 4;
   CreateButton(PFX + "BtnMarket", x + MARGIN, row, BTN_W, BTN_H, "MARKET",
                (g_mode == MODE_MARKET) ? clrDodgerBlue : clrGray);
   CreateButton(PFX + "BtnLimit", x + MARGIN + BTN_W + 6, row, BTN_W, BTN_H, "LIMIT",
                (g_mode == MODE_LIMIT) ? clrDodgerBlue : clrGray);
   row += BTN_H + 6;

   // --- Separator ---
   CreateRect(PFX + "Sep1", x + MARGIN, row, PANEL_W - 2 * MARGIN, 1, clrGray);
   row += 5;

   // --- Account Info (compact) ---
   CreateLabel(PFX + "LblAcct", x + MARGIN, row, "Balance:", InpTextColor, 8, false);
   CreateLabel(PFX + "ValAcct", x + MARGIN + 55, row, "---", clrLime, 8, true);
   CreateLabel(PFX + "LblSymbol2", x + MARGIN + 175, row, _Symbol, clrLime, 8, true);
   row += ROW_H - 4;

   CreateLabel(PFX + "LblContract", x + MARGIN, row, "Contract:", InpTextColor, 8, false);
   CreateLabel(PFX + "ValContract", x + MARGIN + 55, row, "---", clrLime, 8, false);
   CreateLabel(PFX + "LblPtVal", x + MARGIN + 120, row, "Pt Val:", InpTextColor, 8, false);
   CreateLabel(PFX + "ValPtVal", x + MARGIN + 160, row, "---", clrLime, 8, false);
   row += ROW_H - 4;

   // --- Separator ---
   CreateRect(PFX + "Sep2", x + MARGIN, row, PANEL_W - 2 * MARGIN, 1, clrGray);
   row += 5;

   // --- Risk input (always shown) ---
   CreateLabel(PFX + "LblRisk", x + MARGIN, row, "Risk %:", InpTextColor, 9, false);
   CreateEdit(PFX + "EdtRisk", x + MARGIN + LABEL_W + 5, row, INPUT_W, FIELD_H,
              DoubleToString(g_riskPct, 2));
   row += ROW_H;

   // --- Mode-specific fields (compact, no gaps) ---
   if(g_mode == MODE_MARKET)
     {
      CreateLabel(PFX + "LblSLTicks", x + MARGIN, row, "SL (ticks):", InpTextColor, 9, false);
      CreateEdit(PFX + "EdtSLTicks", x + MARGIN + LABEL_W + 5, row, INPUT_W, FIELD_H,
                 IntegerToString(g_slTicks));
      row += ROW_H;

      // Calculated SL prices
      CreateLabel(PFX + "LblMktSLPrice", x + MARGIN, row, "  -> SL Price:", clrGray, 8, false);
      CreateLabel(PFX + "ValMktSLBuy", x + MARGIN + LABEL_W + 5, row, "---", InpSLLineColor, 8, false);
      CreateLabel(PFX + "LblMktSLSep", x + MARGIN + LABEL_W + 78, row, "|", clrGray, 8, false);
      CreateLabel(PFX + "ValMktSLSell", x + MARGIN + LABEL_W + 88, row, "---", InpSLLineColor, 8, false);
      row += ROW_H - 4;

      CreateLabel(PFX + "LblTPTicks", x + MARGIN, row, "TP (ticks, 0=none):", InpTextColor, 9, false);
      CreateEdit(PFX + "EdtTPTicks", x + MARGIN + LABEL_W + 5, row, INPUT_W, FIELD_H,
                 IntegerToString(g_tpTicks));
      row += ROW_H;

      // Calculated TP prices
      CreateLabel(PFX + "LblMktTPPrice", x + MARGIN, row, "  -> TP Price:", clrGray, 8, false);
      CreateLabel(PFX + "ValMktTPBuy", x + MARGIN + LABEL_W + 5, row, "---", InpTPLineColor, 8, false);
      CreateLabel(PFX + "LblMktTPSep", x + MARGIN + LABEL_W + 78, row, "|", clrGray, 8, false);
      CreateLabel(PFX + "ValMktTPSell", x + MARGIN + LABEL_W + 88, row, "---", InpTPLineColor, 8, false);
      row += ROW_H - 4;
     }
   else // LIMIT mode
     {
      CreateLabel(PFX + "LblEntry", x + MARGIN, row, "Entry Price:", InpTextColor, 9, false);
      CreateEdit(PFX + "EdtEntry", x + MARGIN + LABEL_W + 5, row, INPUT_W, FIELD_H,
                 DoubleToString(g_entryPrice, _Digits));
      row += ROW_H;

      CreateLabel(PFX + "LblSLPrice", x + MARGIN, row, "SL Price:", InpTextColor, 9, false);
      CreateEdit(PFX + "EdtSLPrice", x + MARGIN + LABEL_W + 5, row, INPUT_W, FIELD_H,
                 DoubleToString(g_slPrice, _Digits));
      row += ROW_H;

      CreateLabel(PFX + "LblTPPrice", x + MARGIN, row, "TP (0=none):", InpTextColor, 9, false);
      CreateEdit(PFX + "EdtTPPrice", x + MARGIN + LABEL_W + 5, row, INPUT_W, FIELD_H,
                 DoubleToString(g_tpPrice, _Digits));
      row += ROW_H;
     }

   // --- Separator ---
   CreateRect(PFX + "Sep3", x + MARGIN, row, PANEL_W - 2 * MARGIN, 1, clrGray);
   row += 5;

   // --- Calculated Info ---
   CreateLabel(PFX + "LblCalcLots", x + MARGIN, row, "Lot Size:", InpTextColor, 9, false);
   CreateLabel(PFX + "ValCalcLots", x + MARGIN + LABEL_W + 5, row, "---", clrYellow, 9, true);
   row += ROW_H;

   CreateLabel(PFX + "LblCalcRisk", x + MARGIN, row, "Risk Amount:", InpTextColor, 9, false);
   CreateLabel(PFX + "ValCalcRisk", x + MARGIN + LABEL_W + 5, row, "---", clrYellow, 9, true);
   row += ROW_H;

   CreateLabel(PFX + "LblWarn", x + MARGIN, row, "", clrOrangeRed, 8, false);
   row += 16;

   // --- Separator ---
   CreateRect(PFX + "Sep4", x + MARGIN, row, PANEL_W - 2 * MARGIN, 1, clrGray);
   row += 5;

   // --- Break-Even Section ---
   CreateLabel(PFX + "LblBETitle", x + MARGIN, row, "BREAK EVEN", InpTextColor, 9, true);
   CreateButton(PFX + "BtnBE", x + MARGIN + 90, row - 2, 55, 20,
                g_beEnabled ? "ON" : "OFF",
                g_beEnabled ? clrGreen : clrGray);
   row += ROW_H;

   CreateLabel(PFX + "LblBETicks", x + MARGIN, row, "Trigger (ticks):", InpTextColor, 8, false);
   CreateEdit(PFX + "EdtBETicks", x + MARGIN + LABEL_W + 5, row, INPUT_W, FIELD_H,
              IntegerToString(g_beTicks));
   row += ROW_H;

   CreateLabel(PFX + "LblBEPrice", x + MARGIN, row, "Trigger Price:", InpTextColor, 8, false);
   CreateEdit(PFX + "EdtBEPrice", x + MARGIN + LABEL_W + 5, row, INPUT_W, FIELD_H,
              (g_bePrice > 0) ? DoubleToString(g_bePrice, _Digits) : "0");
   row += ROW_H;

   CreateLabel(PFX + "LblBEStatus", x + MARGIN, row, "Status:", InpTextColor, 8, false);
   CreateLabel(PFX + "ValBEStatus", x + MARGIN + 50, row,
              g_beEnabled ? "Monitoring..." : "Disabled",
              g_beEnabled ? clrLime : clrGray, 8, false);
   row += ROW_H - 2;

   // --- Separator ---
   CreateRect(PFX + "Sep5", x + MARGIN, row, PANEL_W - 2 * MARGIN, 1, clrGray);
   row += 5;

   // --- Buy / Sell ---
   CreateButton(PFX + "BtnBuy", x + MARGIN, row, BTN_W, BTN_H + 2, "BUY", InpBuyColor);
   CreateButton(PFX + "BtnSell", x + MARGIN + BTN_W + 6, row, BTN_W, BTN_H + 2, "SELL", InpSellColor);
   row += BTN_H + 8;

   // --- Resize panel background to actual content height ---
   g_panelH = row - y;
   ObjectSetInteger(0, PFX + "BG", OBJPROP_YSIZE, g_panelH - TITLE_H);

   // --- Confirmation overlay (hidden) ---
   int confY = y + TITLE_H + 30;
   CreateRect(PFX + "ConfBG", x + 5, confY, PANEL_W - 10, 130, clrBlack);
   CreateLabel(PFX + "ConfText1", x + 15, confY + 8, "", clrWhite, 9, false);
   CreateLabel(PFX + "ConfText2", x + 15, confY + 28, "", clrWhite, 9, false);
   CreateLabel(PFX + "ConfText3", x + 15, confY + 48, "", clrWhite, 9, false);
   CreateLabel(PFX + "ConfText4", x + 15, confY + 68, "", clrYellow, 9, true);
   CreateLabel(PFX + "ConfText5", x + 15, confY + 86, "", clrLime, 8, false);
   CreateButton(PFX + "BtnConfirm", x + 15, confY + 104, 130, BTN_H, "CONFIRM", clrGreen);
   CreateButton(PFX + "BtnCancel", x + 155, confY + 104, 130, BTN_H, "CANCEL", clrGray);
   ShowConfirmation(false);

   UpdateLiveValues();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Update live values (called on tick and after edits)                |
//+------------------------------------------------------------------+
void UpdateLiveValues()
  {
   if(g_minimized) return;

   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   string currency = AccountInfoString(ACCOUNT_CURRENCY);

   // Only update if objects exist
   if(ObjectFind(0, PFX + "ValAcct") < 0) return;

   ObjectSetString(0, PFX + "ValAcct", OBJPROP_TEXT,
                   DoubleToString(balance, 2) + " " + currency);

   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double tickSize     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);

   // Calculate moneyPerPointPerLot
   double rawPointValue = (tickSize > 0) ? (tickValue / tickSize) : 0;
   double moneyPerPointPerLot = 0;
   if(rawPointValue > 0 && contractSize > 0)
     {
      if(rawPointValue >= contractSize * 0.5)
         moneyPerPointPerLot = rawPointValue;
      else
         moneyPerPointPerLot = contractSize * rawPointValue;
     }
   if(moneyPerPointPerLot <= 0)
      moneyPerPointPerLot = contractSize;

   ObjectSetString(0, PFX + "ValContract", OBJPROP_TEXT, DoubleToString(contractSize, 0));
   ObjectSetString(0, PFX + "ValPtVal", OBJPROP_TEXT,
                   "$" + DoubleToString(moneyPerPointPerLot, 2));

   // Lot calculation
   double lots = 0;
   string warning = "";
   bool   clamped = false;
   double slPriceDistance = 0;

   if(g_mode == MODE_MARKET)
     {
      slPriceDistance = g_slTicks * tickSize;
      if(slPriceDistance > 0 && moneyPerPointPerLot > 0)
        {
         double riskMoney     = balance * g_riskPct / 100.0;
         double slMoneyPerLot = slPriceDistance * moneyPerPointPerLot;
         lots = riskMoney / slMoneyPerLot;
         lots = ClampLots(lots, clamped);
         if(clamped)
           {
            double actualRisk = lots * slMoneyPerLot;
            double actualPct  = (balance > 0) ? (actualRisk / balance * 100.0) : 0;
            warning = "Adj to " + DoubleToString(actualPct, 2) + "% (lot limits)";
           }
        }
     }
   else
     {
      if(g_entryPrice > 0 && g_slPrice > 0 &&
         MathAbs(g_entryPrice - g_slPrice) > 0)
        {
         slPriceDistance = MathAbs(g_entryPrice - g_slPrice);
         if(moneyPerPointPerLot > 0)
           {
            double riskMoney     = balance * g_riskPct / 100.0;
            double slMoneyPerLot = slPriceDistance * moneyPerPointPerLot;
            if(slMoneyPerLot > 0)
              {
               lots = riskMoney / slMoneyPerLot;
               lots = ClampLots(lots, clamped);
               if(clamped)
                 {
                  double actualRisk = lots * slMoneyPerLot;
                  double actualPct  = (balance > 0) ? (actualRisk / balance * 100.0) : 0;
                  warning = "Adj to " + DoubleToString(actualPct, 2) + "% (lot limits)";
                 }
              }
           }
        }
     }

   ObjectSetString(0, PFX + "ValCalcLots", OBJPROP_TEXT,
                   (lots > 0) ? DoubleToString(lots, 2) : "---");

   double riskAmt = (lots > 0 && slPriceDistance > 0) ?
                    lots * slPriceDistance * moneyPerPointPerLot : 0;
   ObjectSetString(0, PFX + "ValCalcRisk", OBJPROP_TEXT,
                   (riskAmt > 0) ? (DoubleToString(riskAmt, 2) + " " + currency) : "---");

   ObjectSetString(0, PFX + "LblWarn", OBJPROP_TEXT, warning);

   // Market mode SL/TP price display
   if(g_mode == MODE_MARKET && tickSize > 0)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

      if(g_slTicks > 0 && ObjectFind(0, PFX + "ValMktSLBuy") >= 0)
        {
         double slBuy  = NormalizeDouble(ask - g_slTicks * tickSize, _Digits);
         double slSell = NormalizeDouble(bid + g_slTicks * tickSize, _Digits);
         ObjectSetString(0, PFX + "ValMktSLBuy", OBJPROP_TEXT,
                         "B:" + DoubleToString(slBuy, _Digits));
         ObjectSetString(0, PFX + "ValMktSLSell", OBJPROP_TEXT,
                         "S:" + DoubleToString(slSell, _Digits));
        }

      if(g_tpTicks > 0 && ObjectFind(0, PFX + "ValMktTPBuy") >= 0)
        {
         double tpBuy  = NormalizeDouble(ask + g_tpTicks * tickSize, _Digits);
         double tpSell = NormalizeDouble(bid - g_tpTicks * tickSize, _Digits);
         ObjectSetString(0, PFX + "ValMktTPBuy", OBJPROP_TEXT,
                         "B:" + DoubleToString(tpBuy, _Digits));
         ObjectSetString(0, PFX + "ValMktTPSell", OBJPROP_TEXT,
                         "S:" + DoubleToString(tpSell, _Digits));
        }
      else if(ObjectFind(0, PFX + "ValMktTPBuy") >= 0)
        {
         ObjectSetString(0, PFX + "ValMktTPBuy", OBJPROP_TEXT, "---");
         ObjectSetString(0, PFX + "ValMktTPSell", OBJPROP_TEXT, "---");
        }
     }

   // BE status
   if(g_beEnabled)
     {
      string cs = ObjectGetString(0, PFX + "ValBEStatus", OBJPROP_TEXT);
      if(StringFind(cs, "BE applied") < 0)
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
  }

//+------------------------------------------------------------------+
//| Create chart lines                                                 |
//+------------------------------------------------------------------+
void CreateChartLines()
  {
   CreateHLine(LINE_ENTRY, 0, InpEntryLineColor, STYLE_SOLID, 2, true, "Entry");
   CreateHLine(LINE_SL, 0, InpSLLineColor, STYLE_SOLID, 2, true, "SL");
   CreateHLine(LINE_TP, 0, InpTPLineColor, STYLE_SOLID, 2, true, "TP");
   CreateHLine(LINE_BE_LEVEL, 0, InpBELineColor, STYLE_DOT, 1, false, "BE Level");
   CreateHLine(LINE_BE_TRIGGER, 0, InpBETrigLineColor, STYLE_DASH, 2, true, "BE Trigger");
  }

void CreateHLine(const string name, double price, color clr, ENUM_LINE_STYLE style,
                 int width, bool draggable, string tooltip)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
   ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, (style == STYLE_SOLID) ? width : 1);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, draggable);
   ObjectSetInteger(0, name, OBJPROP_SELECTED, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
  }

//+------------------------------------------------------------------+
//| Update chart lines                                                 |
//+------------------------------------------------------------------+
void UpdateChartLines()
  {
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double entryLine = 0, slLine = 0, tpLine = 0;
   bool   showEntry = false, showSL = false, showTP = false;
   bool   showBELevel = false, showBETrigger = false;
   bool   entryDraggable = true;

   if(g_mode == MODE_MARKET)
     {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      entryLine = NormalizeDouble((ask + bid) / 2.0, _Digits);
      entryDraggable = false;
      showEntry = true;

      if(g_slTicks > 0 && tickSize > 0)
        { slLine = NormalizeDouble(entryLine - g_slTicks * tickSize, _Digits); showSL = true; }
      if(g_tpTicks > 0 && tickSize > 0)
        { tpLine = NormalizeDouble(entryLine + g_tpTicks * tickSize, _Digits); showTP = true; }
     }
   else
     {
      entryDraggable = true;
      if(g_entryPrice > 0) { entryLine = NormalizeDouble(g_entryPrice, _Digits); showEntry = true; }
      if(g_slPrice > 0)    { slLine = NormalizeDouble(g_slPrice, _Digits); showSL = true; }
      if(g_tpPrice > 0)    { tpLine = NormalizeDouble(g_tpPrice, _Digits); showTP = true; }
     }

   // Entry
   if(showEntry)
     {
      ObjectSetDouble(0, LINE_ENTRY, OBJPROP_PRICE, 0, entryLine);
      ObjectSetString(0, LINE_ENTRY, OBJPROP_TOOLTIP, "Entry: " + DoubleToString(entryLine, _Digits));
      ObjectSetInteger(0, LINE_ENTRY, OBJPROP_SELECTABLE, entryDraggable);
      ObjectSetInteger(0, LINE_ENTRY, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
     }
   else ObjectSetInteger(0, LINE_ENTRY, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);

   if(showSL)
     {
      ObjectSetDouble(0, LINE_SL, OBJPROP_PRICE, 0, slLine);
      ObjectSetString(0, LINE_SL, OBJPROP_TOOLTIP, "SL: " + DoubleToString(slLine, _Digits));
      ObjectSetInteger(0, LINE_SL, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
     }
   else ObjectSetInteger(0, LINE_SL, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);

   if(showTP)
     {
      ObjectSetDouble(0, LINE_TP, OBJPROP_PRICE, 0, tpLine);
      ObjectSetString(0, LINE_TP, OBJPROP_TOOLTIP, "TP: " + DoubleToString(tpLine, _Digits));
      ObjectSetInteger(0, LINE_TP, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
     }
   else ObjectSetInteger(0, LINE_TP, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);

   // BE lines
   if(g_beEnabled && showEntry)
     {
      ObjectSetDouble(0, LINE_BE_LEVEL, OBJPROP_PRICE, 0, entryLine);
      ObjectSetString(0, LINE_BE_LEVEL, OBJPROP_TOOLTIP, "BE Level: " + DoubleToString(entryLine, _Digits));
      ObjectSetInteger(0, LINE_BE_LEVEL, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);

      double beTriggerPrice = 0;
      if(g_bePrice > 0) beTriggerPrice = g_bePrice;
      else if(g_beTicks > 0 && tickSize > 0 && entryLine > 0)
         beTriggerPrice = NormalizeDouble(entryLine + g_beTicks * tickSize, _Digits);

      if(beTriggerPrice > 0)
        {
         ObjectSetDouble(0, LINE_BE_TRIGGER, OBJPROP_PRICE, 0, beTriggerPrice);
         ObjectSetString(0, LINE_BE_TRIGGER, OBJPROP_TOOLTIP, "BE Trigger: " + DoubleToString(beTriggerPrice, _Digits));
         ObjectSetInteger(0, LINE_BE_TRIGGER, OBJPROP_TIMEFRAMES, OBJ_ALL_PERIODS);
         showBETrigger = true;
        }
      showBELevel = true;
     }
   if(!showBELevel)   ObjectSetInteger(0, LINE_BE_LEVEL, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
   if(!showBETrigger) ObjectSetInteger(0, LINE_BE_TRIGGER, OBJPROP_TIMEFRAMES, OBJ_NO_PERIODS);
  }

//+------------------------------------------------------------------+
//| Handle line drag                                                   |
//+------------------------------------------------------------------+
void HandleLineDrag(const string objName)
  {
   double newPrice = NormalizeDouble(ObjectGetDouble(0, objName, OBJPROP_PRICE, 0), _Digits);
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);

   if(objName == LINE_ENTRY && g_mode == MODE_LIMIT)
     {
      g_entryPrice = newPrice;
      RebuildPanel();
      return;
     }
   if(objName == LINE_SL)
     {
      if(g_mode == MODE_MARKET)
        {
         double mid = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) + SymbolInfoDouble(_Symbol, SYMBOL_BID)) / 2.0;
         if(tickSize > 0) { g_slTicks = (int)MathRound(MathAbs(mid - newPrice) / tickSize); if(g_slTicks < 1) g_slTicks = 1; }
        }
      else g_slPrice = newPrice;
      RebuildPanel();
      return;
     }
   if(objName == LINE_TP)
     {
      if(g_mode == MODE_MARKET)
        {
         double mid = (SymbolInfoDouble(_Symbol, SYMBOL_ASK) + SymbolInfoDouble(_Symbol, SYMBOL_BID)) / 2.0;
         if(tickSize > 0) { g_tpTicks = (int)MathRound(MathAbs(newPrice - mid) / tickSize); if(g_tpTicks < 1) g_tpTicks = 1; }
        }
      else g_tpPrice = newPrice;
      RebuildPanel();
      return;
     }
   if(objName == LINE_BE_TRIGGER)
     {
      g_bePrice = newPrice;
      double entryRef = (g_mode == MODE_MARKET) ?
         (SymbolInfoDouble(_Symbol, SYMBOL_ASK) + SymbolInfoDouble(_Symbol, SYMBOL_BID)) / 2.0 : g_entryPrice;
      if(tickSize > 0 && entryRef > 0)
         g_beTicks = (int)MathRound(MathAbs(newPrice - entryRef) / tickSize);
      RebuildPanel();
      return;
     }
  }

//+------------------------------------------------------------------+
//| Check Break-Even                                                   |
//+------------------------------------------------------------------+
void CheckBreakEven()
  {
   if(!g_beEnabled) return;
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0) return;

   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol) continue;
      if(StringFind(PositionGetString(POSITION_COMMENT), "PositionSizer") < 0) continue;

      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);
      long   posType   = PositionGetInteger(POSITION_TYPE);

      if(posType == POSITION_TYPE_BUY && currentSL >= openPrice) continue;
      if(posType == POSITION_TYPE_SELL && currentSL > 0 && currentSL <= openPrice) continue;

      double triggerPrice = 0;
      if(g_bePrice > 0) triggerPrice = g_bePrice;
      else
        {
         double d = g_beTicks * tickSize;
         triggerPrice = (posType == POSITION_TYPE_BUY) ? openPrice + d : openPrice - d;
        }

      double cp = (posType == POSITION_TYPE_BUY) ?
         SymbolInfoDouble(_Symbol, SYMBOL_BID) : SymbolInfoDouble(_Symbol, SYMBOL_ASK);

      bool triggered = (posType == POSITION_TYPE_BUY && cp >= triggerPrice) ||
                       (posType == POSITION_TYPE_SELL && cp <= triggerPrice);

      if(triggered)
        {
         double newSL = NormalizeDouble(openPrice, _Digits);
         if(trade.PositionModify(ticket, newSL, currentTP))
           {
            Print("BE applied #", ticket, " SL->", DoubleToString(newSL, _Digits));
            if(ObjectFind(0, PFX + "ValBEStatus") >= 0)
              {
               ObjectSetString(0, PFX + "ValBEStatus", OBJPROP_TEXT, "BE applied #" + IntegerToString((int)ticket));
               ObjectSetInteger(0, PFX + "ValBEStatus", OBJPROP_COLOR, clrYellow);
              }
           }
         else Print("BE failed #", ticket, " Err:", GetLastError());
        }
     }
  }

//+------------------------------------------------------------------+
//| Clamp lots                                                         |
//+------------------------------------------------------------------+
double ClampLots(double lots, bool &wasClamped)
  {
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   wasClamped = false;
   if(step > 0) lots = MathFloor(lots / step) * step;
   if(lots < minLot) { lots = minLot; wasClamped = true; }
   if(lots > maxLot) { lots = maxLot; wasClamped = true; }
   return NormalizeDouble(lots, 2);
  }

//+------------------------------------------------------------------+
//| Handle clicks                                                      |
//+------------------------------------------------------------------+
void HandleClick(const string objName)
  {
   if(objName == PFX + "BtnMarket")
     {
      g_mode = MODE_MARKET;
      ObjectSetInteger(0, PFX + "BtnMarket", OBJPROP_STATE, false);
      RebuildPanel();
      UpdateChartLines();
      return;
     }
   if(objName == PFX + "BtnLimit")
     {
      g_mode = MODE_LIMIT;
      ObjectSetInteger(0, PFX + "BtnLimit", OBJPROP_STATE, false);
      RebuildPanel();
      UpdateChartLines();
      return;
     }
   if(objName == PFX + "BtnBE")
     {
      g_beEnabled = !g_beEnabled;
      ObjectSetInteger(0, PFX + "BtnBE", OBJPROP_STATE, false);
      RebuildPanel();
      UpdateChartLines();
      return;
     }
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
//| Handle edit end                                                    |
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
   if(objName == PFX + "EdtBETicks")
      g_beTicks = (int)StringToInteger(ObjectGetString(0, objName, OBJPROP_TEXT));
   if(objName == PFX + "EdtBEPrice")
      g_bePrice = StringToDouble(ObjectGetString(0, objName, OBJPROP_TEXT));
  }

//+------------------------------------------------------------------+
//| Show order confirmation                                            |
//+------------------------------------------------------------------+
void ShowOrderConfirmation(int direction)
  {
   g_confirmDirection = direction;
   string dirStr = (direction > 0) ? "BUY" : "SELL";
   double lots = CalculateLots();
   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double entry = 0, sl = 0, tp = 0;

   if(g_mode == MODE_MARKET)
     {
      entry = (direction > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = (direction > 0) ? entry - g_slTicks * tickSize : entry + g_slTicks * tickSize;
      if(g_tpTicks > 0) tp = (direction > 0) ? entry + g_tpTicks * tickSize : entry - g_tpTicks * tickSize;
     }
   else { entry = g_entryPrice; sl = g_slPrice; tp = g_tpPrice; }

   string modeStr = (g_mode == MODE_MARKET) ? "MKT" : "LMT";
   ObjectSetString(0, PFX + "ConfText1", OBJPROP_TEXT,
                   modeStr + " " + dirStr + " | " + DoubleToString(lots, 2) + " lots");
   ObjectSetString(0, PFX + "ConfText2", OBJPROP_TEXT,
                   "Entry: " + DoubleToString(entry, _Digits) + "  SL: " + DoubleToString(sl, _Digits));
   ObjectSetString(0, PFX + "ConfText3", OBJPROP_TEXT,
                   (tp > 0) ? ("TP: " + DoubleToString(tp, _Digits)) : "TP: None");
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmt = balance * g_riskPct / 100.0;
   ObjectSetString(0, PFX + "ConfText4", OBJPROP_TEXT,
                   "Risk: " + DoubleToString(g_riskPct, 2) + "% = " +
                   DoubleToString(riskAmt, 2) + " " + AccountInfoString(ACCOUNT_CURRENCY));
   if(g_beEnabled)
     {
      string bi = "BE: ON | ";
      bi += (g_bePrice > 0) ? DoubleToString(g_bePrice, _Digits) : (IntegerToString(g_beTicks) + " ticks");
      ObjectSetString(0, PFX + "ConfText5", OBJPROP_TEXT, bi);
     }
   else ObjectSetString(0, PFX + "ConfText5", OBJPROP_TEXT, "BE: OFF");

   ShowConfirmation(true);
  }

void ShowConfirmation(bool show)
  {
   g_confirmShowing = show;
   string objs[] = {"ConfBG","ConfText1","ConfText2","ConfText3","ConfText4","ConfText5","BtnConfirm","BtnCancel"};
   for(int i = 0; i < ArraySize(objs); i++)
      SetObjVisible(PFX + objs[i], show);
  }

//+------------------------------------------------------------------+
//| Calculate lots                                                     |
//+------------------------------------------------------------------+
double CalculateLots()
  {
   double balance      = AccountInfoDouble(ACCOUNT_BALANCE);
   double tickSize     = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue    = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double contractSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_CONTRACT_SIZE);
   double riskMoney    = balance * g_riskPct / 100.0;

   double rawPV = (tickSize > 0) ? (tickValue / tickSize) : 0;
   double mpp = 0;
   if(rawPV > 0 && contractSize > 0)
     { if(rawPV >= contractSize * 0.5) mpp = rawPV; else mpp = contractSize * rawPV; }
   if(mpp <= 0) mpp = contractSize;

   double lots = 0;
   bool clamped = false;

   if(g_mode == MODE_MARKET)
     {
      double d = g_slTicks * tickSize;
      if(d > 0 && mpp > 0) lots = riskMoney / (d * mpp);
     }
   else
     {
      if(g_entryPrice > 0 && g_slPrice > 0)
        {
         double d = MathAbs(g_entryPrice - g_slPrice);
         if(d > 0 && mpp > 0) lots = riskMoney / (d * mpp);
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
   if(lots <= 0) { Alert("Lot size is zero. Check inputs."); return; }

   double tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double entry = 0, sl = 0, tp = 0;
   bool result = false;

   if(g_mode == MODE_MARKET)
     {
      entry = (direction > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK) : SymbolInfoDouble(_Symbol, SYMBOL_BID);
      sl = (direction > 0) ? entry - g_slTicks * tickSize : entry + g_slTicks * tickSize;
      if(g_tpTicks > 0) tp = (direction > 0) ? entry + g_tpTicks * tickSize : entry - g_tpTicks * tickSize;
      sl = NormalizeDouble(sl, _Digits);
      tp = NormalizeDouble(tp, _Digits);
      result = (direction > 0) ? trade.Buy(lots, _Symbol, 0, sl, tp, "PositionSizer Buy")
                               : trade.Sell(lots, _Symbol, 0, sl, tp, "PositionSizer Sell");
     }
   else
     {
      entry = NormalizeDouble(g_entryPrice, _Digits);
      sl    = NormalizeDouble(g_slPrice, _Digits);
      tp    = (g_tpPrice > 0) ? NormalizeDouble(g_tpPrice, _Digits) : 0;
      double cAsk = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double cBid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(direction > 0)
         result = (entry < cAsk) ? trade.BuyLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "PositionSizer BuyLimit")
                                 : trade.BuyStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "PositionSizer BuyStop");
      else
         result = (entry > cBid) ? trade.SellLimit(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "PositionSizer SellLimit")
                                 : trade.SellStop(lots, entry, _Symbol, sl, tp, ORDER_TIME_GTC, 0, "PositionSizer SellStop");
     }

   if(result)
      Alert((g_mode==MODE_MARKET?"Market":"Limit"), " ", (direction>0?"Buy":"Sell"),
            " placed: ", DoubleToString(lots,2), " lots @ ", DoubleToString(entry,_Digits),
            " SL=", DoubleToString(sl,_Digits), (tp>0?" TP="+DoubleToString(tp,_Digits):""));
   else
      Alert("Order failed! Error:", GetLastError(), " | ", trade.ResultRetcodeDescription());
  }

//+------------------------------------------------------------------+
//| Helpers                                                            |
//+------------------------------------------------------------------+
void CreateRect(const string name, int x, int y, int w, int h, color clr)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
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

void CreateLabel(const string name, int x, int y, string text, color clr, int fontSize, bool bold)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
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

void CreateButton(const string name, int x, int y, int w, int h, string text, color bgClr)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
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

void CreateEdit(const string name, int x, int y, int w, int h, string text)
  {
   if(ObjectFind(0, name) >= 0) ObjectDelete(0, name);
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

void SetObjVisible(const string name, bool visible)
  {
   if(ObjectFind(0, name) < 0) return;
   ObjectSetInteger(0, name, OBJPROP_TIMEFRAMES, visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
  }
//+------------------------------------------------------------------+
