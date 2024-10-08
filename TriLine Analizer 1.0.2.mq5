//+------------------------------------------------------------------+
//|                  TriLine Analyzer Completo con Depuración        |
//|                                  Copyright 2024, Tu Nombre Aquí  |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property copyright "Copyright 2024, Carlos Arturo Garzon"
#property link      "sedsist@gmail.com"
#property version   "1.06"
#property strict
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   5

//--- plot Linea Superior
#property indicator_label1  "Linea Superior"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrRed
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

//--- plot Linea Inferior
#property indicator_label2  "Linea Inferior"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrGreen
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

//--- plot Linea Media
#property indicator_label3  "Linea Media"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrBlue
#property indicator_style3  STYLE_SOLID
#property indicator_width3  1

//--- plot Texto Alcista
#property indicator_label4  "Texto Alcista"
#property indicator_type4   DRAW_NONE

//--- plot Texto Bajista
#property indicator_label5  "Texto Bajista"
#property indicator_type5   DRAW_NONE

//--- input parameters
input group "Configuración del Indicador"
input int    InpPeriodoAnalisis = 200;   // Número de velas a analizar (100-500)
input bool   InpUsarVolumen = false;     // Usar volumen para la línea media
input group "Ajustes de Volatilidad"
input int    InpPeriodoVolatilidad = 14; // Periodo para calcular la volatilidad
input double InpFactorAjuste = 1.5;      // Factor de ajuste para alta volatilidad
input group "Configuración de Detección de Patrones"
input int    InpPatronVelas = 50;        // Número de velas para buscar patrones
input double InpTolerancia = 0.1;        // Tolerancia para la detección de patrones (%)

//--- indicator buffers
double BufferSuperior[];
double BufferInferior[];
double BufferMedia[];
double BufferTextoAlcista[];
double BufferTextoBajista[];

// Estructura para almacenar la información de cada periodo
struct PeriodInfo
{
   string name;
   ENUM_TIMEFRAMES timeframe;
   double percentage;
   string trend;
   double prediction;
   double score;
};

PeriodInfo periods[] = {
   {"M1", PERIOD_M1, 0, "", 0, 0},
   {"M5", PERIOD_M5, 0, "", 0, 0},
   {"M15", PERIOD_M15, 0, "", 0, 0},
   {"M30", PERIOD_M30, 0, "", 0, 0},
   {"H1", PERIOD_H1, 0, "", 0, 0},
   {"H4", PERIOD_H4, 0, "", 0, 0},
   {"D1", PERIOD_D1, 0, "", 0, 0}
};

int g_atrHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Custom indicator initialization function                         |
//+------------------------------------------------------------------+
int OnInit()
{
   SetIndexBuffer(0, BufferSuperior, INDICATOR_DATA);
   SetIndexBuffer(1, BufferInferior, INDICATOR_DATA);
   SetIndexBuffer(2, BufferMedia, INDICATOR_DATA);
   SetIndexBuffer(3, BufferTextoAlcista, INDICATOR_DATA);
   SetIndexBuffer(4, BufferTextoBajista, INDICATOR_DATA);
   
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   
   PlotIndexSetDouble(0, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(1, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(2, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(3, PLOT_EMPTY_VALUE, 0.0);
   PlotIndexSetDouble(4, PLOT_EMPTY_VALUE, 0.0);
   
   IndicatorSetString(INDICATOR_SHORTNAME, "TriLine Analyzer");
   
   g_atrHandle = iATR(Symbol(), PERIOD_CURRENT, InpPeriodoVolatilidad);
   if(g_atrHandle == INVALID_HANDLE)
   {
      Print("Error al crear el handle de ATR: ", GetLastError());
      return(INIT_FAILED);
   }
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Custom indicator iteration function                              |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
{
   int calculados = MathMin(rates_total, InpPeriodoAnalisis);
   if(calculados < InpPeriodoAnalisis) return(0);
   
   int inicio = rates_total - calculados;
   
   ArrayInitialize(BufferSuperior, 0);
   ArrayInitialize(BufferInferior, 0);
   ArrayInitialize(BufferMedia, 0);
   ArrayInitialize(BufferTextoAlcista, EMPTY_VALUE);
   ArrayInitialize(BufferTextoBajista, EMPTY_VALUE);
   
   for(int i=0; i<ArraySize(periods); i++)
   {
      if(periods[i].timeframe == Period())
      {
         periods[i].percentage = CalcularLineas(high, low, close, volume, inicio, rates_total, true);
      }
      else
      {
         periods[i].percentage = CalcularLineaMultiperiodo(periods[i].timeframe);
      }
      
      periods[i].prediction = CalcularPrediccion(periods[i].timeframe, GetVelasParaPrediccion(periods[i].timeframe));
      
      // Añadir verificación
      if(periods[i].prediction == 0)
      {
         Print("Advertencia: Predicción cero para ", periods[i].name, " timeframe");
      }
      
      periods[i].trend = IdentificarTendencia(periods[i].percentage);
      periods[i].score = EvaluarPeriodo(periods[i]);
   }
   
   DetectarPatronesMultitemporal(close, high, low, time, rates_total);
   
   if(prev_calculated > 0 && rates_total > 1)
   {
      VerificarCruceYAlineacion(close, rates_total);
   }
   
   ActualizarTexto();
   
   return(rates_total);
}

//+------------------------------------------------------------------+
//| Calcula las líneas para un periodo específico                    |
//+------------------------------------------------------------------+
double CalcularLineas(const double &high[], const double &low[], const double &close[], 
                      const long &volume[], int inicio, int fin, bool dibujarLineas)
{
   double volatilidad = CalcularVolatilidad(close, inicio, fin - 1);
   double volatilidadPromedio = CalcularVolatilidad(close, MathMax(0, fin - InpPeriodoVolatilidad), fin - 1);
   
   double maximo = high[inicio];
   double minimo = low[inicio];
   for(int i = inicio + 1; i < fin; i++)
   {
      maximo = MathMax(maximo, high[i]);
      minimo = MathMin(minimo, low[i]);
   }
   
   if(volatilidad > volatilidadPromedio * InpFactorAjuste)
   {
      double rango = maximo - minimo;
      maximo += rango * 0.1;
      minimo -= rango * 0.1;
   }
   
   double media = 0;
   double conteo[100] = {0};
   double volumenTotal = 0;
   
   for(int i = 0; i < 100; i++)
   {
      double nivel = minimo + (maximo - minimo) * i / 99;
      for(int j = inicio; j < fin; j++)
      {
         if(low[j] <= nivel && high[j] >= nivel)
         {
            if(InpUsarVolumen)
            {
               conteo[i] += (double)volume[j];
               volumenTotal += (double)volume[j];
            }
            else
            {
               conteo[i]++;
            }
         }
      }
      if(conteo[i] > conteo[(int)media])
         media = i;
   }
   
   media = minimo + (maximo - minimo) * media / 99;
   
   double porcentajeMedia = (media - minimo) / (maximo - minimo) * 100;
   
   if(dibujarLineas)
   {
      for(int i = inicio; i < fin; i++)
      {
         BufferSuperior[i] = maximo;
         BufferInferior[i] = minimo;
         BufferMedia[i] = media;
      }
   }
   
   return porcentajeMedia;
}

//+------------------------------------------------------------------+
//| Calcula la línea media para un periodo específico                |
//+------------------------------------------------------------------+
double CalcularLineaMultiperiodo(ENUM_TIMEFRAMES periodo)
{
   int calculados = MathMin(InpPeriodoAnalisis, Bars(Symbol(), periodo));
   if(calculados < InpPeriodoAnalisis) return 0;
   
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copiado = CopyRates(Symbol(), periodo, 0, calculados, rates);
   
   if(copiado == calculados)
   {
      double high[], low[], close[];
      long volume[];
      ArrayResize(high, calculados);
      ArrayResize(low, calculados);
      ArrayResize(close, calculados);
      ArrayResize(volume, calculados);
      
      for(int i = 0; i < calculados; i++)
      {
         high[i] = rates[i].high;
         low[i] = rates[i].low;
         close[i] = rates[i].close;
         volume[i] = rates[i].tick_volume;
      }
      
      return CalcularLineas(high, low, close, volume, 0, calculados, false);
   }
   
   return 0;
}

//+------------------------------------------------------------------+
//| Calcula la volatilidad en un rango dado                          |
//+------------------------------------------------------------------+
double CalcularVolatilidad(const double &close[], int desde, int hasta)
{
   double suma = 0;
   for(int i = desde + 1; i <= hasta; i++)
   {
      suma += MathAbs(close[i] - close[i-1]);
   }
   return suma / (hasta - desde);
}

//+------------------------------------------------------------------+
//| Detecta patrones de inversión                                    |
//+------------------------------------------------------------------+
void DetectarPatronesMultitemporal(const double &close[], const double &high[], const double &low[], const datetime &time[], int total)
{
   int lookback = MathMin(total, InpPatronVelas);
   int ultimaSenal = -1;
   double escala = AjustarEscalaTemporalidad(Period());

   for(int i = lookback - 1; i >= 0; i--)
   {
      string patron = "";
      bool senalAlcista = false;
      bool senalBajista = false;

      if(DetectarDobleTecho(high, i, escala))
      {
         patron = "Doble Techo";
         senalBajista = true;
      }
      else if(DetectarDobleSuelo(low, i, escala))
      {
         patron = "Doble Suelo";
         senalAlcista = true;
      }
      else if(DetectarHCHAlcista(high, low, i, escala))
      {
         patron = "HCH Alcista";
         senalAlcista = true;
      }
      else if(DetectarHCHBajista(high, low, i, escala))
      {
         patron = "HCH Bajista";
         senalBajista = true;
      }

      if((senalAlcista || senalBajista) && (ultimaSenal == -1 || i < ultimaSenal - 5))
      {
         if(senalAlcista)
         {
            DibujarTexto(i, patron, true, low, high);
            Print("Señal alcista detectada: ", patron, " en ", TimeToString(time[i]));
            ultimaSenal = i;
         }
         else if(senalBajista)
         {
            DibujarTexto(i, patron, false, low, high);
            Print("Señal bajista detectada: ", patron, " en ", TimeToString(time[i]));
            ultimaSenal = i;
         }
      }
   }
}

//+------------------------------------------------------------------+
//| Dibuja texto en el gráfico                                       |
//+------------------------------------------------------------------+
void DibujarTexto(int indice, string texto, bool esAlcista, const double &low[], const double &high[])
{
   string nombre = "TriLine_Patron_" + IntegerToString(indice);
   double precio = esAlcista ? low[indice] : high[indice];
   color colorTexto = esAlcista ? clrLime : clrRed;
   
   ObjectCreate(0, nombre, OBJ_TEXT, 0, iTime(NULL, 0, indice), precio);
   ObjectSetString(0, nombre, OBJPROP_TEXT, texto);
   ObjectSetInteger(0, nombre, OBJPROP_COLOR, colorTexto);
   ObjectSetInteger(0, nombre, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, nombre, OBJPROP_ANCHOR, esAlcista ? ANCHOR_TOP : ANCHOR_BOTTOM);
}

//+------------------------------------------------------------------+
//| Detecta patrón de Doble Techo                                    |
//+------------------------------------------------------------------+
bool DetectarDobleTecho(const double &high[], int indice, double escala)
{
   if(indice < 5) return false;

   double pico1 = high[indice-4];
   double pico2 = high[indice];
   double valle = MathMin(high[indice-3], MathMin(high[indice-2], high[indice-1]));

   double toleranciaAjustada = InpTolerancia * escala;

   if(pico1 > valle && pico2 > valle &&
      MathAbs(pico1 - pico2) / pico1 < toleranciaAjustada &&
      (pico1 - valle) / pico1 > toleranciaAjustada / 2)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| Detecta patrón de Doble Suelo                                    |
//+------------------------------------------------------------------+
bool DetectarDobleSuelo(const double &low[], int indice, double escala)
{
   if(indice < 5) return false;

   double valle1 = low[indice-4];
   double valle2 = low[indice];
   double pico = MathMax(low[indice-3], MathMax(low[indice-2], low[indice-1]));

   double toleranciaAjustada = InpTolerancia * escala;

   if(valle1 < pico && valle2 < pico &&
      MathAbs(valle1 - valle2) / valle1 < toleranciaAjustada &&
      (pico - valle1) / valle1 > toleranciaAjustada / 2)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| Detecta patrón de Hombro-Cabeza-Hombro Alcista                   |
//+------------------------------------------------------------------+
bool DetectarHCHAlcista(const double &high[], const double &low[], int indice, double escala)
{
   if(indice < 7) return false;

   double hombro1 = low[indice-6];
   double cabeza = low[indice-3];
   double hombro2 = low[indice];
   double neckline = MathMax(high[indice-5], MathMax(high[indice-4], MathMax(high[indice-2], high[indice-1])));

   double toleranciaAjustada = InpTolerancia * escala;
   double diferenciaMinima = (neckline - cabeza) * escala;

   if(cabeza < hombro1 && cabeza < hombro2 &&
      MathAbs(hombro1 - hombro2) / hombro1 < toleranciaAjustada &&
      (neckline - cabeza) > diferenciaMinima &&
      (neckline - hombro1) > diferenciaMinima * 0.5 &&
      (neckline - hombro2) > diferenciaMinima * 0.5)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| Detecta patrón de Hombro-Cabeza-Hombro Bajista                   |
//+------------------------------------------------------------------+
bool DetectarHCHBajista(const double &high[], const double &low[], int indice, double escala)
{
   if(indice < 7) return false;

   double hombro1 = high[indice-6];
   double cabeza = high[indice-3];
   double hombro2 = high[indice];
   double neckline = MathMin(low[indice-5], MathMin(low[indice-4], MathMin(low[indice-2], low[indice-1])));

   double toleranciaAjustada = InpTolerancia * escala;
   double diferenciaMinima = (cabeza - neckline) * escala;

   if(cabeza > hombro1 && cabeza > hombro2 &&
      MathAbs(hombro1 - hombro2) / hombro1 < toleranciaAjustada &&
      (cabeza - neckline) > diferenciaMinima &&
      (hombro1 - neckline) > diferenciaMinima * 0.5 &&
      (hombro2 - neckline) > diferenciaMinima * 0.5)
      return true;

   return false;
}

//+------------------------------------------------------------------+
//| Ajusta la escala según la temporalidad                           |
//+------------------------------------------------------------------+
double AjustarEscalaTemporalidad(ENUM_TIMEFRAMES periodo)
{
   switch(periodo)
   {
      case PERIOD_M1:  return 0.05;
      case PERIOD_M5:  return 0.1;
      case PERIOD_M15: return 0.2;
      case PERIOD_M30: return 0.3;
      case PERIOD_H1:  return 0.4;
      case PERIOD_H4:  return 0.6;
      case PERIOD_D1:  return 0.8;
      case PERIOD_W1:  return 1.0;
      default:         return 1.0;
   }
}

//+------------------------------------------------------------------+
//| Identifica la tendencia para un porcentaje dado                  |
//+------------------------------------------------------------------+
string IdentificarTendencia(double porcentaje)
{
   if(porcentaje > 60)
      return "Alcista";
   else if(porcentaje < 40)
      return "Bajista";
   else
      return "Lateral";
}

//+------------------------------------------------------------------+
//| Calcula la predicción para un periodo específico                 |
//+------------------------------------------------------------------+
double CalcularPrediccion(ENUM_TIMEFRAMES periodo, int numVelas)
{
   MqlRates rates[];
   ArraySetAsSeries(rates, true);
   int copiado = CopyRates(Symbol(), periodo, 0, numVelas, rates);
   
   if(copiado != numVelas)
   {
      Print("Error al copiar datos históricos para el periodo ", EnumToString(periodo), ". Copiados: ", copiado, " de ", numVelas);
      return 0;
   }
   
   double suma = 0;
   int conteo = 0;
   double cambios[];
   ArrayResize(cambios, numVelas - 1);
   
   for(int i = 0; i < numVelas - 1; i++)
   {
      if(rates[i+1].close != 0)
      {
         double cambio = (rates[i].close - rates[i+1].close) / rates[i+1].close;
         cambio = MathMax(MathMin(cambio, 0.1), -0.1);  // Limitar a ±10%
         cambios[conteo] = cambio;
         suma += cambio;
         conteo++;
      }
   }
   
   if(conteo == 0)
   {
      Print("Advertencia: No se calcularon cambios para ", EnumToString(periodo));
      return rates[0].close;
   }
   
   ArraySort(cambios);
   double medianaCambio = (conteo % 2 == 0) ? 
      (cambios[conteo/2 - 1] + cambios[conteo/2]) / 2 : cambios[conteo/2];
   double mediaCambio = suma / conteo;
   
   double cambioPonderado = (medianaCambio * 0.7 + mediaCambio * 0.3);  // 70% mediana, 30% media
   
   string simbolo = Symbol();
   if(StringFind(simbolo, "Boom") != -1)
   {
      cambioPonderado = MathMin(cambioPonderado, 0);  // Tendencia a la baja
   }
   else if(StringFind(simbolo, "Crash") != -1)
   {
      cambioPonderado = MathMax(cambioPonderado, 0);  // Tendencia al alza
   }
   
   cambioPonderado = MathMax(MathMin(cambioPonderado, 0.05), -0.05);  // Limitar a ±5%
   
   double prediccion = rates[0].close * (1 + cambioPonderado);
   
   // Asegurar que la predicción sea diferente del precio actual
   if(MathAbs(prediccion - rates[0].close) / rates[0].close < 0.0001)
   {
      prediccion = rates[0].close * (1 + (cambioPonderado >= 0 ? 0.0001 : -0.0001));
   }
   
   Print("Predicción para ", EnumToString(periodo), ": ", prediccion, " (Cambio ponderado: ", cambioPonderado, ")");
   
   return prediccion;
}

//+------------------------------------------------------------------+
//| Evalúa un periodo y devuelve una puntuación                      |
//+------------------------------------------------------------------+
double EvaluarPeriodo(PeriodInfo &periodo)
{
   double score = 0;
   
   // Factor 1: Fuerza de la tendencia
   double fuerzaTendencia = MathAbs(periodo.percentage - 50) / 10;
   score += fuerzaTendencia * 2;  // Max 10 puntos
   
   // Factor 2: Alineación entre tendencia y predicción
   double cambioPredicho = 0;
   double precioActual = SymbolInfoDouble(Symbol(), SYMBOL_LAST);
   if(MathIsValidNumber(periodo.prediction) && precioActual != 0)
   {
      cambioPredicho = (periodo.prediction - precioActual) / precioActual * 100;
      cambioPredicho = MathMax(MathMin(cambioPredicho, 100), -100);  // Limitar a ±100%
   }
   
   if((periodo.percentage > 50 && cambioPredicho > 0) || (periodo.percentage < 50 && cambioPredicho < 0))
   {
      score += MathMin(MathAbs(cambioPredicho) / 10, 5);  // Max 5 puntos
   }
   
   // Factor 3: Volatilidad
   double volatilidad = ObtenerVolatilidad(periodo.timeframe, precioActual);
   double volatilidadNormalizada = MathMin(volatilidad, 0.05) / 0.05;  // Normalizar a escala 0-1
   score += (1 - volatilidadNormalizada) * 2.5;  // Max 2.5 puntos
   
   // Factor 4: Consistencia con periodos superiores
   int index = ArraySearch(periods, periodo.name);
   if(index < ArraySize(periods) - 1)
   {
      if(periodo.trend == periods[index + 1].trend)
      {
         score += 2.5;  // 2.5 puntos por consistencia con el periodo superior
      }
   }
   
   return MathMax(score, 0);  // Asegurar que el score no sea negativo
}

//+------------------------------------------------------------------+
//| Determina el número de velas para la predicción según el periodo |
//+------------------------------------------------------------------+
int GetVelasParaPrediccion(ENUM_TIMEFRAMES periodo)
{
   int velas = 1000;  // Valor por defecto
   
   switch(periodo)
   {
      case PERIOD_M1:  velas = 10000; break;
      case PERIOD_M5:  velas = 5000; break;
      case PERIOD_M15: velas = 3000; break;
      case PERIOD_M30: velas = 2000; break;
      case PERIOD_H1:  velas = 1000; break;
      case PERIOD_H4:  velas = 500; break;
      case PERIOD_D1:  velas = 250; break;
   }
   
   Print("Velas para predicción en ", EnumToString(periodo), ": ", velas);
   return velas;
}

//+------------------------------------------------------------------+
//| Verifica el cruce de la línea media y la alineación de tendencias|
//+------------------------------------------------------------------+
void VerificarCruceYAlineacion(const double &close[], int total)
{
   bool crucePorEncima = close[total-2] <= BufferMedia[total-2] && close[total-1] > BufferMedia[total-1];
   bool crucePorDebajo = close[total-2] >= BufferMedia[total-2] && close[total-1] < BufferMedia[total-1];
   
   string tendencia5M = periods[1].trend;
   string tendencia15M = periods[2].trend;
   string tendencia30M = periods[3].trend;
   
   bool tendenciasAlineadas = (tendencia5M == tendencia15M) && (tendencia15M == tendencia30M);
   
   if((crucePorEncima || crucePorDebajo) && tendenciasAlineadas)
   {
      string direccionCruce = crucePorEncima ? "por encima" : "por debajo";
      Alert("Precio cruzó la línea media ", direccionCruce, " en ", Symbol(), " ", EnumToString(Period()), 
            ". Tendencias alineadas (5M, 15M, 30M): ", tendencia5M);
      PlaySound("alert.wav");
   }
}

//+------------------------------------------------------------------+
//| Actualiza el texto en el gráfico                                 |
//+------------------------------------------------------------------+
void ActualizarTexto()
{
   for(int i=0; i<ArraySize(periods); i++)
   {
      ObjectDelete(0, "TriLine_InfoText_" + periods[i].name);
   }
   
   int mejorPeriodoIndex = 0;
   double mejorScore = 0;
   for(int i=0; i<ArraySize(periods); i++)
   {
      if(periods[i].score > mejorScore)
      {
         mejorScore = periods[i].score;
         mejorPeriodoIndex = i;
      }
   }
   
   for(int i=0; i<ArraySize(periods); i++)
   {
      string objectName = "TriLine_InfoText_" + periods[i].name;
      double precioActual = SymbolInfoDouble(Symbol(), SYMBOL_LAST);
      double cambioPredicho = 0;
      
      if(periods[i].prediction > 0 && precioActual > 0)
      {
         cambioPredicho = (periods[i].prediction - precioActual) / precioActual * 100;
         cambioPredicho = MathRound(cambioPredicho * 100) / 100;  // Redondear a 2 decimales
      }
      else
      {
         Print("Error en el cálculo de cambio predicho para ", periods[i].name, 
               ". Predicción: ", periods[i].prediction, ", Precio actual: ", precioActual);
      }
      
      string textoInfo = StringFormat("%s: %.2f%% - %s (Pred: %.2f%%) Score: %.2f", 
                                      periods[i].name, 
                                      periods[i].percentage, 
                                      periods[i].trend,
                                      cambioPredicho,
                                      periods[i].score);
      
      if(!ObjectCreate(0, objectName, OBJ_LABEL, 0, 0, 0))
      {
         Print("Error al crear el objeto de texto ", objectName, ": ", GetLastError());
         continue;
      }
      
      color textColor = (i == mejorPeriodoIndex) ? clrLime : clrWhite;
      
      ObjectSetString(0, objectName, OBJPROP_TEXT, textoInfo);
      ObjectSetInteger(0, objectName, OBJPROP_XDISTANCE, 10);
      ObjectSetInteger(0, objectName, OBJPROP_YDISTANCE, 30 + i*20);
      ObjectSetInteger(0, objectName, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, objectName, OBJPROP_FONTSIZE, 9);
      ObjectSetInteger(0, objectName, OBJPROP_COLOR, textColor);
      ObjectSetInteger(0, objectName, OBJPROP_BGCOLOR, clrBlack);
      ObjectSetInteger(0, objectName, OBJPROP_BORDER_COLOR, clrNONE);
      ObjectSetInteger(0, objectName, OBJPROP_BACK, false);
      ObjectSetInteger(0, objectName, OBJPROP_SELECTABLE, false);
      
      Print("Texto actualizado: ", textoInfo);
   }
   
   double confianza;
   double precioActual = SymbolInfoDouble(Symbol(), SYMBOL_LAST);
   string sugerencia = DeterminarSugerencia(periods[mejorPeriodoIndex].percentage, 
                                            periods[mejorPeriodoIndex].prediction, 
                                            precioActual, 
                                            confianza);
   
   string objectNameSugerencia = "TriLine_InfoText_Sugerencia";
   string textoSugerencia = StringFormat("Sugerencia: %s (Confianza: %.2f%%) Mejor periodo: %s", 
                                         sugerencia, confianza, periods[mejorPeriodoIndex].name);
   
   if(!ObjectCreate(0, objectNameSugerencia, OBJ_LABEL, 0, 0, 0))
   {
      Print("Error al crear el objeto de texto ", objectNameSugerencia, ": ", GetLastError());
      return;
   }
   
   ObjectSetString(0, objectNameSugerencia, OBJPROP_TEXT, textoSugerencia);
   ObjectSetInteger(0, objectNameSugerencia, OBJPROP_XDISTANCE, 10);
   ObjectSetInteger(0, objectNameSugerencia, OBJPROP_YDISTANCE, 30 + ArraySize(periods)*20 + 20);
   ObjectSetInteger(0, objectNameSugerencia, OBJPROP_CORNER, CORNER_LEFT_UPPER);
   ObjectSetInteger(0, objectNameSugerencia, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, objectNameSugerencia, OBJPROP_COLOR, clrYellow);
   ObjectSetInteger(0, objectNameSugerencia, OBJPROP_BGCOLOR, clrBlack);
   ObjectSetInteger(0, objectNameSugerencia, OBJPROP_BORDER_COLOR, clrNONE);
   ObjectSetInteger(0, objectNameSugerencia, OBJPROP_BACK, false);
   ObjectSetInteger(0, objectNameSugerencia, OBJPROP_SELECTABLE, false);
   
   Print("Texto de sugerencia actualizado: ", textoSugerencia);
}

//+------------------------------------------------------------------+
//| Determina la sugerencia de compra/venta con predicción           |
//+------------------------------------------------------------------+
string DeterminarSugerencia(double porcentajeMedia, double prediccion, double precioActual, double &confianza)
{
   double cambioPredicho = 0;
   if(MathIsValidNumber(prediccion) && precioActual != 0)
   {
      cambioPredicho = (prediccion - precioActual) / precioActual * 100;
      cambioPredicho = MathMax(MathMin(cambioPredicho, 100), -100);  // Limitar a ±100%
   }
   
   double fuerzaTendencia = MathAbs(porcentajeMedia - 50) / 10;  // 0 a 5
   double fuerzaPrediccion = MathAbs(cambioPredicho) / 20;  // 0 a 5
   
   if(porcentajeMedia > 55 && cambioPredicho > 0)
   {
      confianza = (fuerzaTendencia + fuerzaPrediccion) * 10;  // 0 a 100
      return "Comprar";
   }
   else if(porcentajeMedia < 45 && cambioPredicho < 0)
   {
      confianza = (fuerzaTendencia + fuerzaPrediccion) * 10;  // 0 a 100
      return "Vender";
   }
   else
   {
      confianza = MathMax((50 - MathAbs(porcentajeMedia - 50)) * 2, 0);  // Mayor confianza en el centro
      return "Neutral";
   }
}

//+------------------------------------------------------------------+
//| Obtiene la volatilidad utilizando ATR                            |
//+------------------------------------------------------------------+
double ObtenerVolatilidad(ENUM_TIMEFRAMES periodo, double precioActual)
{
   double atrBuffer[];
   ArraySetAsSeries(atrBuffer, true);
   int copied = CopyBuffer(g_atrHandle, 0, 0, 1, atrBuffer);
   
   if(copied != 1)
   {
      Print("Error al copiar datos de ATR: ", GetLastError());
      return 0.01; // Valor por defecto en caso de error
   }

   return atrBuffer[0] / precioActual;
}

//+------------------------------------------------------------------+
//| Función auxiliar para buscar un periodo en el array              |
//+------------------------------------------------------------------+
int ArraySearch(const PeriodInfo &arr[], string value)
{
   for(int i = 0; i < ArraySize(arr); i++)
   {
      if(arr[i].name == value)
         return i;
   }
   return -1;
}

//+------------------------------------------------------------------+
//| Custom indicator deinitialization function                       |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   ObjectsDeleteAll(0, "TriLine_");
   if(g_atrHandle != INVALID_HANDLE)
   {
      IndicatorRelease(g_atrHandle);
   }
}